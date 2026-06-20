# Aave V3 Connector Review

## Immutable Dependencies

- `aave`: Aave V3 Pool contract
- `poolAddressesProvider`: Aave addresses provider
- `swapTarget`: DEX aggregator for reinvest
- `rewardsController`: Aave rewards controller

## Critical Analysis

| Area          | Verdict                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------- |
| Asset binding | Resolves aToken via PoolDataProvider. Correct.                                                  |
| Supply        | `forceApprove(aave, amount)` → `aave.supply(asset, amount, vault, 0)`. Correct.                 |
| Withdraw      | `aave.withdraw(asset, amount, vault)`. Returns actual amount — ignored (balance-delta). Safe.   |
| totalAssets   | Reads aToken.balanceOf(vault). Correct — aToken = 1:1 with underlying over time.                |
| maxDeposit    | Checks active/frozen/paused. Computes supply cap with decimal scaling. Correct.                 |
| maxWithdraw   | Reads aToken contract's underlying balance. Conservative.                                       |
| Claim         | `claimAllRewards` → multisend. Balance-delta for received amount. Safe.                         |
| Reinvest      | Claim → approve(swapTarget, max) → swap → supply. **Persistent max approval** for reward token. |

## Key Risk: swapTarget unlimited approval

Reinvest leaves `forceApprove(swapTarget, type(uint256).max)`. If swapTarget is compromised, reward tokens can be drained.
