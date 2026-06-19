# Nemesis — Pass 3: Feynman Re-Interrogation (Targeted)

## Scope: Only State Gaps G-01 through G-05 from Pass 2

### G-01: \_lastTotalAssets not updated on value loss — Feynman Deep Dive

**Pass 2 finding**: When connector loses value, `trySub(newTA, lastTA)` returns 0. `_lastTotalAssets` stays at ATH. Recovery yield up to the ATH generates no fee.

**Feynman interrogation**:

```
Q: WHY doesn't any function update _lastTotalAssets downward?
→ Because _lastTotalAssets is designed as a yield capture mechanism.
  It's set to totalAssets() at the END of each deposit/withdraw/collect.
  If yield is negative (loss), there's nothing to capture.
  The high-water mark ensures fee is only taken on net positive yield
  since the last interaction.

Q: What ASSUMPTION led to this design?
→ "totalAssets() never decreases significantly between user interactions."
  This is FALSE for connectors that can experience bad debt (Aave shortfall events,
  Morpho market insolvency, stablecoin depeg).

Q: What DOWNSTREAM function reads both and breaks?
→ _accruedRewardFeeShares() reads totalAssets() and _lastTotalAssets.
  If they diverge (loss, no user interaction), the next _accrueRewardFee()
  over-counts the recovery as yield.

Q: Can an attacker CHOOSE a sequence to exploit this?
→ Attacker cannot directly trigger connector loss (external event).
→ But: a whale depositor who times their deposits to avoid loss periods
  can avoid paying fees on recovery yield that other users' deposits paid for.
```

**Root cause**: `_lastTotalAssets` is a one-directional tracker (only increases via yield, never decreases via loss). This is intentional for yield accounting but creates a blind spot during loss/recovery cycles.

### G-02: dispatchFees rounding dust — Feynman Deep Dive

**Pass 2 finding**: Floor rounding in mulDiv leaves residual that never dispatches.

**Feynman interrogation**:

```
Q: WHY does dispatchFees use Floor rounding?
→ Standard mulDiv behavior. No explicit rounding choice — OpenZeppelin's mulDiv
  defaults to truncation toward zero (Floor for positive values).

Q: What ASSUMPTION led to this gap?
→ "Each recipient's split will exactly total 100% and amounts will be
  perfectly divisible."
  This is FALSE for most real-world fee amounts.

Q: What DOWNSTREAM reads the accumulator and breaks?
→ The accumulator _pendingDepositFee tracks "how much fee is owed."
  When it never reaches zero, there's always a "stub" owed that can never
  be paid. This grows unbounded.

Q: Can an attacker amplify this?
→ Not directly — each dispatch only loses 1-2 wei per recipient.
  Over thousands of cycles, it's bounded by gas costs.
```

**Root cause**: Floor rounding in proportional distribution without trailing-dust sweep.

### G-03: collectRewardFees unminted R' shares — Feynman Deep Dive (CRITICAL)

**Pass 2 finding**: `_accruedRewardFeeShares()` computes R' (view-only, no mint). `collectRewardFees` uses C+R' for asset conversion, but burns only C.

**Feynman interrogation**:

```
Q: WHY does _accruedRewardFeeShares return view-only shares?
→ Because _accrueRewardFee() (non-view) mints the shares and updates state.
  But collectRewardFees calls the VIEW version — it never mints R'!

Q: What is the EXACT code path?
collectRewardFees:
  L923: (R', newTA) = _accruedRewardFeeShares()  ← VIEW, no mint
  L926-930: collectable = convertToAssets(C + R', Floor, newTA, supply + R')
  L935: connector.withdraw(asset, collectable)    ← REAL ASSETS LEAVE
  L937: incrementPendingRewardFee(actualReceived) ← FEES RECORDED
  L939: _burn(address(this), C)                   ← ONLY C BURNED
  L940: C = 0

Where C = _collectableRewardFeesShares (previously minted via _accrueRewardFee)
      R' = _rewardFeeShares (unminted, from view function)

Q: When C = 0 and R' > 0:
  1. collectable = convertToAssets(R', Floor, newTA, supply + R')
  2. Assets withdrawn from connector
  3. _burn(address(this), 0) — NOTHING BURNED
  4. R' shares were NEVER minted → they don't exist in totalSupply
  5. After this call: supply unchanged, assets withdrawn, fee recorded
  6. Share price: (TA - withdrawn) / supply < TA / (supply + R') ← INFLATED

Q: What's the CONCRETE attack?
Vault state: TA = 1,010,000 USDC, lastTA = 1,000,000, supply = 1B shares
             C = 0 (no prior reward accrual), offset = 6, rewardFee = 10%

1. FEE_COLLECTOR calls collectRewardFees()
2. R' = 9,900,990 shares (yield of 10k USDC, 10% fee)
3. collectable = convertToAssets(9,900,990, Floor, 1,009,900,000,000, 1,009,900,990)
              ≈ 999,000 micro-USDC
4. 999,000 micro-USDC withdrawn from connector → sent to FeeDispatcher
5. _burn(address(this), 0) — nothing burned
6. C = 0, lastTA = TA_after_withdrawal
7. Supply still 1B, TA reduced by 999,000
8. Share price DROPS: remaining users lost value

Q: Why is this NOT caught by nonReentrant?
→ nonReentrant prevents REENTRY, not this accounting error.
   The error is that R' is used for computation but never minted or burned.

Q: Can this be called MULTIPLE TIMES?
→ Yes! FEE_COLLECTOR can call collectRewardFees() as often as they want.
   Each call: computes new R' from latest yield, withdraws assets, burns 0.
   But C stays 0 unless _accrueRewardFee (non-view) was called in between.

ACTUAL BEHAVIOR: collectRewardFees works correctly ONLY if C > 0,
which requires a deposit/withdrawal (which calls _accrueRewardFee) to happen
BETWEEN collectRewardFees calls.

If FEE_COLLECTOR calls collectRewardFees() twice in a row WITHOUT an intermediate
deposit/withdrawal:
  First call: R'=9.9M (yield since lastTA), withdraws assets, burns C=0
  Second call: R'=0 (lastTA was just updated), collects nothing
  → Only one call extracts value without burning shares.
```

**Root cause**: `collectRewardFees()` uses view-only `_accruedRewardFeeShares()` that never mints. It should use the mutating `_accrueRewardFee()` that actually mints shares before burning them.

**Verdict**: **TRUE POSITIVE** — MEDIUM (requires FEE_COLLECTOR to call without prior deposit/withdrawal, or more severely, repeated extraction if shares accumulative)

### G-04: Fee recipients reconfiguration redistributes pending fees

**Feynman interrogation**:

```
Q: WHY does setFeeRecipients delete old recipients but KEEP pending fees?
→ It only deletes the recipients array. The pending fees remain.
  Next dispatchFees() uses NEW split ratios on OLD accumulated fees.

Q: Is this exploitable?
→ FEE_MANAGER_ROLE controls this. If they want to reward new recipients
  with old fees, they can. This is a design choice, not a vulnerability.
```

**Verdict**: **FALSE POSITIVE** — Intentional design (GATE C)

### G-05: FeeDispatcher functions have no access control

**Feynman interrogation**:

```
Q: WHY no onlyRole()?
→ Each function keys off $._dispatches[msg.sender]. Every address scoped to own state.
  No cross-address tampering possible.

Q: Exploitable?
→ incrementPendingDepositFee(amount) → only inflates caller's own pending fee
→ dispatchFees needs safeTransferFrom(caller, recipient) → caller must have approved
  FeeDispatcher and have the balance
→ Self-scoped, no exploit across vaults
```

**Verdict**: **FALSE POSITIVE** — msg.sender scoping by design

---

## Pass 3 — New Findings

| ID     | Finding                                                                              | Source          | Severity   |
| ------ | ------------------------------------------------------------------------------------ | --------------- | ---------- |
| FF-005 | collectRewardFees uses unminted shares — asset extracted without burning counterpart | G-03 cross-feed | **MEDIUM** |
| FF-006 | \_lastTotalAssets is one-directional — double-fees on recovery yield                 | G-01            | LOW        |

## Pass 3 — New Suspects (if any)

None. G-03 produced concrete finding FF-005. G-04 and G-05 disproven by code.

## Convergence Check

Pass 3 produced 2 new findings compared to Pass 1+2:

- FF-005 (MEDIUM) — collectRewardFees unminted shares
- FF-006 (LOW) — high-water mark double-fee

Proceed to Pass 4 (State re-analysis) to check if these reveal additional coupled pairs.
