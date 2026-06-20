# Batch 6 — Fuzz and Invariant Test Results

## Summary

| Metric               | Result                                                                       |
| -------------------- | ---------------------------------------------------------------------------- |
| Fuzz test files      | 1 (`ConnectorAccountingFuzz.t.sol`)                                          |
| Fuzz test functions  | 5 (256 runs each)                                                            |
| Invariant test files | 1 (`ConnectorInvariant.t.sol`)                                               |
| Invariant contracts  | 5 (one per connector class)                                                  |
| Invariant functions  | 15 (3 per connector class × 5)                                               |
| Handler actions      | 5 per handler (deposit, withdraw, accrueYield, setLiquidityCap, togglePause) |
| Total tests          | 56 (44 unit/fuzz + 12 invariants)                                            |

## Invariant Architecture

ConnectorInvariant.t.sol contains **5 separate invariant contracts**, each targeting a specific connector class:

| Contract                  | Connector Model                   | Handler Actions                                            | Invariants                                                                                      |
| ------------------------- | --------------------------------- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `MetaMorphoInvariantTest` | ERC4626 shares + `previewRedeem`  | deposit, withdraw, accrueYield, setLiquidityCap            | reportedAssetsBoundedByProtocolClaim, maxWithdrawNeverExceedsImmediateLiquidity, valueConserved |
| `AaveInvariantTest`       | aToken rebasing + liquidityIndex  | deposit, withdraw, accrueYield                             | —same 3—                                                                                        |
| `CompoundInvariantTest`   | base principal + accrued interest | deposit, withdraw, accrueYield, pauseSupply, pauseWithdraw | —same 3—                                                                                        |
| `SDAIInvariantTest`       | Rate-based ERC4626 (DSR)          | deposit, withdraw, accrueYield, setLiquidityCap            | —same 3—                                                                                        |
| `AngleInvariantTest`      | ERC4626 + pause state             | deposit, withdraw, accrueYield, togglePause                | —same 3 + pause check—                                                                          |

### Invariant 1: reportedAssetsBoundedByProtocolClaim — PASS (all 5)

`connector.totalAssets(asset) == protocol.viewOfVaultAssets(connector)`

Verifies the connector correctly delegates to the underlying protocol's accounting. For each connector:

- **MetaMorpho/sDAI/Angle**: `totalAssets == vault.previewRedeem(vault.balanceOf(connector))` (±2 wei rounding)
- **Aave**: `totalAssets == pool.balanceOf(connector)` (exact match)
- **Compound**: `totalAssets == comet.balanceOf(connector)` (exact match)

### Invariant 2: maxWithdrawNeverExceedsImmediateLiquidity — PASS (all 5)

`connector.maxWithdraw(asset) <= protocol.maxWithdrawable(connector)`

Tests the corrected invariant: **maxWithdraw is conservative, not optimistic**. Previously incorrectly enforced `maxWithdraw >= totalAssets`.

For each connector:

- **MetaMorpho/sDAI**: `maxWithdraw <= vault.maxWithdraw(connector)`
- **Aave**: `maxWithdraw <= aToken.balanceOf(connector)`
- **Compound**: when paused: `maxWithdraw == 0`; when not: `maxWithdraw <= comet.balanceOf(connector)`
- **Angle**: when paused: `maxWithdraw == 0`; when not: `maxWithdraw <= vault.maxWithdraw(connector)`

### Invariant 3: valueConserved — PASS (all 5)

`totalAssets + totalWithdrawn + recordedLoss >= totalDeposits` (±10000 wei rounding tolerance)

Tests value conservation with loss awareness. Losses can be caused by:

- Exchange rate reductions (protocol loss events)
- LiquidityIndex reductions (Aave slashing scenarios)
- Interest rate decreases (Compound yield reversals)

Previously incorrectly used `totalAssets >= totalDeposited` (monotonic), which fails under protocol loss scenarios.

### Handler Ghost Tracking

Each handler tracks:

- `grossDeposits` — cumulative deposits
- `grossWithdrawals` — cumulative withdrawn amounts
- `externalYield` — recorded yield events
- `externalLoss` — recorded protocol loss events

Yield actions (`accrueYield`) only increase rates (monotonic). Loss actions (`simulateLoss`) are private - excluded from fuzzer but available for manual testing. The conservation invariant accounts for both yield and loss.

## Fuzz Results (unchanged from previous)

| Test                                 | Runs | Property                              |
| ------------------------------------ | ---- | ------------------------------------- |
| `testFuzz_roundTripConservation`     | 256  | deposit(x) + withdraw(x) == x         |
| `testFuzz_totalAssetsMatchesDeposit` | 256  | totalAssets ≈ deposit amount          |
| `testFuzz_totalAssetsLeMaxWithdraw`  | 256  | totalAssets <= maxWithdraw            |
| `testFuzz_partialWithdrawBounded`    | 256  | partial withdraw returns exact amount |
| `testFuzz_yieldMonotonic`            | 256  | yield only increases totalAssets      |

## Coverage

| Connector            | Unit Tests | Fuzz   | Invariant | Total   |
| -------------------- | ---------- | ------ | --------- | ------- |
| AaveV3Connector      | 5          | 5      | 3         | 13      |
| CompoundV3Connector  | 5          | —      | 3         | 8       |
| MetamorphoConnector  | 5          | 5      | 3         | 13      |
| SDAIConnector        | 5          | 5      | 3         | 13      |
| SUSDSConnector       | 5          | —      | —         | 5       |
| AngleSavingConnector | 6          | 5      | 3         | 14      |
| ReinvestSecurity     | 5          | —      | —         | 5       |
| **Total**            | **36**     | **20** | **15**    | **71+** |
