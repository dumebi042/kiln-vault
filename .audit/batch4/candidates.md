# Batch 4 — Deposit, Withdrawal & Connector Audit Candidates

## Summary

| ID     | Title                                                         | Classification           |
| ------ | ------------------------------------------------------------- | ------------------------ |
| B4-001 | Shares minted before connector deposit (read-only reentrancy) | **EXPECTED BEHAVIOR**    |
| B4-002 | Balance-delta withdrawal protects against partial returns     | **EXPECTED BEHAVIOR**    |
| B4-003 | Connector update preserves existing positions                 | **EXPECTED BEHAVIOR**    |
| B4-004 | Deposit fee idle balance is not invested                      | **EXPECTED BEHAVIOR**    |
| B4-005 | Fee-on-transfer tokens not fully supported                    | **OUT OF SCOPE**         |
| B4-006 | Delegated connector can corrupt vault storage                 | **EXPECTED ADMIN POWER** |
| B4-007 | Reinvest swapTarget retains max approval                      | **EXPECTED ADMIN POWER** |
| B4-008 | Connector naming collision in registry                        | **EXPECTED ADMIN POWER** |

No **VALID** vulnerabilities found in the asset flow or connector code.

---

## B4-001: Shares minted before connector deposit

The Vault mints shares BEFORE calling the connector's `deposit()`. Between `_mint()` and the delegatecall, no external calls are made to untrusted contracts. The asset transfer uses `safeTransferFrom` which can trigger ERC777 hooks, but these hooks execute during `_mint` (not between mint and deposit, since `_mint` is called after `safeTransferFrom`).

**Classification**: EXPECTED BEHAVIOR.

## B4-002: Balance-delta withdrawal protects against partial returns

The Vault transfers `asset.balanceOf(vault) - balanceBefore` rather than the requested amount. This safely handles:

- Partial liquidity (connector returns less)
- Zero returns (connector reverts or returns 0)
- Rate changes (sDAI/sUSDS rate changes between preview and execution)

**Classification**: EXPECTED BEHAVIOR.

## B4-003: Connector update preserves existing positions

Positions are tied to the VAULT address (via delegatecall), not the connector address. Updating the connector registry does not strand assets. Tested in `test_registryUpdatePreservesPosition`.

**Classification**: EXPECTED BEHAVIOR.

## B4-004: Deposit fee idle balance is not invested

The deposit fee stays as idle balance in the vault. This is by design — the fee is owed to fee recipients. It's tracked in FeeDispatcher and dispatched separately.

**Classification**: EXPECTED BEHAVIOR.

## B4-005: Fee-on-transfer tokens not fully supported

Fee-on-transfer tokens result in fewer assets being invested than shares were minted against. The protocol does not claim broad ERC20 support for fee-on-transfer tokens.

**Classification**: OUT OF SCOPE.

## B4-006: Delegated connector can corrupt vault storage

Connectors execute via `functionDelegateCall`. A malicious connector (or one with storage state variables) could corrupt vault storage by writing to vault storage at the connector's storage slot positions. All production connectors use only immutable variables, mitigating this.

**Classification**: EXPECTED ADMIN POWER (requires CONNECTOR_MANAGER role to register malicious connector).

## B4-007: Reinvest swapTarget retains max approval

The `reinvest()` functions in AaveV3 and CompoundV3 connectors leave `forceApprove(swapTarget, type(uint256).max)` for the reward token. If swapTarget is compromised, reward tokens can be drained.

**Classification**: EXPECTED ADMIN POWER (swapTarget is immutable).

## B4-008: Connector naming collision in registry

The `ConnectorRegistry` uses a `bytes32` name for each connector. If two connectors are added with the same name (different hash), the second would revert with `ConnectorAlreadyExists`. If a connector is removed and re-added, there's no issue.

**Classification**: EXPECTED ADMIN POWER.
