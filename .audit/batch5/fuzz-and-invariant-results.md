# Batch 5 — Fuzz and Invariant Test Results

## Fuzz Tests

### FeeDispatchDustFuzz

| Test                            | Runs | Result | Property                              |
| ------------------------------- | ---- | ------ | ------------------------------------- |
| `testFuzz_singleRecipientExact` | 256  | PASS   | Single recipient has 0 remainder      |
| `testFuzz_twoRecipientsDust`    | 256  | PASS   | Dust bounded by recipient count (< 2) |
| `testFuzz_threeRecipientsDust`  | 256  | PASS   | Dust bounded by recipient count (< 3) |
| `testFuzz_repeatedDispatchDust` | 256  | PASS   | Dust accumulates linearly, bounded    |

**Input ranges**:

- `pending`: [1, 10^15] (1 wei to 10^9 USDC)
- `splitA`: [1, MAX_SCALE-1] (all non-extreme split values)
- `cycles`: [1, 100]

## Invariant Tests

### FeeAccountingInvariantTest

| Invariant                           | Runs | Calls   | Reverts | Result   |
| ----------------------------------- | ---- | ------- | ------- | -------- |
| `invariant_feesDispatchedLeAccrued` | 256  | 128,000 | ~32,000 | **PASS** |
| `invariant_pendingFeeBacked`        | 256  | 128,000 | ~32,000 | **PASS** |

**Handler actions**: deposit, dispatch, collectReward
**Ghost variables**: totalDepositFeesAccrued, totalFeesDispatched, totalPrincipalDeposited

## Summary

- **Total tests**: 16
- **Passed**: 16
- **Failed**: 0
- **Fuzz runs**: 1,024 (4 fuzz tests × 256 runs)
- **Invariant runs**: 512 (2 invariants × 256 runs)
- **Handler calls**: ~128,000
