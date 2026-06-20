# Batch 7 — Vault Authorization Review

## Privileged Functions in Vault.sol

| Function                         | Role Required            | Can Revert On            |
| -------------------------------- | ------------------------ | ------------------------ |
| `initialize()`                   | `onlyFactory`            | Non-factory callers      |
| `upgrade()`                      | `onlyFactory`            | Non-factory callers      |
| `delegateToFactory()`            | `onlyFactory`            | Non-factory callers      |
| `setDepositFee()`                | `FEE_MANAGER_ROLE`       | Unauthorized             |
| `setRewardFee()`                 | `FEE_MANAGER_ROLE`       | Unauthorized             |
| `setFeeRecipients()`             | `FEE_MANAGER_ROLE`       | Unauthorized             |
| `collectRewardFees()`            | `FEE_COLLECTOR_ROLE`     | Unauthorized             |
| `setBlockList()`                 | `SANCTIONS_MANAGER_ROLE` | Unauthorized             |
| `claimAdditionalRewards()`       | `CLAIM_MANAGER_ROLE`     | Unauthorized             |
| `setAdditionalRewardsStrategy()` | `CLAIM_MANAGER_ROLE`     | Unauthorized             |
| `pauseDeposit()`                 | `PAUSER_ROLE`            | Unauthorized             |
| `unpauseDeposit()`               | `UNPAUSER_ROLE`          | Unauthorized             |
| `forceWithdraw()`                | **Permissionless**       | Non-blocked user         |
| `dispatchFees()`                 | **Permissionless**       | None                     |
| `transfer()`                     | checkTransferability     | Blocked/non-transferable |
| `transferFrom()`                 | checkTransferability     | Blocked/non-transferable |
| `approve()`                      | checkTransferability     | Blocked/non-transferable |

## Authorization Test Matrix

All tests verify that:

1. Authorized caller succeeds
2. Unauthorized EOA reverts
3. Unauthorized contract reverts
4. Different role holders cannot call unrelated functions
