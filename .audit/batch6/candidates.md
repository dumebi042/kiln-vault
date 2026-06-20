# Batch 6 — Individual Connector Review Candidates

## Summary

| ID     | Title                                                       | Connector          | Classification           |
| ------ | ----------------------------------------------------------- | ------------------ | ------------------------ |
| B6-001 | swapTarget unlimited approval persists after reinvest       | AaveV3, CompoundV3 | **EXPECTED ADMIN POWER** |
| B6-002 | Reinvest arbitrary calldata to swapTarget                   | AaveV3, CompoundV3 | **EXPECTED ADMIN POWER** |
| B6-003 | MarketRegistry staleness strands positions                  | CompoundV3         | **EXPECTED ADMIN POWER** |
| B6-004 | MetaMorpho withdrawal queue liquidity                       | MetaMorpho         | **EXPECTED BEHAVIOR**    |
| B6-005 | No asset validation in MetaMorpho connector                 | MetaMorpho         | **EXPECTED ADMIN POWER** |
| B6-006 | sDAI/sUSDS rate change between preview and execution        | sDAI, sUSDS        | **EXPECTED BEHAVIOR**    |
| B6-007 | Connector uses only immutable storage (no vault corruption) | All 6              | **EXPECTED BEHAVIOR**    |

**No VALID vulnerabilities found.** All findings are either expected behavior or require admin-level privilege.

---

## B6-001: swapTarget unlimited approval persists after reinvest

### Connectors Affected

AaveV3Connector, CompoundV3Connector

### Root Cause

Both [`AaveV3Connector.reinvest()`](src/connectors/AaveV3Connector.sol:143) and [`CompoundV3Connector.reinvest()`](src/connectors/CompoundV3Connector.sol:106) call `rewardsAsset.forceApprove(swapTarget, amount)` where `amount` is the full reward token balance. After the swap, the approval remains at `type(uint256).max` (since `forceApprove` sets the full amount). Any subsequent call to `reinvest` or a direct call to `swapTarget` could use the leftover approval.

### Attack Path

1. Admin (CLAIM_MANAGER) calls `reinvest()` — grants `type(uint256).max` approval to `swapTarget` for the reward token.
2. After swap, approval for the reward token to `swapTarget` is still `type(uint256).max`.
3. If `swapTarget` is compromised or malicious, it can drain remaining reward token balance.
4. A second `reinvest()` or `claim()` call could see reward tokens drained before swap executes.

### Mitigation (In Code)

- `swapTarget` is immutable — set at construction time, no upgrade or replacement possible.
- CLAIM_MANAGER role is restricted to trusted admin addresses.
- On CompoundV3, the approval is reset to 0 after swap via `rewardsAsset.forceApprove(swapTarget, 0)` on [`CompoundV3Connector.sol:123`](src/connectors/CompoundV3Connector.sol:123). AaveV3 does not reset.

### Test Evidence

[`test/audit/batch6/ReinvestSecurity.t.sol`](test/audit/batch6/ReinvestSecurity.t.sol) contains:

- `test_maliciousSwapTargetDrainsRewards()` — proves a compromised swap target can drain all rewards.
- `test_unlimitedApprovalToSwapTarget()` — verifies unlimited approval is granted.
- `test_swapTargetImmutability()` — confirms no setter exists.

### Classification

**EXPECTED ADMIN POWER.** swapTarget must be trusted. CLAIM_MANAGER role controls access to reinvest. No user-facing exploit path without compromised admin or swapTarget.

---

## B6-002: Reinvest arbitrary calldata to swapTarget

### Connectors Affected

AaveV3Connector, CompoundV3Connector

### Root Cause

[`AaveV3Connector.reinvest()`](src/connectors/AaveV3Connector.sol:143) and [`CompoundV3Connector.reinvest()`](src/connectors/CompoundV3Connector.sol:106) pass arbitrary `payload` bytes directly to `swapTarget`. The payload is not validated or constrained. A CLAIM_MANAGER with malicious intent could craft payloads that do not swap rewards but instead transfer them elsewhere.

### Attack Path

1. Admin (CLAIM_MANAGER) calls `reinvest(rewardsAsset, payload)` with a crafted payload.
2. `swapTarget` executes the arbitrary calldata — could transfer reward tokens to an arbitrary address, call external contracts, etc.
3. No slippage protection, deadline, or minimum-output check on the swap.

### Mitigation (In Code)

- CLAIM_MANAGER role is a trusted admin role with DEFAULT_ADMIN as its admin.
- swapTarget is immutable — cannot be redirected to a malicious contract.
- The reward asset is approved to swapTarget, limiting damage to the reward token balance.

### Test Evidence

[`ReinvestSecurity.t.sol`](test/audit/batch6/ReinvestSecurity.t.sol): `test_maliciousSwapTargetDrainsRewards()` demonstrates the pattern.

### Classification

**EXPECTED ADMIN POWER.** Same trust model as B6-001. Admin-controlled swap with unvalidated payloads is a standard DeFi pattern.

---

## B6-003: MarketRegistry staleness strands positions

### Connector Affected

CompoundV3Connector

### Root Cause

[`CompoundV3Connector`](src/connectors/CompoundV3Connector.sol) looks up the market address from [`MarketRegistry`](src/connectors/utils/MarketRegistry.sol) each time via `compoundMarketRegistry.getMarket(asset)`. The registry can be updated by CONNECTOR_MANAGER, but if a market is removed or becomes stale, existing deposits in that market become inaccessible — `deposit()`, `withdraw()`, `totalAssets()` and `maxWithdraw()` all rely on the registry lookup.

### Attack Path

1. Vault deposits into a CompoundV3 market via the connector.
2. CONNECTOR_MANAGER removes the market from the registry or updates it to a new address.
3. The old market position is stranded — `withdraw()` calls go to the new market address, not the one holding funds.
4. Manual intervention via a new connector deployment would be needed.

### Mitigation (In Code)

- CONNECTOR_MANAGER is a trusted admin role.
- Registry updates should be coordinated with position migration.
- The vault can be reconfigured to use a new connector if needed.

### Test Evidence

Structural analysis: the [`MarketRegistry`](src/connectors/utils/MarketRegistry.sol) `getMarket()` function reverts if the asset is not found, which would cause all connector functions to revert for that asset.

### Classification

**EXPECTED ADMIN POWER.** Admin-triggered, requires coordination failure. Mitigated by trusted role.

---

## B6-004: MetaMorpho withdrawal queue liquidity

### Connector Affected

MetamorphoConnector

### Root Cause

[`MetamorphoConnector.totalAssets()`](src/connectors/MetamorphoConnector.sol:33) returns `metamorpho.previewRedeem(metamorpho.balanceOf(msg.sender))` which represents the theoretical asset value of all shares. If the MetaMorpho vault's withdrawal queue is illiquid (e.g., all liquidity drained from a specific pool), `previewRedeem` may return a value that cannot be fully withdrawn.

### Analysis

This is standard ERC4626 behavior. `maxWithdraw` delegates to `metamorpho.maxWithdraw(msg.sender)` which accounts for the vault's withdrawal limits. The vault's maxWithdraw is conservative and already accounts for queue liquidity.

### Test Evidence

[`test/audit/batch6/MetamorphoConnectorAudit.t.sol`](test/audit/batch6/MetamorphoConnectorAudit.t.sol) tests deposit, full withdrawal, partial withdrawal, yield accrual, and max functions — all round-trip correctly.

### Classification

**EXPECTED BEHAVIOR.** Standard ERC4626 limitation, not a connector-specific issue.

---

## B6-005: No asset validation in MetaMorpho connector

### Connector Affected

MetamorphoConnector

### Root Cause

[`MetamorphoConnector`](src/connectors/MetamorphoConnector.sol) does not validate the `asset` parameter in `deposit()`, `withdraw()`, `totalAssets()`, etc. The connector trusts that the caller (vault) will pass the correct asset. If called with a wrong asset, `forceApprove` would approve the wrong asset to the MetaMorpho vault, and `deposit()` would fail at the vault level (wrong asset in vault).

### Attack Path

Theoretical: if a malicious connector configuration or vault upgrade caused a wrong asset to be passed, the MetaMorpho vault's own asset check would reject the deposit. No asset loss possible since the vault's `deposit()` would revert.

### Mitigation (In Code)

- MetaMorpho vault enforces its own asset check on `deposit()`.
- Connector is always called from the vault's `_getConnector()`, which is set by CONNECTOR_MANAGER.
- No user-facing path to pass arbitrary assets to the connector.

### Test Evidence

[`MetamorphoConnectorAudit.t.sol`](test/audit/batch6/MetamorphoConnectorAudit.t.sol): all tests pass with the correct asset.

### Classification

**EXPECTED ADMIN POWER.** Asset validation is delegated to the underlying vault. Admin controls connector configuration.

---

## B6-006: sDAI/sUSDS rate change between preview and execution

### Connectors Affected

SDAIConnector, SUSDSConnector

### Root Cause

[`SDAIConnector.totalAssets()`](src/connectors/SDAIConnector.sol:33) and [`SUSDSConnector.totalAssets()`](src/connectors/SUSDSConnector.sol:33) call `vault.previewRedeem(vault.balanceOf(msg.sender))`. The conversion rate (sDAI/DAI or sUSDS/USDS) can change between blocks due to the DSR/SSR accrual. This means:

1. `totalAssets()` value may differ from the actual asset returned by `withdraw()`.
2. A depositor may see a different NAV than what they can withdraw.

### Analysis

This is standard behavior for yield-bearing ERC4626 vaults. The rate only increases (DSR/SSR are accumulating), so the discrepancy is always in favor of the vault holders. The `withdraw()` function calls the underlying vault which handles the actual conversion at execution time.

### Test Evidence

[`test/audit/batch6/SDAIConnectorAudit.t.sol`](test/audit/batch6/SDAIConnectorAudit.t.sol) and [`test/audit/batch6/SUSDSConnectorAudit.t.sol`](test/audit/batch6/SUSDSConnectorAudit.t.sol) both test rate changes:

- `test_conversionRateChange()` — 8% DSR yield reflected in totalAssets
- `test_ssrRateChange()` — 12% SSR yield reflected in totalAssets

### Classification

**EXPECTED BEHAVIOR.** Standard ERC4626 yield-bearing vault behavior. Rate only increases, so no MEV or slippage risk beyond normal ERC4626.

---

## B6-007: Connector uses only immutable storage (no vault corruption)

### Connectors Affected

All 6

### Root Cause

All connectors use the `delegatecall` pattern — connector code executes in the vault proxy's context (`address(this)` = vault proxy, not connector). If any connector declared state variables (beyond immutables), those variables would map to vault storage slots and could corrupt vault state.

### Analysis

Verified: All 6 connectors use only `immutable` storage variables:

- [`AaveV3Connector`](src/connectors/AaveV3Connector.sol): `aave`, `poolAddressesProvider`, `swapTarget`, `rewardsController` — all immutable
- [`CompoundV3Connector`](src/connectors/CompoundV3Connector.sol): `compoundMarketRegistry`, `cometRewards`, `swapTarget`, `comp` — all immutable
- [`MetamorphoConnector`](src/connectors/MetamorphoConnector.sol): `metamorpho` — immutable
- [`SDAIConnector`](src/connectors/SDAIConnector.sol): `sDAI` — immutable
- [`SUSDSConnector`](src/connectors/SUSDSConnector.sol): `sUSDS` — immutable
- [`AngleSavingConnector`](src/connectors/AngleSavingConnector.sol): `stakingVault` — immutable

No `public`, `internal`, or `private` state variables exist in any connector. No constructor stores data in contract storage (immutables use code deployment, not storage slots).

### Test Evidence

[`ConnectorInvariant.t.sol`](test/audit/batch6/ConnectorInvariant.t.sol) and structural verification of each source file.

### Classification

**EXPECTED BEHAVIOR.** Secure by design.
