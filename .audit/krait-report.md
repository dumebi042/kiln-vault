# Krait Security Audit Report

Target: Kiln OmniVault
Date: 2026-06-19

## Scope

Fresh audit using `kiln-v2-vault.md` as the scope boundary. The repo source was matched to scanner-verified deployed sources before auditing; flattened scanner exports are archived under `.audit/backups/src-flattened-20260619-164835`.

In scope: Vault core, factories, beacons/proxies, `FeeDispatcher`, `ConnectorRegistry`, blocklist/access control, and scoped connector contracts including Aave V3 and Compound V3.

## Result

| Severity | Count |
| --- | ---: |
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 0 |

No bounty-ready exploit was found in current production scope.

## Production Review Of Compound Pre-Claim Candidate

Status: killed for current production deployment.

The candidate was: anyone can call Compound `CometRewards.claim(comet, vault, true)` before Kiln's claim manager, causing `CompoundV3Connector.claim()` to observe `_received == 0` and revert before Claim-strategy multisend distribution.

The code-level trace is valid for a vault configured with `AdditionalRewardsStrategy.Claim`, and the PoC remains at `test/CompoundPreclaimPoC.t.sol:93`. However, it is not present in current production scope because every scoped active Compound vault queried is configured as `AdditionalRewardsStrategy.Reinvest` (`2`), not `Claim` (`1`):

- Polygon `0xE194d6De7E9499116A9E7E923696A92d6944D2B2`: `2`.
- Base `0xd92249507B3ECe9600a3b1DaDC1e4DAc3B80128F`: `2`.
- Arbitrum `0xAd231a5aAc991089F1A4FEbFD95eE571A9826054`: `2`.
- Arbitrum `0x19A0F016Ac3989e754ab8216810beD8503bDA37e`: `2`.
- Arbitrum `0xAB3aC228Cac84a8a1C855C3E08F869B65836c962`: `2`.
- Arbitrum `0x1C107c4233Ab3056254e717c7a67F9917079b615`: `2`.
- Arbitrum `0x1eB3061F96Ff927EA7CAeF216bB5872622052C1C`: `2`.
- Ethereum `0x96D595D35a0203d6e218852190b3E981ADEeab0B`: `2`.
- Ethereum `0x91422083A9947De4f0423c6829888BE7B83f06F5`: `2`.
- Ethereum `0x754A34e2f4582925F5E384c371f78db01A869572`: `2`.
- Ethereum `0xB9E62Cb9b4cE8ec13c886FaE67369Da417EE2714`: `2`.
- Ethereum `0x804EE40b227B9003BB7bf2880cF502466544F208`: `2`.
- Ethereum `0x4bf3499072103e9A4afC2Ce4ea09afccF163CD87`: `2`.

For Reinvest strategy, pre-claimed COMP sitting in the vault can still be swapped by the claim manager's reinvest payload, so the Claim-strategy multisend-brick impact does not apply.

Additional production notes:

- Several Ethereum Compound vaults have owed COMP.
- Simulated unprivileged `CometRewards.claim()` calls succeeded on small-owed Ethereum vaults.
- Some larger owed simulations reverted because the Compound rewards contract currently had insufficient COMP balance, which further weakens current exploitability for those specific vaults.

## Killed Candidates

### Compound pre-claim Claim-strategy distribution grief

Killed because no current scoped Compound production vault was configured with Claim strategy.

### Aave reward-asset parameter mismatch

`AaveV3Connector.claim()` passes `rewardsAsset` into Aave's `claimAllRewards(assets, to)`, where Aave expects incentivized assets. This is a real future-configuration risk, but sampled live non-zero scoped Ethereum Aave rewards were aToken rewards, so the deployed path works for the observed current value at risk. Not bounty-ready.

### Withdraw partial-share rounding

Killed as duplicate/out of scope: the Sigma Prime DeFi Integrations report covers the partial-share rounding behavior, and the bounty excludes rounding errors.

## Verification

- `forge test --match-path test/CompoundPreclaimPoC.t.sol -vv`: passed for conditional Claim-strategy trace.
- `forge test --match-path test/invariant/VaultInvariant.t.sol -q`: passed.
- `additionalRewardsStrategy()(uint8)` queried on all scoped active Compound vaults listed above: all returned `2`.
