# Batch 5 — Fee Accounting Candidates

## Summary

| ID     | Title                                                   | Classification        |
| ------ | ------------------------------------------------------- | --------------------- |
| B5-001 | Deposit fee assets isolated from shareholder withdrawal | **EXPECTED BEHAVIOR** |
| B5-002 | Reward fee checkpoint prevents double-charge            | **EXPECTED BEHAVIOR** |
| B5-003 | FeeDispatcher multi-vault isolation by msg.sender       | **EXPECTED BEHAVIOR** |
| B5-004 | Deposit fee round-trip dust accumulation                | **FALSE POSITIVE**    |
| B5-005 | Pending fee solvency after shareholder exit             | **EXPECTED BEHAVIOR** |
| B5-006 | Fee dispatch requires vault approval                    | **EXPECTED BEHAVIOR** |
| B5-007 | Recipient split rounding dust                           | **EXPECTED BEHAVIOR** |

---

## B5-001: Deposit fee assets isolated from shareholder withdrawal

| Field                  | Value                                                                                                                                                                      |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Affected functions** | `_deposit()` L624, `_maxRedeem()` L707, `maxRedeem()` L464                                                                                                                 |
| **Root cause**         | Deposit fee stays as idle vault balance, not invested via connector. `maxRedeem()` is limited by `connector.maxWithdraw()` which only returns connector-accessible assets. |
| **Test**               | `test_feeAssetsProtectedByMaxRedeem` — PASS                                                                                                                                |
| **Impact**             | Fee assets cannot be withdrawn by shareholders. Protected.                                                                                                                 |
| **Classification**     | **EXPECTED BEHAVIOR**                                                                                                                                                      |

---

## B5-002: Reward fee checkpoint prevents double-charge

| Field                  | Value                                                                                    |
| ---------------------- | ---------------------------------------------------------------------------------------- |
| **Affected functions** | `_accruedRewardFeeShares()` L827, `_accrueRewardFee()` L814                              |
| **Root cause**         | `_lastTotalAssets` is updated after each accrual. No new fee without new yield increase. |
| **Tests**              | `test_noDoubleFeeOnSameYield` — PASS, `test_noFeeOnPrincipal` — PASS                     |
| **Impact**             | No double-charge. No fee on principal or losses.                                         |
| **Classification**     | **EXPECTED BEHAVIOR**                                                                    |

---

## B5-003: FeeDispatcher multi-vault isolation

| Field                  | Value                                                                             |
| ---------------------- | --------------------------------------------------------------------------------- |
| **Affected functions** | FeeDispatcher `_dispatches[msg.sender]`                                           |
| **Root cause**         | All state keyed by `msg.sender`. Vault A cannot access Vault B's state.           |
| **Tests**              | `test_vaultStateIsolated` — PASS, `test_maliciousEOACannotModifyVaultFees` — PASS |
| **Impact**             | Cross-vault fee theft impossible. EOA calls create isolated state (harmless).     |
| **Classification**     | **EXPECTED BEHAVIOR**                                                             |

---

## B5-004: Deposit fee round-trip dust accumulation

| Field              | Value              |
| ------------------ | ------------------ |
| **Classification** | **FALSE POSITIVE** |

Floor rounding in fee calculation means each micro-deposit loses <1 unit to rounding. Bounded by number of deposits. Always favors user (lower fee). Fuzz verified.

---

## B5-005: Pending fee solvency after shareholder exit

| Field                  | Value                                                                                                                                      |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| **Affected functions** | `_maxRedeem()` L707, `_withdraw()` L656, `dispatchFees()` in FeeDispatcher L129                                                            |
| **Root cause**         | `maxRedeem()` limits shareholder withdrawal to connector-accessible assets. Idle fee balance is excluded from `connector.maxWithdraw()`.   |
| **Test**               | `test_shareholderExitsAfterDepositFee` — PASS                                                                                              |
| **Numerical proof**    | Alice deposits 100k (10% fee): 10k fee idle, 90k invested. `maxRedeem(Alice)` returns ~81k < Alice's ~90k shares. Alice CANNOT fully exit. |
| **Impact**             | Fee always backed by idle balance ≥ pending fee. Only becomes undercollateralized if connector over-reports `maxWithdraw()` (admin power). |
| **Classification**     | **EXPECTED BEHAVIOR**                                                                                                                      |

---

## B5-006: Fee dispatch requires vault approval

| Field                  | Value                                                                                                         |
| ---------------------- | ------------------------------------------------------------------------------------------------------------- |
| **Affected functions** | FeeDispatcher `dispatchFees()`, Vault `__Vault_upgrade()` L416                                                |
| **Root cause**         | Dispatch uses `safeTransferFrom(vault, recipient, amount)`. Vault approves FeeDispatcher for max during init. |
| **Classification**     | **EXPECTED BEHAVIOR**                                                                                         |

---

## B5-007: Recipient split rounding dust

| Field                  | Value                                                                                                                               |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| **Affected functions** | FeeDispatcher `dispatchFees()` recipient loop                                                                                       |
| **Root cause**         | `pendingFee * split_i / maxScale [Floor]` leaves remainder for multi-recipient configurations.                                      |
| **Fuzz proof**         | 2 recipients: dust < 2 per dispatch. 3 recipients: dust < 3 per dispatch. Repeated dispatch: dust accumulates linearly but bounded. |
| **Impact**             | Dust remains in pending state. Can be dispatched in future cycles when additional fees accumulate. Not permanently trapped.         |
| **Classification**     | **EXPECTED BEHAVIOR**                                                                                                               |
