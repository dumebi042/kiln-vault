# Reward Fee Review

## Calculation

```
reward = max(totalAssets - _lastTotalAssets, 0)
feeAmount = reward * _rewardFee / (100 * 10^decimals) [Floor]
feeShares = convertToShares(feeAmount, Floor, total - feeAmount, supply)
```

## Checkpointing

`_lastTotalAssets` is updated after each accrual. No double-charge on same yield. No fee on losses (saturating subtraction). No fee on principal-only deposits.

## Collection

`collectRewardFees()` converts fee shares to assets via connector.withdraw, then burns shares from vault. Pending reward fee tracked in FeeDispatcher.
