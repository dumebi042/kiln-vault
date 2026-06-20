# Batch 4 — Asset Flow Map

## Deposit Flow

```
User
  │
  ▼
Vault.deposit(assets, receiver)  or  Vault.mint(shares, receiver)
  │
  ├── _accrueRewardFee()              ← view/totalAssets() BEFORE transfer
  ├── _previewDeposit / _previewMint  ← compute shares/fees
  │
  └── _deposit(caller, receiver, assets, shares, depositFeeAmount)
        │
        ├── balanceBefore = asset.balanceOf(vault)
        ├── safeTransferFrom(caller, vault, assets)
        ├── _mint(receiver, shares)
        ├── check: totalSupply >= _minTotalSupply
        │
        ├── connector.functionDelegateCall(
        │       abi.encodeCall(IConnector.deposit,
        │           (asset, balanceOf(vault) - balanceBefore - depositFeeAmount)
        │       )
        │   )
        │   │
        │   └── [delegatecall → connector code runs in vault's storage context]
        │       address(this) = vault proxy
        │       msg.sender    = original caller (user)
        │       │
        │       ├── AaveV3:      asset.forceApprove(aave, amount) → aave.supply(...)
        │       ├── CompoundV3:  asset.forceApprove(comet, amount) → comet.supply(...)
        │       ├── MetaMorpho:  asset.forceApprove(metamorpho, amount) → metamorpho.deposit(...)
        │       ├── sDAI:        asset.forceApprove(sDAI, amount) → sDAI.deposit(...)
        │       ├── sUSDS:       asset.forceApprove(sUSDS, amount) → sUSDS.deposit(...)
        │       └── Angle:       asset.forceApprove(stakingVault, amount) → stakingVault.deposit(...)
        │
        ├── _lastTotalAssets = totalAssets()
        └── feeDispatcher.incrementPendingDepositFee(depositFeeAmount)
```

### Critical observation: delegatecall semantics

All connector `deposit()` and `withdraw()` functions execute via `functionDelegateCall`. This means:

- `address(this)` inside the connector = **Vault proxy address**
- `msg.sender` inside the connector = **Original caller** (the user who called deposit/withdraw)
- Connector storage is NOT used — vault storage is used instead
- All state writes go to the vault's storage at the connector's storage layout positions

For `forceApprove(protocol, amount)`:

- The vault proxy becomes the `msg.sender` for the token's `approve()` call
- The protocol receives approval to spend the VAULT's tokens, not the connector's

For `protocol.deposit(asset, amount, address(this))`:

- Protocol credits `address(this)` = **Vault proxy**
- Receipt tokens (aTokens, Comet balance, MetaMorpho shares) are held by the **Vault proxy**
- The connector address has NO position in the protocol

### Key consequence for connector registry transitions

Since the position is tied to the **Vault address** (not the connector address), updating the connector registry to a new connector implementation does NOT strand existing positions. The new connector can still withdraw because:

1. The protocol balance is at the vault address (unchanged)
2. The new connector reads `balanceOf(msg.sender)` where `msg.sender` = vault
3. Receipt tokens are held by the vault (accessible by any connector via delegatecall)

---

## Withdrawal Flow

```
User
  │
  ▼
Vault.withdraw(assets, receiver, owner)  or  Vault.redeem(shares, receiver, owner)
  │
  ├── _accrueRewardFee()
  ├── compute shares/assets
  │
  └── _withdraw(caller, receiver, owner, assets, shares)
        │
        ├── if caller != owner: _spendAllowance(owner, caller, shares)
        ├── _burn(owner, shares)
        │
        ├── balanceBefore = asset.balanceOf(vault)
        │
        ├── connector.functionDelegateCall(
        │       abi.encodeCall(IConnector.withdraw, (asset, assets))
        │   )
        │   │
        │   └── [delegatecall — connector code runs in vault's storage context]
        │       address(this) = vault proxy
        │       │
        │       ├── AaveV3:      aave.withdraw(asset, amount, address(this)) → returns assets to vault
        │       ├── CompoundV3:  comet.withdraw(asset, amount) → sends assets to vault
        │       ├── MetaMorpho:  metamorpho.withdraw(amount, address(this), address(this))
        │       ├── sDAI:        sDAI.withdraw(amount, address(this), address(this))
        │       ├── sUSDS:       sUSDS.withdraw(amount, address(this), address(this))
        │       └── Angle:       stakingVault.withdraw(amount, address(this), address(this))
        │
        ├── actualReceived = asset.balanceOf(vault) - balanceBefore
        ├── safeTransfer(vault, receiver, actualReceived)
        ├── _lastTotalAssets = totalAssets()
        └── emit Withdraw(caller, receiver, owner, assets, shares)
```

### Critical: balance-delta transfer

The Vault transfers `asset.balanceOf(vault) - balanceBefore` rather than the requested `assets`. This means:

- If the connector returns **less** than requested, that's what the receiver gets
- If the connector returns **more**, that extra stays in the vault (or goes to receiver)
- The `Withdraw` event still records the REQUESTED `assets`, not actual received

**This is safe** because the receiver always gets what was actually recovered. However, the event is technically inaccurate when actual ≠ requested.

---

## Connector-by-Connector Asset Location

| Connector  | Deposit: assets go to | Receipt token/proof | Held by     | totalAssets reads                  |
| ---------- | --------------------- | ------------------- | ----------- | ---------------------------------- |
| AaveV3     | Aave pool             | aToken              | Vault proxy | aToken.balanceOf(vault)            |
| CompoundV3 | Comet market          | basePrincipal       | Vault proxy | comet.balanceOf(vault)             |
| MetaMorpho | MetaMorpho vault      | Metamorpho shares   | Vault proxy | metamorpho.previewRedeem(shares)   |
| sDAI       | sDAI vault            | sDAI shares         | Vault proxy | sDAI.previewRedeem(shares)         |
| sUSDS      | sUSDS vault           | sUSDS shares        | Vault proxy | sUSDS.previewRedeem(shares)        |
| Angle      | stakingVault          | stakingVault shares | Vault proxy | stakingVault.previewRedeem(shares) |

---

## Approval Lifecycle

| Connector             | Approve calls                                                                       | Amount                    | Resets?                   |
| --------------------- | ----------------------------------------------------------------------------------- | ------------------------- | ------------------------- |
| AaveV3 (deposit)      | `asset.forceApprove(aave, amount)`                                                  | Deposit amount            | Yes (forceApprove resets) |
| AaveV3 (reinvest)     | `rewardsAsset.forceApprove(swapTarget, max)` + `asset.forceApprove(aave, received)` | max + received            | Yes                       |
| CompoundV3            | `asset.forceApprove(comet, amount)`                                                 | Deposit amount            | Yes                       |
| CompoundV3 (reinvest) | `comp.forceApprove(swapTarget, max)` + `asset.forceApprove(comet, received)`        | max + received            | Yes                       |
| MetaMorpho            | `asset.forceApprove(metamorpho, amount)`                                            | Deposit amount            | Yes                       |
| sDAI                  | `asset.forceApprove(sDAI, amount)`                                                  | Deposit amount            | Yes                       |
| sUSDS                 | `asset.forceApprove(sUSDS, amount)`                                                 | Deposit amount            | Yes                       |
| Angle                 | `asset.forceApprove(stakingVault, amount)`                                          | Deposit amount            | Yes                       |
| Vault init            | `asset.forceApprove(feeDispatcher, type(uint256).max)`                              | Unlimited (FeeDispatcher) | Not reset                 |

The `forceApprove` pattern handles USDT-style tokens (which require zero-first approval) by calling `approve(spender, 0)` then `approve(spender, amount)`.

After each `deposit()`, the approval to the protocol is fully consumed (protocol transfers exact amount). No residual approval remains for standard ERC20 tokens.

**Exception**: `reinvest()` leaves `rewardsAsset.forceApprove(swapTarget, type(uint256).max)` — the swap target retains unlimited approval of the reward token. If the swap target is malicious or compromised, it could drain reward tokens.

---

## Risk Summary

| Risk                                          | Likelihood                            | Impact                                             |
| --------------------------------------------- | ------------------------------------- | -------------------------------------------------- |
| Connector withdraws less than requested       | Low (external protocol behavior)      | Receiver gets less, event records requested amount |
| Connector returns zero on withdraw            | Low (protocol pause/freeze)           | Receiver gets nothing, shares burned               |
| Swap target abuses max approval               | Low (trusted setup)                   | Reward tokens drained                              |
| Registry update with old positions            | Low (positions tied to vault address) | No position loss                                   |
| Connector delegatecall modifies vault storage | Admin power (connector manager)       | Vault storage corruption                           |
