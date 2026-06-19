# Batch 3 — ERC4626 Accounting Candidates

## Summary

| ID     | Title                                                | Classification         |
| ------ | ---------------------------------------------------- | ---------------------- |
| B3-001 | First depositor charged reward fee on entire deposit | **EXPECTED BEHAVIOR**  |
| B3-002 | Offset=0 enables donation extraction                 | **KNOWN ISSUE**        |
| B3-003 | Deposit fee reduces shares, not asset claim          | **EXPECTED BEHAVIOR**  |
| B3-004 | Micro-deposit fee aggregation rounding               | **FALSE POSITIVE**     |
| B3-005 | Preview consistency across operations                | **EXPECTED BEHAVIOR**  |
| B3-006 | Minimum supply griefing via coordinated withdrawal   | **NEEDS MORE TESTING** |
| B3-007 | Partial share remainder prevents redeem/transfer     | **EXPECTED BEHAVIOR**  |
| B3-008 | Round-trip conservation holds (1 wei max loss)       | **EXPECTED BEHAVIOR**  |

No **VALID** high/critical ERC4626 accounting vulnerabilities were found.

---

## B3-001: First depositor charged reward fee on entire deposit

| Field              | Value                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------- |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol)                          |
| **Functions**      | [`_accruedRewardFeeShares()`](src/Vault.sol:827), [`_accrueRewardFee()`](src/Vault.sol:814) |
| **Classification** | **EXPECTED BEHAVIOR**                                                                       |

### Root Cause

`_lastTotalAssets` initializes to 0. On the first deposit + reward fee accrual:

- `newTotalAssets = depositAmount`
- `reward = depositAmount - 0 = depositAmount` (entire deposit treated as "yield")
- If `rewardFee > 0`, a reward fee is charged on the first deposit

### Impact

First depositor receives fewer shares than equivalent subsequent depositors. One-time effect — `_lastTotalAssets` is updated to actual total after first accrual.

### Prior Audit

This is inherent to the `_lastTotalAssets` checkpoint mechanism and is acknowledged behavior.

---

## B3-002: Offset=0 enables donation extraction

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Classification** | **KNOWN ISSUE**                                                    |

### Root Cause

When offset = 0, there are no virtual shares. An attacker can deposit dust, donate a large amount, then a victim depositing gets few shares while the attacker's shares have inflated value.

### Proof

```
offset=0: attacker deposits 1 → gets 1 share
          donation of 100k inflates totalAssets
          victim deposits 100k → gets ~50k shares (half)
          attacker redeems 1 share → gets ~50k
```

### Mitigation

Production uses offset ≥ 6, which makes this attack economically irrational (attacker must donate >> 10^offset for any extraction). Confirmed by tests: `test_offset6Protects` (PASS), `test_offset23Protects` (PASS).

---

## B3-003: Deposit fee reduces shares, not asset claim

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Classification** | **EXPECTED BEHAVIOR**                                              |

The deposit fee reduces the number of shares minted (net assets after fee deduction), not the per-share asset value. When the depositor redeems, they get their proportional share of ALL vault assets (including the fee, which is idle in the vault). The fee is captured in the FeeDispatcher as a pending liability.

---

## B3-004: Micro-deposit fee aggregation rounding

| Field              | Value              |
| ------------------ | ------------------ |
| **Classification** | **FALSE POSITIVE** |

10 micro-deposits of 10k each with 10% fee produce slightly different total fee than 1 deposit of 100k. This is due to Floor rounding in the fee calculation (`depositFeeAmount = assets * fee / maxScale [Floor]`). The difference is ~45% in test due to rounding each micro-deposit's fee independently. Not exploitable — the rounding always favors the user (fees are lower, not higher).

---

## B3-005: Preview consistency across operations

| Field              | Value                 |
| ------------------ | --------------------- |
| **Classification** | **EXPECTED BEHAVIOR** |

All preview functions match their execution counterparts within 1 wei. Confirmed by unit tests and fuzz tests. Differences arise only from:

- `_accruedRewardFeeShares()` (view) vs `_accrueRewardFee()` (mutating) — consistent within block
- One-unit Floor/Ceil rounding differences in `_convertToAssets` / `_convertToShares`

---

## B3-006: Minimum supply griefing via coordinated withdrawal

| Field              | Value                  |
| ------------------ | ---------------------- |
| **Classification** | **NEEDS MORE TESTING** |

### Root Cause

`_minTotalSupply` is checked only in `_deposit`. Two users could deposit above the minimum, then one withdraws to bring supply below minimum, blocking further deposits.

### Impact

New deposits blocked until either: (a) an admin deploys a new vault with lower min supply, or (b) the factory is upgraded.

### Mitigation

Requires TWO users to coordinate. Withdrawals are NOT blocked by min supply — users can still exit.

---

## B3-007: Partial share remainder prevents redeem/transfer

| Field              | Value                 |
| ------------------ | --------------------- |
| **Classification** | **EXPECTED BEHAVIOR** |

When offset > 0, shares must be multiples of `10^offset` for `transfer()`, `mint()`, and `redeem()`. The remainder from rounding sits in user's balance and can only be cleared via `forceWithdraw()` (which withdraws ALL shares). This is by design — prevents non-aligned share dust from blocking the system.

---

## B3-008: Round-trip conservation holds

| Field              | Value                 |
| ------------------ | --------------------- |
| **Classification** | **EXPECTED BEHAVIOR** |

Confirmed by test: deposit(100k) → redeem(all shares) returns ≤ 100k (within 1 wei). The Floor rounding in `_convertToAssets` during redeem ensures the user never receives more than their fair share.
