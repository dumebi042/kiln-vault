# Nemesis — Pass 4: State Re-Analysis (Targeted)

## Scope: Only new coupled pairs and mutation paths from Pass 3

### FF-005: collectRewardFees unminted shares — State analysis

**Does this root cause affect OTHER coupled pairs?**

The root cause: `collectRewardFees()` computes R' via VIEW function (no mint), uses C+R' for asset conversion, but burns only C. The R' shares are never minted.

**Coupled pairs affected:**

| Coupled Pair                                | Is FF-005 breaking it?                                                                                                                                                                   |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| \_collectableRewardFeesShares ↔ totalSupply | ❌ C tracks only minted shares. After FF-005 runs: C=0, R' never minted, so C says "0 reward shares owed" while assets were withdrawn. But totalSupply is correct (R' was never minted). |
| totalAssets ↔ totalSupply (share price)     | ✅ **YES.** After FF-005: TA decreased by withdrawn assets, supply unchanged. Share price is reduced. Remaining shareholders lost value.                                                 |
| \_pendingRewardFee ↔ vault asset balance    | ✅ **YES.** Assets were withdrawn and credited as fee, but the corresponding shares were never burned. The vault has fewer assets than the share price implies.                          |

**Parallel path comparison:**

| Path                                           | Mints Fee Shares? | Burns Fee Shares?  | Withdraws Assets? | Correct?        |
| ---------------------------------------------- | ----------------- | ------------------ | ----------------- | --------------- |
| deposit() → \_accrueRewardFee                  | ✅ Yes            | N/A (accrues only) | N/A               | ✅              |
| withdraw() → \_accrueRewardFee                 | ✅ Yes            | N/A (accrues only) | N/A               | ✅              |
| setRewardFee() → \_accrueRewardFee             | ✅ Yes            | N/A                | N/A               | ✅              |
| collectRewardFees() → \_accruedRewardFeeShares | ❌ VIEW only      | ✅ (C only)        | ✅                | ❌ **MISMATCH** |

**Additional gaps discovered via root cause propagation:**

If FEE_COLLECTOR calls collectRewardFees() when C = 0 and R' > 0:

1. R' computed via view function
2. Assets withdrawn equal to R' share value
3. 0 shares burned
4. C remains 0

On the NEXT deposit/withdrawal that calls \_accrueRewardFee():

1. newR' computed from yield since lastTA
2. newR' shares MINTED to vault → C += newR'
3. But the assets for the PREVIOUS R' (which was never minted) were already taken
4. C now includes newR' (current yield) but NOT the old R' (which was never tracked)

So the fee is correctly tracked going forward, but the asset value of the old unminted R' is permanently extracted without burning shares. This is a one-time loss per collectRewardFees call where C=0.

### FF-006: \_lastTotalAssets high-water mark — State analysis

**Does this root cause affect OTHER coupled pairs?**

The root cause: `trySub` returns 0 when totalAssets < \_lastTotalAssets. No function ever reduces \_lastTotalAssets.

**Coupled pairs affected:**

| Coupled Pair                                   | Is FF-006 breaking it?                                                                  |
| ---------------------------------------------- | --------------------------------------------------------------------------------------- |
| \_lastTotalAssets ↔ \_accruedRewardFeeShares() | ✅ **YES.** Stale high-water mark inflates computed reward fee on recovery.             |
| \_lastTotalAssets ↔ new deposit share price    | ✅ **YES.** If \_lastTotalAssets is too high, \_accrueRewardFee minted too many shares. |

**Parallel path comparison:**

All functions that update \_lastTotalAssets only set it to `totalAssets()` or higher. None ever reduce it. This is a one-directional tracker.

No additional gaps: the high-water mark behavior is inherent to the design, not a missing function call. The fix would be to reduce \_lastTotalAssets to `min(lastTA, currentTA)` during loss events.

## Convergence Check

Pass 4 produced:

- FF-005 confirmed as affecting share price (TA/supply) and fee/asset coupling
- FF-006 confirmed as affecting fee computation on recovery
- NO new coupled pairs discovered
- NO new mutation paths discovered
- NO new gaps found

**Result**: CONVERGED. No new findings in Pass 4.

Combined across all 4 passes:

- Pass 1 (Feynman): 6 findings, 7 suspects
- Pass 2 (State): 4 state gaps
- Pass 3 (Feynman targeted): 2 new findings
- Pass 4 (State targeted): 0 new findings

**Convergence status**: CONVERGED after 4 passes. Max allowed: 6.
Proceeding to verification and final consolidation.
