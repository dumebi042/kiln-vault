# Batch 3 — ERC4626 Accounting Candidates

## Summary

| ID     | Title                                                | Classification        |
| ------ | ---------------------------------------------------- | --------------------- |
| B3-001 | First depositor charged reward fee on entire deposit | **FALSE POSITIVE**    |
| B3-002 | Offset=0 enables donation extraction                 | **FALSE POSITIVE**    |
| B3-003 | Deposit fee reduces shares, not asset claim          | **EXPECTED BEHAVIOR** |
| B3-004 | Micro-deposit fee aggregation rounding               | **FALSE POSITIVE**    |
| B3-005 | Preview consistency across operations                | **EXPECTED BEHAVIOR** |
| B3-006 | Minimum supply griefing via coordinated withdrawal   | **EXPECTED BEHAVIOR** |
| B3-007 | Partial share remainder prevents redeem/transfer     | **EXPECTED BEHAVIOR** |
| B3-008 | Round-trip conservation holds (1 wei max loss)       | **EXPECTED BEHAVIOR** |

No **VALID** high/critical ERC4626 accounting vulnerabilities were found.

---

## B3-001: First depositor charged reward fee on entire deposit

| Field              | Value                                                                                       |
| ------------------ | ------------------------------------------------------------------------------------------- |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol)                          |
| **Functions**      | [`_accruedRewardFeeShares()`](src/Vault.sol:827), [`_accrueRewardFee()`](src/Vault.sol:814) |
| **Classification** | **FALSE POSITIVE**                                                                          |

### Root Cause Analysis

The suspect claim: on the first deposit, `_lastTotalAssets = 0`, so `newTotalAssets - 0 = newTotalAssets` is treated as yield, and a reward fee is charged.

**This is incorrect because of execution order.**

The deposit flow is:

```
deposit(assets, receiver)
  1. _newTotalAssets = _accrueRewardFee()     ← runs BEFORE asset transfer
  2. (_shares, _depositFeeAmount) = _previewDeposit(assets, _newTotalAssets, totalSupply())
  3. _deposit(caller, receiver, assets, shares, _depositFeeAmount)
     a. safeTransferFrom(caller, vault, assets)  ← asset transfer happens HERE
     b. connector.deposit(...)
     c. _lastTotalAssets = totalAssets()          ← _lastTotalAssets updated HERE
```

Step 1 calls `_accruedRewardFeeShares()`:

- `newTotalAssets = totalAssets()` → for an empty vault, this returns **0** (no assets yet)
- `(_reward, _) = newTotalAssets.trySub(_lastTotalAssets)` → `0.trySub(0)` → reward = **0**
- No reward fee is computed because `totalAssets = 0` before the deposit

The reward fee is only computed on the **increase** in totalAssets since the last snapshot. On the first deposit, there is no increase because no assets have been transferred yet.

After step 3c, `_lastTotalAssets = totalAssets()` correctly captures the total. On subsequent deposits, only genuine yield increases between checkpoints trigger reward fees.

### Conclusion

No reward fee is charged on the first deposit. The `_lastTotalAssets` checkpoint starts at 0, but `_accrueRewardFee()` runs before any asset transfer, so the computed reward is always 0 on an empty vault.

---

## B3-002: Offset=0 enables donation extraction

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Classification** | **FALSE POSITIVE**                                                 |

### Root Cause Analysis

The claim: with offset=0, the vault has no virtual shares, making donation extraction profitable.

**This is incorrect. Even with offset=0, the OZ v5 formulas impose virtual terms:**

```
virtual shares = 10^offset = 10^0 = 1
virtual assets = 1
```

Conversion formulas (Vault overrides at L789, L799):

```
shares = assets * (supply + 10^offset) / (totalAssets + 1)
assets = shares * (totalAssets + 1) / (supply + 10^offset)
```

### Exact Arithmetic: offset=0, attacker deposits 1, donates 100k, victim deposits 100k

**Step 1 — Attacker deposits 1 unit:**

```
totalAssets = 0, totalSupply = 0
shares = 1 * (0 + 1) / (0 + 1) = 1
```

Attacker gets 1 share. State: totalAssets=1, totalSupply=1.

**Step 2 — Attacker donates 100,000 units:**

```
totalAssets = 100,001, totalSupply = 1 (unchanged)
```

State: totalAssets=100,001, totalSupply=1.

**Step 3 — Victim deposits 100,000 units:**

```
shares = 100,000 * (1 + 1) / (100,001 + 1) = 200,000 / 100,002 = 1 (Floor)
```

Victim gets 1 share. State: totalAssets=200,001, totalSupply=2.

**Step 4 — Attacker redeems 1 share:**

```
assets = 1 * (200,001 + 1) / (1 + 1) = 200,002 / 2 = 100,001 (Floor)
```

Attacker receives 100,001 units.

**Step 5 — Attacker net result:**

```
Attacker spent: 1 (deposit) + 100,000 (donation) = 100,001
Attacker recovered: 100,001 (redemption)
Net: 100,001 - 100,001 = 0
```

The attacker breaks even — no profit, no loss.

**Step 6 — Victim redeems 1 share:**

```
assets = 1 * (200,001 + 1) / (1 + 1) = 100,001 (Floor)
Victim deposited: 100,000
Victim recovered: 100,001
Victim gains 1 unit (rounding)
```

### Parameter Search

| Atk deposit | Donation  | Victim deposit | Atk cost  | Atk redemption | Net profit   |
| ----------- | --------- | -------------- | --------- | -------------- | ------------ |
| 1           | 100,000   | 100,000        | 100,001   | 100,001        | **0**        |
| 1           | 1,000,000 | 100,000        | 1,000,001 | 500,001        | **-500,000** |
| 1,000       | 1,000,000 | 100,000        | 1,001,000 | 501,000        | **-500,000** |
| 100,000     | 1,000,000 | 100,000        | 1,100,000 | 600,000        | **-500,000** |

In every case, the attacker's donation cost exceeds or equals their redemption proceeds. **The attack is never profitable** because:

1. The virtual share (1 share) and virtual asset (1 unit) ensure the attacker cannot extract more than they contribute
2. The attacker's donation is shared pro-rata with ALL holders, including the attacker themselves
3. Even with offset=0, the attacker always recovers ≤ their total contribution

### Mitigation

Production uses offset ≥ 6, which further increases the attacker's loss (the virtual 10^offset shares dilute the attacker's extraction).

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

10 micro-deposits of 10k each with 10% fee produce slightly different total fee than 1 deposit of 100k. This is due to Floor rounding in the fee calculation (`depositFeeAmount = assets * fee / maxScale [Floor]`). The rounding always favors the user (fees are lower, not higher).

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

| Field              | Value                 |
| ------------------ | --------------------- |
| **Classification** | **EXPECTED BEHAVIOR** |

### Analysis

`_minTotalSupply` is checked only in `_deposit` (Vault.sol L633):

```solidity
if (totalSupply() < $._minTotalSupply) revert MinimumTotalSupplyNotReached();
```

### Key Questions Answered

1. **Can one unprivileged user alone push supply below minimum?** Yes — the user can withdraw their entire position.
2. **Does the withdrawal that crosses below the minimum succeed?** Yes — withdrawals are NOT checked against min supply.
3. **Once below minimum, are only deposits blocked?** Yes — withdrawals, transfers, and fee operations all work normally.
4. **Can an existing holder restore the vault?** Yes — depositing enough to exceed the minimum re-enables deposits.
5. **Can a new depositor deposit directly above the minimum?** Yes — the `_minTotalSupply` check only verifies `totalSupply >= minTotalSupply` after the deposit. A deposit large enough to push the total above the minimum succeeds.
6. **Can fee minting, donations, or transfers restore usability?** Yes — reward fee accrual mints shares to the vault, increasing totalSupply. Direct donations also work.
7. **Can an attacker create this condition without cooperating?** No — the attacker must withdraw their own position, which drops supply. The attacker cannot touch other users' shares.
8. **Can the attacker profit?** No — the attacker loses their position.
9. **Are user funds permanently locked?** No — withdrawals still work.
10. **Does this affect production?** Only if `_minTotalSupply > 0` and all depositors exit except one who then exits.

### Conclusion

The minimum supply check is a dust-prevention mechanism, not a DoS protection. The "attack" requires self-sacrifice, provides no profit, and can be reverted by any depositor or donor.

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
