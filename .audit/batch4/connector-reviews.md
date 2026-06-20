# Batch 4 — Connector Reviews

## 1. Aave V3 Connector

| Aspect          | Assessment                                                                                                      |
| --------------- | --------------------------------------------------------------------------------------------------------------- |
| `totalAssets()` | Reads aToken balance of `msg.sender` (vault) via PoolDataProvider. Correct.                                     |
| `deposit()`     | `forceApprove(aave, amount)` then `aave.supply(asset, amount, vault, 0)`. Correct.                              |
| `withdraw()`    | `aave.withdraw(asset, amount, vault)`. Aave returns actual withdrawn. Ignored — Vault uses balance-delta. Safe. |
| `maxDeposit()`  | Checks reserve is active, not frozen, not paused. Computes supply cap correctly with decimal scaling. Correct.  |
| `maxWithdraw()` | Checks reserve active and not paused. Returns aToken contract's balance of asset. Correct.                      |
| Reward claim    | `claimAllRewards` then multisend to recipients. Uses balance-delta for received amount. Correct.                |
| Reinvest        | Claims, swaps via swapTarget, then supplies swapped amount. Safe.                                               |

### Risk: `swapTarget` approval

The `reinvest()` function leaves `rewardsAsset.forceApprove(address(swapTarget), type(uint256).max)`. If `swapTarget` is malicious or compromised, reward tokens can be drained.

**Classification**: EXPECTED ADMIN POWER (swapTarget is an immutable set during deployment).

## 2. Compound V3 Connector

| Aspect          | Assessment                                                                                             |
| --------------- | ------------------------------------------------------------------------------------------------------ |
| `totalAssets()` | Reads `comet.balanceOf(msg.sender)` via MarketRegistry lookup. Correct.                                |
| `deposit()`     | `forceApprove(comet, amount)` then `comet.supply(asset, amount)`. Correct.                             |
| `withdraw()`    | `comet.withdraw(asset, amount)`. Comet sends assets to `msg.sender` (vault during delegatecall). Safe. |
| `maxDeposit()`  | Checks `isSupplyPaused()`. Returns max if not paused. Correct.                                         |
| `maxWithdraw()` | Checks `isWithdrawPaused()`. Returns asset balance of Comet contract. Correct.                         |

### Risk: MarketRegistry dependency

The connector resolves the Comet market address via `compoundMarketRegistry.getMarket(asset)`. If the registry returns a stale or incorrect market, funds could be sent to the wrong protocol. The registry is initialized during construction and is immutable.

**Classification**: EXPECTED ADMIN POWER (market registry is part of trusted setup).

## 3. MetaMorpho Connector

| Aspect          | Assessment                                                                                                                                          |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `totalAssets()` | `metamorpho.previewRedeem(metamorpho.balanceOf(msg.sender))`. Double conversion: balanceOf gives shares, previewRedeem converts to assets. Correct. |
| `deposit()`     | `forceApprove(metamorpho, amount)` then `metamorpho.deposit(amount, vault)`. MetaMorpho credits vault with shares. Correct.                         |
| `withdraw()`    | `metamorpho.withdraw(amount, vault, vault)`. Shares are burned, assets returned to vault. Correct.                                                  |
| `maxDeposit()`  | Delegates to `metamorpho.maxDeposit(msg.sender)`. Correct.                                                                                          |
| `maxWithdraw()` | Delegates to `metamorpho.maxWithdraw(msg.sender)`. Correct.                                                                                         |

### Risk: Asynchronous liquidity

MetaMorpho vaults may have withdrawal queues or timelocks. `maxWithdraw()` may report a value that isn't immediately liquid. The balance-delta approach in Vault's `_withdraw` handles this safely: if less is recovered, that's what the user gets.

**Classification**: EXPECTED BEHAVIOR (Vault's balance-delta pattern protects against this).

## 4. sDAI / sUSDS Connectors

Identical implementation. Only the immutable ERC4626 vault address differs.

| Aspect          | Assessment                                                                |
| --------------- | ------------------------------------------------------------------------- |
| `totalAssets()` | `sDAI.previewRedeem(sDAI.balanceOf(msg.sender))`. Correct.                |
| `deposit()`     | `forceApprove(sDAI, amount)` then `sDAI.deposit(amount, vault)`. Correct. |
| `withdraw()`    | `sDAI.withdraw(amount, vault, vault)`. Correct.                           |
| `maxDeposit()`  | Delegates to `sDAI.maxDeposit(msg.sender)`. Correct.                      |
| `maxWithdraw()` | Delegates to `sDAI.maxWithdraw(msg.sender)`. Correct.                     |

### Risk: Rate changes between preview and execution

sDAI/sUSDS exchange rates change with the DSR (DAI Savings Rate). `totalAssets()` uses `previewRedeem` which reflects the current rate. Between a preview and execution, the rate may change. The Vault's balance-delta pattern in `_withdraw` handles this.

**Classification**: EXPECTED BEHAVIOR.

## 5. Angle Savings Connector

| Aspect          | Assessment                                                                                |
| --------------- | ----------------------------------------------------------------------------------------- |
| `totalAssets()` | `stakingVault.previewRedeem(stakingVault.balanceOf(msg.sender))`. Correct.                |
| `deposit()`     | `forceApprove(stakingVault, amount)` then `stakingVault.deposit(amount, vault)`. Correct. |
| `withdraw()`    | `stakingVault.withdraw(amount, vault, vault)`. Correct.                                   |
| `maxDeposit()`  | Checks `paused()`. Delegates to vault. Correct.                                           |
| `maxWithdraw()` | Checks `paused()`. Delegates to vault. Correct.                                           |
| Constructor     | Validates `totalAssets() > 0` to ensure vault is initialized. Good.                       |

## Summary

All 6 connectors follow the same safe pattern:

1. No storage state (only immutables) — safe for delegatecall
2. `forceApprove` for all approvals (handles USDT-style tokens)
3. Protocol credits go to `address(this)` (vault proxy during delegatecall)
4. Withdrawal returns to `address(this)` (vault proxy)
5. Vault's balance-delta approach protects against partial returns

No exploitable vulnerabilities found in connector code.
