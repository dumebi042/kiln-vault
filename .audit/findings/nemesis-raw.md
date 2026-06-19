# N E M E S I S - Raw Working Notes

Date: 2026-06-19

## Source-Matched Scope

Nemesis was run only on the contracts whose local bodies were previously matched to deployed source or deployed executable logic:

- `extracted/Vault.sol`
- `extracted/VaultFactory.sol`
- `extracted/FeeDispatcher.sol`
- `extracted/BlockList.sol`
- `extracted/BlockListFactory.sol`
- `extracted/ExternalAccessControl.sol`

The bounty document was read before this pass. The relevant kill rules are:

- Known issues from external audits are not reward-eligible.
- Admin/proxy-admin/privileged-role behavior is out of scope unless the contract is explicitly designed to prevent that privileged access from enabling the attack.
- Rounding errors are explicitly out of scope.
- Critical/High/Medium submissions require a PoC.

ConnectorRegistry and connector implementations are in bounty scope, but their deployed source was not proven matched in this run, so Nemesis did not promote connector-specific claims.

## Phase 0 - Attacker Recon

Language: Solidity 0.8.x, upgradeable EVM contracts.

Attack goals:

1. Withdraw assets without burning the correct shares.
2. Corrupt fee accounting so commissions can be stolen or permanently stranded.
3. Desynchronize vault share supply, connector assets, and cached reward-fee state.
4. Bypass blocklist/transferability controls to move or release restricted assets.
5. Abuse factory or migration logic to initialize a vault with mismatched dependencies.

Priority targets:

1. `Vault`: holds user-facing ERC4626 accounting and all connector value movement.
2. `FeeDispatcher`: stores pending fees and pulls tokens from vault buckets.
3. `VaultFactory.upgradeVault`: migrates legacy fee state into the new vault/dispatcher model.
4. `BlockList` plus `Vault.forceWithdraw`: controls compliance exits.

## Phase 1 - Function-State and Coupling Map

### Core Coupled State Pairs

| Pair | Invariant | Main mutation paths | Raw verdict |
| --- | --- | --- | --- |
| Vault ERC20 balances/totalSupply vs connector-held assets | Shares must represent current claim on connector assets plus vault-held idle fees | `deposit`, `mint`, `withdraw`, `redeem`, `collectRewardFees`, `claimAdditionalRewards`, connector `totalAssets` | No verified gap in matched core |
| `_lastTotalAssets` vs `totalAssets()` | Reward fee accrual uses last snapshot, updated after value-moving operations that should close a reward interval | `_deposit`, `_withdraw`, `collectRewardFees`, `setRewardFee`; read by `_accruedRewardFeeShares` | No verified gap; deliberate lazy reward interval around additional rewards |
| `_collectableRewardFeesShares` vs vault-owned fee shares | Stored fee-share counter should track shares minted to `address(this)` for accrued reward fees | `_accrueRewardFee`, `collectRewardFees` | No verified gap |
| FeeDispatcher pending fee buckets vs vault-held idle fee assets/allowance | Pending fees are keyed by vault/caller and dispatch can only pull from that same caller | Vault `_deposit`, `collectRewardFees`, `dispatchFees`; FeeDispatcher increment/set/dispatch | No verified gap |
| `_connectorRegistry` vs `_connectorName` | Registry must contain the selected connector name for state-changing connector calls | init, factory upgrade, `_getConnector`/`getOrRevert` callers | Admin-only/configuration lead, not bounty-eligible here |
| `_blockList` internal list vs underlying sanctions list | Internal blocklist enables forced user exit only when not OFAC-sanctioned | `BlockList.addToBlockList`, `removeFromBlockList`, `setUnderlyingSanctionsList`, `Vault.forceWithdraw` | No verified bypass |
| Factory arrays vs deployed proxies | Factory lists should index deployed vaults/blocklists | create/remove/upgrade functions | Admin-only/off-chain indexing, no material unprivileged impact |

### High-Risk Function-State Matrix

| Function | Reads | Writes | Guards | External/delegate calls | Raw verdict |
| --- | --- | --- | --- | --- | --- |
| `Vault.deposit` lines 448-469 | pause, blocklist, max deposit, reward snapshot | reward fee shares via `_accrueRewardFee`, shares, `_lastTotalAssets`, pending deposit fee | `nonReentrant`, transferability, blocklist, deposit pause | ERC20 transfer, connector deposit delegatecall, FeeDispatcher increment | Sound after trace |
| `Vault.mint` lines 473-496 | reward snapshot, max mint, partial shares | same as deposit | same as deposit | same as deposit | Sound after trace |
| `Vault.withdraw` lines 500-520 | max withdraw, reward snapshot, total supply | fee shares, burns shares, `_lastTotalAssets` | `nonReentrant`, transferability, blocklist | connector withdraw delegatecall, ERC20 transfer | Rounding candidate killed |
| `Vault.redeem` lines 524-551 | max redeem, reward snapshot | fee shares, burns shares, `_lastTotalAssets` | `nonReentrant`, transferability, blocklist | connector withdraw delegatecall, ERC20 transfer | Sound after trace |
| `Vault.collectRewardFees` lines 861-882 | accrued reward fee shares, stored fee shares, total assets | pending reward fee, burns stored fee shares, clears counter, `_lastTotalAssets` | `nonReentrant`, `FEE_COLLECTOR_ROLE` | connector withdraw delegatecall, FeeDispatcher increment | Sound after feedback loop |
| `Vault.claimAdditionalRewards` lines 893-934 | total assets before/after, reward strategy | none directly except connector side effects | `nonReentrant`, `CLAIM_MANAGER_ROLE` | connector claim/reinvest delegatecall | No eligible gap; reward fee is lazily captured later |
| `Vault.forceWithdraw` lines 956-979 | blocklist, reward snapshot, max redeem, user balance | burns user shares, `_lastTotalAssets` | `nonReentrant`; public but internally constrained | connector withdraw delegatecall, ERC20 transfer | Sound after trace |
| `FeeDispatcher.dispatchFees` lines 96-135 | caller pending fees and recipients | caller pending fees | `nonReentrant` | `asset.safeTransferFrom(msg.sender, recipient, amount)` | Sound; caller-scoped buckets |
| `FeeDispatcher.incrementPending*` lines 182-192 | caller bucket | caller pending fee bucket | none | none | Sound; caller can only affect own bucket |
| `FeeDispatcher.setFeeRecipients` lines 199-232 | caller bucket | caller recipients | none | none | Sound; caller-scoped and validates full split |
| `VaultFactory.createVault` lines 138-188 | factory beacon/registry/dispatcher | deployed vault list | `DEPLOYER_ROLE` | CREATE2 beacon proxy init | Privileged path |
| `VaultFactory.upgradeVault` lines 217-247 | legacy fee storage through vault delegatecall | vault upgrade state, deployed vault list | `DEPLOYER_ROLE` | vault delegatecall and upgrade | Privileged migration path |
| `BlockList.add/remove` lines 108-128 | internal list | internal list | `OPERATOR_ROLE` | none | Privileged path |
| `BlockList.isBlocked` lines 138-143 | sanctions list, internal list | none | none | sanctions list view | Sound |

## Phase 2 - Feynman Raw Hypotheses

### NM-H01: `withdraw` rounds required shares down to zero after a nonzero preview

Question that exposed it: Why does `withdraw` check `_shares == 0` before `_roundDownPartialShares`, rather than after rounding?

Code:

- `previewWithdraw` rounds down partial shares at lines 428-435.
- `withdraw` computes required shares at line 515, checks zero at line 516, then rounds down at line 517.
- `_roundDownPartialShares` floors by `10 ** _offset` at lines 798-803.

Concrete arithmetic trace:

- `offset = 6`
- `totalSupply = 100_000_000`
- `totalAssets = 150`
- `assets = 1`
- raw shares = `ceil(1 * (100_000_000 + 1_000_000) / (150 + 1)) = 668875`
- rounded shares = `0`

Raw severity: would be high/critical if eligible and live because assets could be withdrawn without burning shares.

Raw status: killed in verification. This is a rounding issue, explicitly out of bounty scope, and the partial-share interaction is documented in the Sigma Prime DeFi Integrations assessment as the motivation for `_roundDownPartialShares`.

### NM-H02: `collectRewardFees` collects newly accrued reward fees without minting new fee shares

Question that exposed it: If `_collectableRewardFeesShares + _rewardFeeShares` is converted to assets, why are only stored `_collectableRewardFeesShares` burned?

Code:

- `_accruedRewardFeeShares` computes new shares without minting at lines 768-783.
- `collectRewardFees` includes stored plus new fee shares in `_collectable` at lines 864-871.
- It withdraws that asset amount, increments pending reward fee, burns only stored shares, clears stored shares, and refreshes `_lastTotalAssets` at lines 874-882.

Raw status: false positive. Minting and immediately burning `_rewardFeeShares` inside the same function would have no net share-supply effect; using those virtual shares only for the conversion is equivalent for this collection path. Stored fee shares are the only already-minted shares that require a real burn.

### NM-H03: FeeDispatcher public increment/setter functions look unguarded

Question that exposed it: Why can any caller increment pending fees or set fee recipients?

Code:

- Fee buckets are stored as `_dispatches[msg.sender]` at lines 16-20.
- Getter, increment, setter, and dispatcher logic all index `msg.sender` at lines 99-104, 142-156, 182-192, and 199-232.
- `dispatchFees` transfers from `msg.sender`, not from an arbitrary vault, at lines 115 and 127.

Raw status: false positive. A caller can only mutate and dispatch its own fee bucket. This cannot steal another vault's funds unless that caller already has asset balance/allowance for its own bucket.

### NM-H04: `claimAdditionalRewards(Reinvest)` increases assets without updating `_lastTotalAssets`

Question that exposed it: If reinvest raises connector assets, why is `_lastTotalAssets` not updated in the same call?

Code:

- `claimAdditionalRewards` checks total assets before/after and emits the gain at lines 899-931.
- `_lastTotalAssets` is not updated there.
- `_accruedRewardFeeShares` later computes reward as `totalAssets() - _lastTotalAssets` at lines 768-783.

Raw status: false positive. The stated behavior is that additional rewards are considered yield where the reward fee can apply. Leaving `_lastTotalAssets` stale after a successful reinvest causes the next accrual path to charge reward fee on that newly added yield. No unprivileged loss or stale-state exploit was found.

### NM-H05: Factory upgrade can change connector registry without revalidating connector name

Question that exposed it: Why does `_setConnectorRegistry` update the registry without also rechecking the existing `_connectorName` against the new registry?

Code:

- Factory upgrade passes `connectorRegistry_` at `VaultFactory.upgradeVault` lines 233-243.
- Vault `_setConnectorRegistry` checks only code length at lines 1045-1050.
- `_setConnectorName` validates existence when called, lines 1053-1059, but upgrade does not call it.

Raw status: not eligible. The path is restricted to `DEPLOYER_ROLE` and depends on privileged misconfiguration/migration. The bounty excludes issues requiring privileged roles.

### NM-H06: Force withdrawal is public

Question that exposed it: If anyone can call `forceWithdraw`, can they force an arbitrary user's exit?

Code:

- `forceWithdraw` is public at line 956.
- It requires a nonzero user to be internally blocked and not sanctioned by the underlying list at lines 958-966.
- It then requires full liquidity for the user's entire balance at lines 970-972 and withdraws to `blockedUser` at lines 975-977.

Raw status: false positive. The caller does not receive funds, and the target must already be internally blocked and not OFAC-sanctioned. This is the intended compliance exit path, not an unprivileged theft path.

## Phase 3 - State Cross-Check

Mutation matrix deltas:

| State | Mutating functions | Coupled update checked | Result |
| --- | --- | --- | --- |
| `_lastTotalAssets` | `_deposit`, `_withdraw`, `collectRewardFees`, `setRewardFee` | Reward interval closes after deposit/withdraw/fee collection; additional rewards intentionally left for later fee accrual | No verified gap |
| `_collectableRewardFeesShares` | `_accrueRewardFee`, `collectRewardFees` | Minted shares to vault are tracked and burned when collected | No verified gap |
| Pending deposit fee | Vault `_deposit`, FeeDispatcher `dispatchFees`, public caller increment | Idle deposit fee assets remain in vault; dispatcher pulls from caller bucket | No verified gap |
| Pending reward fee | Vault `collectRewardFees`, FeeDispatcher `dispatchFees`, public caller increment | Reward assets are withdrawn from connector before pending bucket increments | No verified gap |
| ERC20 balances/totalSupply | `_mint`, `_burn`, transfers | Partial-share guard enforced on mint/redeem/transfer; withdraw rounding candidate killed by scope | No eligible gap |
| Blocklist status | BlockList add/remove/set underlying | Vault checks blocklist on user flows and force-withdraw checks internal-only status | No verified gap |

Parallel path comparison:

| Outcome | Paths compared | Difference | Verdict |
| --- | --- | --- | --- |
| User enters vault | `deposit` vs `mint` | Both accrue reward fee before preview and use `_deposit` | Synced |
| User exits vault | `withdraw` vs `redeem` vs `forceWithdraw` | All accrue reward fee then use `_withdraw`; `forceWithdraw` exits to blocked user | Synced except killed rounding candidate |
| Fee movement | deposit fee vs reward fee | Deposit fee remains idle and pending; reward fee withdraws from connector then pending | Designed asymmetry |
| Share movement | transfer vs transferFrom vs burn on redeem/withdraw | Transfers enforce partial shares/blocklist; burns occur through exit paths with reward accrual | No eligible gap |
| Compliance state | internal blocklist vs underlying sanctions | Forced exit allowed only for internal-only block | Synced |

Masking/defensive code reviewed:

- `_roundDownPartialShares`: real arithmetic edge, killed by rounding exclusion and known-issue perimeter.
- `_accruedRewardFeeShares` uses `trySub` to ignore negative rewards at lines 771-783. This is not a desync bug by itself; reward fees only accrue on positive yield, and losses should not mint negative fees.
- FeeDispatcher per-recipient rounding leaves residual pending amounts at lines 112-134. This is rounding dust and out of scope.

## Phase 4 - Nemesis Feedback Loop

Loop 1:

- State Mapper fed `_collectableRewardFeesShares` into Feynman. Result: no bug, because new virtual fee shares in `collectRewardFees` do not need mint/burn when collected in the same call.
- Feynman fed public FeeDispatcher setters into State Mapper. Result: no bug, because all state keys and transfers are scoped to `msg.sender`.
- State Mapper fed `_lastTotalAssets` after `claimAdditionalRewards` into Feynman. Result: no bug, because additional rewards are intended yield and later fee accrual is consistent with comments and code.

Loop 2:

- No new coupled pairs or reachable unprivileged breaking operations emerged.
- Converged.

## Phase 5 - Multi-Transaction Journeys

Journeys traced:

1. Deposit -> yield accrues -> deposit/mint/redeem/withdraw -> reward fee accrues before user operation. No verified gap.
2. Deposit -> yield accrues -> collectRewardFees -> dispatchFees. Stored fee shares are burned, pending reward fee is backed by asset balance, and dispatch pulls from the same vault bucket. No verified gap.
3. Deposit -> additional rewards reinvest -> later user operation. `_lastTotalAssets` remains stale until next accrual, so reward fee applies to the reinvested yield. No exploit found.
4. Deposit fee accumulates -> fee recipients changed -> dispatch. Recipient change is `FEE_MANAGER_ROLE`/caller-bucket behavior and privileged/configuration, not an unprivileged theft path.
5. User internally blocked -> forceWithdraw. Funds go to the blocked user and only when full liquidity exists. No theft path.
6. Multiple tiny withdrawals under nonzero offset. Demonstrates NM-H01 arithmetic but killed by known/rounding/out-of-scope filters.

## Raw Summary

- Functions analyzed: 30+ public/external core entry points plus key internal accounting helpers.
- Coupled state pairs mapped: 7.
- Nemesis loop iterations: 2.
- Raw hypotheses: 6.
- Verified bounty-eligible true positives: 0.
- False positives / killed leads: 6.
