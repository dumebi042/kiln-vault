# Fee State Model

## Deposit Fee State

| Component         | Location                                              | Backed By          |
| ----------------- | ----------------------------------------------------- | ------------------ |
| Pending liability | FeeDispatcher.\_dispatches[vault].\_pendingDepositFee | Vault idle balance |
| Idle assets       | Vault (asset.balanceOf)                               | Not invested       |
| Vault approval    | allowance[vault][feeDispatcher] = max                 | Set during init    |

## Reward Fee State

| Component          | Location                                             | Backed By                  |
| ------------------ | ---------------------------------------------------- | -------------------------- |
| Fee shares         | Vault.balanceOf(vault)                               | Share of totalAssets       |
| Collectable shares | VaultStorage.\_collectableRewardFeesShares           | Same as above              |
| Pending reward fee | FeeDispatcher.\_dispatches[vault].\_pendingRewardFee | Collected connector assets |
