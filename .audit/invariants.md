# Krait Fuzz — Invariant Catalog

## Core Contract: FeeDispatcher

| ID    | Category     | Description                                                                                  | Formal Expression                                                        | Priority |
| ----- | ------------ | -------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | -------- |
| FD-01 | accounting   | Pending deposit fee can never exceed the dispatched total when recipients are set            | `pendingDepositFee == 0 \|\| sum(dispatch amounts) <= pendingDepositFee` | high     |
| FD-02 | accounting   | Total deposit fee split always equals \_MAX_PERCENT \* 10^decimals                           | `totalDepositFeeSplit == 100 * 10^decimals`                              | high     |
| FD-03 | accounting   | Total reward fee split always equals \_MAX_PERCENT \* 10^decimals                            | `totalRewardFeeSplit == 100 * 10^decimals`                               | high     |
| FD-04 | bounds       | depositFeeSplit per recipient is non-zero                                                    | `recipient.depositFeeSplit > 0`                                          | low      |
| FD-05 | accounting   | After dispatch, the remaining pending fee is the difference between original and transferred | `pendingAfter = pendingBefore - transferred`                             | medium   |
| FD-06 | relationship | Each address's fee state is independent — no cross-address contamination                     | `dispatches[A] != dispatches[B]` for A != B                              | medium   |
| FD-07 | bounds       | Fee dispatcher loops are bounded by recipient count (not unbounded)                          | `recipients.length <= MAX_RECIPIENTS`                                    | low      |

## Core Contract: Vault

| ID   | Category           | Description                                                              | Formal Expression                                                    | Priority |
| ---- | ------------------ | ------------------------------------------------------------------------ | -------------------------------------------------------------------- | -------- |
| V-01 | accounting         | Total supply is sum of all user balances (ERC20 invariant — OZ enforces) | `totalSupply() == sum(balanceOf(user))`                              | high     |
| V-02 | economic           | ConvertToShares(x) <= x (rounding favors vault)                          | `convertToShares(assets) * convertToAssets(1) <= assets`             | high     |
| V-03 | economic           | ConvertToAssets(x) >= x (rounding favors vault)                          | `convertToAssets(shares) * convertToShares(1) >= shares`             | high     |
| V-04 | bounds             | Reward fee never exceeds \_MAX_FEE                                       | `rewardFee <= 35 * 10^decimals`                                      | high     |
| V-05 | bounds             | Deposit fee never exceeds \_MAX_FEE                                      | `depositFee <= 35 * 10^decimals`                                     | high     |
| V-06 | state-transition   | transferable can only be set by FEE_MANAGER_ROLE                         | `onlyRole(FEE_MANAGER_ROLE) on _setTransferable`                     | medium   |
| V-07 | state-transition   | Only SANCTIONS_MANAGER can set blocklist                                 | `onlyRole(SANCTIONS_MANAGER_ROLE) on setBlockList`                   | medium   |
| V-08 | accounting         | After deposit, assets move from user to vault                            | `balanceOf(vault, after) - balanceOf(vault, before) = depositAmount` | high     |
| V-09 | bounds             | Offset never exceeds \_MAX_OFFSET                                        | `offset <= 23`                                                       | medium   |
| V-10 | economic           | Deposit returns zero shares when assets == 0                             | `deposit(0) → PreviewZero revert or 0 shares`                        | medium   |
| V-11 | access-control     | Only factory can call initialize and upgrade                             | `onlyFactory on initialize()`                                        | high     |
| V-12 | access-control     | Only FEE_COLLECTOR_ROLE can call collectRewardFees                       | `onlyRole(FEE_COLLECTOR_ROLE) on collectRewardFees()`                | high     |
| V-13 | access-control     | Only PAUSER_ROLE can call pauseDeposit                                   | `onlyRole(PAUSER_ROLE) on pauseDeposit()`                            | high     |
| V-14 | ordering           | Withdrawals are guarded by nonReentrant                                  | `nonReentrant on withdraw()`                                         | medium   |
| V-15 | token-conservation | Vault token balance equals connector total                               | `balanceOf(asset) + connectorBalance >= totalAssets()`               | high     |
| V-16 | accounting         | lastTotalAssets is updated after every deposit/withdrawal                | `after: lastTotalAssets == totalAssets()`                            | high     |

## Core Contract: ConnectorRegistry

| ID    | Category         | Description                                    | Formal Expression                      | Priority |
| ----- | ---------------- | ---------------------------------------------- | -------------------------------------- | -------- |
| CR-01 | state-transition | Frozen connectors cannot be updated or removed | `frozen → revert on update/remove`     | high     |
| CR-02 | state-transition | Only CONNECTOR_MANAGER can add connectors      | `onlyRole(CONNECTOR_MANAGER) on add()` | high     |
| CR-03 | access-control   | Only PAUSER can pause connectors               | `onlyRole(PAUSER_ROLE) on pause()`     | high     |

## Core Contract: BlockList

| ID    | Category         | Description                             | Formal Expression                             | Priority |
| ----- | ---------------- | --------------------------------------- | --------------------------------------------- | -------- |
| BL-01 | access-control   | Only OPERATOR_ROLE can add to blocklist | `onlyRole(OPERATOR_ROLE) on addToBlockList()` | high     |
| BL-02 | state-transition | Removing non-blocked address reverts    | `removeFromBlockList(unblocked) → revert`     | medium   |
