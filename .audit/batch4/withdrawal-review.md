# Batch 4 — Withdrawal Review

## Balance-Delta Pattern

The Vault's `_withdraw` function:

```solidity
_burn(owner, shares);                          // 1. Burn shares (irreversible)
uint256 balanceBefore = asset.balanceOf(vault); // 2. Snapshot vault balance
connector.delegatecall(withdraw(asset, assets)); // 3. Request from connector
safeTransfer(                                   // 4. Transfer actual increase
    receiver,
    asset.balanceOf(vault) - balanceBefore      //    NOT the requested `assets`
);
```

## Key Finding: B4-002 — Short Withdrawal

**The shares are burned for the full requested amount before the connector call.** If the connector returns less than requested (without reverting), the withdrawing user loses value and remaining holders gain a windfall.

### Exact Numerical Proof

See [`test/audit/batch4/VaultWithdrawalDelta.t.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/test/audit/batch4/VaultWithdrawalDelta.t.sol) for complete tests.

### Connector-by-Connector Analysis

| Connector   | Short return possible? | Evidence                                                                                               |
| ----------- | ---------------------- | ------------------------------------------------------------------------------------------------------ |
| Aave V3     | **No**                 | `withdraw()` reverts on insufficient liquidity. Returns actual amount.                                 |
| Compound V3 | **No**                 | `withdraw()` reverts if market has insufficient base asset.                                            |
| MetaMorpho  | **No**                 | ERC4626 `withdraw()` reverts if assets cannot be delivered. `maxWithdraw()` reflects actual liquidity. |
| sDAI        | **No**                 | ERC4626 `withdraw()` guarantees exact output.                                                          |
| sUSDS       | **No**                 | Same as sDAI.                                                                                          |
| Angle       | **No**                 | Same pattern — revert on failure.                                                                      |

### Other Edge Cases

| Scenario          | Vault Behavior                           | Safe?                                          |
| ----------------- | ---------------------------------------- | ---------------------------------------------- |
| Returns 100/100   | Exact match                              | Yes                                            |
| Returns 99/100    | Balance-delta transfers 99               | Receiver loses 1%, but connector can't do this |
| Returns 50/100    | Balance-delta transfers 50               | Unsafe (B4-002) - requires CONNECTOR_MANAGER
| Returns 0/100     | Balance-delta transfers 0                | Unsafe — shares burned for nothing             |
| Returns 101/100   | Extra stays in vault or goes to receiver | Extra is a windfall (unlikely)                 |
| Connector reverts | Entire tx reverts, shares restored       | Yes (atomic)                                   |
