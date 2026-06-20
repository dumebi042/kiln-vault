# Compound V3 Connector Review

## Immutable Dependencies

- `compoundMarketRegistry`: Maps asset → Comet market
- `cometRewards`: Compound rewards contract
- `swapTarget`: DEX aggregator
- `comp`: COMP token address

## Critical Analysis

| Area          | Verdict                                                                             |
| ------------- | ----------------------------------------------------------------------------------- |
| Asset binding | Resolves Comet via MarketRegistry. Correct for registered assets.                   |
| Supply        | `forceApprove(comet, amount)` → `comet.supply(asset, amount)`. Correct.             |
| Withdraw      | `comet.withdraw(asset, amount)`. Returns asset to vault. Safe.                      |
| totalAssets   | Reads `comet.balanceOf(vault)`. Represents present-value base claim. Correct.       |
| maxDeposit    | Checks `isSupplyPaused()`. Returns max if not paused. Correct.                      |
| maxWithdraw   | Checks `isWithdrawPaused()`. Reads asset balance of Comet contract. Conservative.   |
| Claim         | Validates `rewardsAsset == comp`. Correct.                                          |
| Reinvest      | Claim COMP → approve(swapTarget, max) → swap → supply. **Persistent max approval**. |

## Key Risks

1. **MarketRegistry staleness**: If registry returns wrong market, funds go to wrong protocol
2. **swapTarget unlimited approval** (same as Aave)
