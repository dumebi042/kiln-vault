# Batch 4 — Fuzz and Invariant Test Results

## Fuzz Tests

### Test: `testFuzz_shortWithdrawal` (conceptual — requires non-state connector mock)

Due to the delegatecall storage collision issue (connector state variables map to vault storage), fuzz testing of short-withdrawal behavior requires connector implementations with fixed behaviors (no mutable state). The fixed-behavior connectors in `VaultWithdrawalDelta.t.sol` prove the vulnerability numerically.

**Fuzz dimensions tested manually:**

- Amounts: 1 to 10^15 range
- Short ratios: 50%, 0%, 100%
- Multiple users: 2
- Withdrawal order: Alice first, Bob second

## Invariant Tests

### Short-Withdrawal Invariant

For any withdrawal where the connector returns less than requested:

```
sharesBurned > 0
assetsDelivered < assetsRequested
valueTransferredToRemainingHolders = assetsRequested - assetsDelivered
```

This invariant is violated when a connector returns less than requested (B4-002).

### Deposit Invariant

For any deposit where the connector receives less than sent:

```
assetsInvested ≤ assetsReceived
idleBalance ≥ 0
sharesMinted = f(assetsReceived - fees)
```

This invariant holds for all tested scenarios.

## Coverage Summary

| Area                    | Tested                     | Result               |
| ----------------------- | -------------------------- | -------------------- |
| Normal deposit/withdraw | Yes (VaultAssetFlow)       | PASS                 |
| Fee isolation           | Yes                        | PASS                 |
| Connector limits        | Yes                        | PASS                 |
| Registry transitions    | Yes                        | PASS                 |
| Short withdrawal (50%)  | Yes (VaultWithdrawalDelta) | PROVEN VULNERABILITY |
| Short withdrawal (0%)   | Yes                        | PROVEN VULNERABILITY |
| Exact withdrawal        | Yes                        | PASS                 |
