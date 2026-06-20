# Batch 5 — Fee Flow Map

## Deposit Fee Lifecycle

```
User deposits A assets
  → _previewDeposit computes depositFee = A * fee / maxScale [Floor]
  → _deposit transfers A from user
  → _mint(receiver, shares) based on (A - depositFee)
  → connector receives (A - depositFee)
  → depositFee stays as idle vault balance
  → feeDispatcher.incrementPendingDepositFee(depositFee)
  → pendingDepositFee[vault] += depositFee

Later:
  Vault.dispatchFees()
    → feeDispatcher.dispatchFees(asset, decimals)
    → reads pendingDepositFee[vault]
    → for each recipient:
        transfer = pendingDepositFee * split / maxScale [Floor]
        safeTransferFrom(vault, recipient, transfer)
    → pendingDepositFee[vault] -= transferred
```

## Reward Fee Lifecycle

```
Protocol yield increases totalAssets
  → _accruedRewardFeeShares():
      reward = totalAssets - _lastTotalAssets
      feeAmount = reward * fee / maxScale [Floor]
      shares = convertToShares(feeAmount, Floor, total - feeAmount, supply)
  → _accrueRewardFee():
      _mint(vault, shares)
      _collectableRewardFeesShares += shares

Later:
  collectRewardFees():
    → reads _collectableRewardFeesShares + new accrued
    → convertToAssets(shares, Floor, total, supply)
    → connector.withdraw(asset, collectable)
    → feeDispatcher.incrementPendingRewardFee(recovered)
    → _burn(vault, _collectableRewardFeesShares)
    → _collectableRewardFeesShares = 0

Later:
  Vault.dispatchFees()
    → same as deposit fee dispatch
```
