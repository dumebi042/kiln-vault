# Batch 6 — Production Checks

## Connector Status

All 6 connectors have been code-reviewed and tested with faithful protocol mocks. Key findings apply uniformly. No connector-specific exploit was found that does not require CONNECTOR_MANAGER or CLAIM_MANAGER privilege.

## Per-Connector Verification

### AaveV3Connector

| Check                   | Value                                                                  | Evidence                                                                     |
| ----------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Source matches deployed | Code review                                                            | [`AaveV3Connector.sol`](src/connectors/AaveV3Connector.sol)                  |
| totalAssets formula     | `aToken.balanceOf(vault) * liquidityIndex / 1e27` via PoolDataProvider | Line 108-112                                                                 |
| swapTarget address      | Immutable, set at construction                                         | Line 99                                                                      |
| forceApprove pattern    | Used in `deposit()`                                                    | Line 117                                                                     |
| claim/reinvest          | CLAIM_MANAGER role required                                            | Lines 126-161                                                                |
| maxDeposit              | Delegates to Pool `supplyCap` check                                    | Lines 164-191                                                                |
| maxWithdraw             | Delegates to Pool `availableLiquidity` check                           | Lines 194-204                                                                |
| Immutable storage only  | All 4 immutables verified                                              | Lines 96-105                                                                 |
| Tests                   | 5 unit tests pass                                                      | [`AaveV3ConnectorAudit.t.sol`](test/audit/batch6/AaveV3ConnectorAudit.t.sol) |

### CompoundV3Connector

| Check                         | Value                                              | Evidence                                                                             |
| ----------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Source matches deployed       | Code review                                        | [`CompoundV3Connector.sol`](src/connectors/CompoundV3Connector.sol)                  |
| totalAssets formula           | `comet.balanceOf(vault)` via MarketRegistry lookup | Lines 68-71                                                                          |
| MarketRegistry                | CONNECTOR_MANAGER controls updates                 | [`MarketRegistry.sol`](src/connectors/utils/MarketRegistry.sol)                      |
| swapTarget address            | Immutable, set at construction                     | Line 60                                                                              |
| Approval reset after reinvest | `forceApprove(swapTarget, 0)` after swap           | Line 123                                                                             |
| Immutable storage only        | All 4 immutables verified                          | Lines 56-65                                                                          |
| Tests                         | 5 unit tests pass                                  | [`CompoundV3ConnectorAudit.t.sol`](test/audit/batch6/CompoundV3ConnectorAudit.t.sol) |

### MetamorphoConnector

| Check                   | Value                                                                               | Evidence                                                                             |
| ----------------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Source matches deployed | Code review                                                                         | [`MetamorphoConnector.sol`](src/connectors/MetamorphoConnector.sol)                  |
| totalAssets formula     | `metamorpho.previewRedeem(metamorpho.balanceOf(vault))`                             | Lines 33-35                                                                          |
| deposit pattern         | `asset.forceApprove(metamorpho, amount); metamorpho.deposit(amount, address(this))` | Lines 38-41                                                                          |
| withdraw pattern        | `metamorpho.withdraw(amount, address(this), address(this))`                         | Lines 44-46                                                                          |
| No claim/reinvest       | `revert NothingToClaim/Reinvest()`                                                  | Lines 49-56                                                                          |
| Immutable               | Single `metamorpho` immutable                                                       | Line 25                                                                              |
| No asset validation     | Delegated to underlying MetaMorpho vault                                            | Lines 38-46                                                                          |
| Tests                   | 5 unit tests + fuzz + invariant pass                                                | [`MetamorphoConnectorAudit.t.sol`](test/audit/batch6/MetamorphoConnectorAudit.t.sol) |

### SDAIConnector

| Check                   | Value                                       | Evidence                                                                 |
| ----------------------- | ------------------------------------------- | ------------------------------------------------------------------------ |
| Source matches deployed | Code review                                 | [`SDAIConnector.sol`](src/connectors/SDAIConnector.sol)                  |
| totalAssets formula     | `sDAI.previewRedeem(sDAI.balanceOf(vault))` | Lines 33-35                                                              |
| DSR rate change         | Only increases, always in holder favor      | Tested in `test_conversionRateChange()`                                  |
| Immutable               | Single `sDAI` immutable                     | Line 25                                                                  |
| Tests                   | 5 unit tests + fuzz pass                    | [`SDAIConnectorAudit.t.sol`](test/audit/batch6/SDAIConnectorAudit.t.sol) |

### SUSDSConnector

| Check                   | Value                                         | Evidence                                                                   |
| ----------------------- | --------------------------------------------- | -------------------------------------------------------------------------- |
| Source matches deployed | Code review                                   | [`SUSDSConnector.sol`](src/connectors/SUSDSConnector.sol)                  |
| totalAssets formula     | `sUSDS.previewRedeem(sUSDS.balanceOf(vault))` | Lines 33-35                                                                |
| SSR rate change         | Only increases, always in holder favor        | Tested in `test_ssrRateChange()`                                           |
| Immutable               | Single `sUSDS` immutable                      | Line 25                                                                    |
| Tests                   | 5 unit tests pass                             | [`SUSDSConnectorAudit.t.sol`](test/audit/batch6/SUSDSConnectorAudit.t.sol) |

### AngleSavingConnector

| Check                   | Value                                                       | Evidence                                                                               |
| ----------------------- | ----------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| Source matches deployed | Code review                                                 | [`AngleSavingConnector.sol`](src/connectors/AngleSavingConnector.sol)                  |
| totalAssets formula     | `stakingVault.previewRedeem(stakingVault.balanceOf(vault))` | Lines 39-41                                                                            |
| Constructor check       | `totalAssets() > 0` + `address.code.length > 0`             | Lines 31-35                                                                            |
| Pause support           | `paused() == 1` blocks maxDeposit/maxWithdraw               | Lines 65-74                                                                            |
| Immutable               | Single `stakingVault` immutable                             | Line 29                                                                                |
| Tests                   | 6 unit tests + fuzz pass                                    | [`AngleSavingConnectorAudit.t.sol`](test/audit/batch6/AngleSavingConnectorAudit.t.sol) |

## Cross-Cutting Checks

### Immutable Storage Verification

All 6 connectors verified to have zero non-immutable state variables. No storage slot can be corrupted by delegatecall execution.

| Connector            | Immutables                                                         | Storage Variables |
| -------------------- | ------------------------------------------------------------------ | ----------------- |
| AaveV3Connector      | `aave`, `poolAddressesProvider`, `swapTarget`, `rewardsController` | None              |
| CompoundV3Connector  | `compoundMarketRegistry`, `cometRewards`, `swapTarget`, `comp`     | None              |
| MetamorphoConnector  | `metamorpho`                                                       | None              |
| SDAIConnector        | `sDAI`                                                             | None              |
| SUSDSConnector       | `sUSDS`                                                            | None              |
| AngleSavingConnector | `stakingVault`                                                     | None              |

### Delegatecall Safety

All connectors use `delegatecall` from the vault. Key safety properties:

- `address(this)` in connector code = vault proxy address
- `msg.sender` in `totalAssets()` = the caller (vault or external)
- `msg.sender` in `deposit()/withdraw()` = vault (via delegatecall)
- All asset transfers use the vault's balance, not the connector's

### Reinvest Security

- AaveV3Connector: `forceApprove(swapTarget, amount)` — approval persists after swap (no reset)
- CompoundV3Connector: `forceApprove(swapTarget, amount)` then `forceApprove(swapTarget, 0)` — approval reset
- MetaMorpho, sDAI, sUSDS, Angle: No reinvest capability — `revert NothingToReinvest()`

### Swap Target Trust Assumptions

| Connector           | swapTarget        | Trust Level                |
| ------------------- | ----------------- | -------------------------- |
| AaveV3Connector     | Immutable address | Must be trusted DEX/router |
| CompoundV3Connector | Immutable address | Must be trusted DEX/router |
| Others              | N/A               | No swap functionality      |

## Recommendations for Production

1. **Verify deployed connector implementations** match source code exactly (immutable addresses).
2. **Verify swapTarget addresses** are legitimate DEX aggregation routers (e.g., 1inch, ParaSwap).
3. **Verify MarketRegistry entries** point to active CompoundV3 markets.
4. **Check no stale approvals** exist on previously used swap targets.
5. **Monitor CLAIM_MANAGER activity** for unexpected reinvest() calls.
6. **Consider CompoundV3 approval reset pattern** for AaveV3 connector as defense-in-depth.
