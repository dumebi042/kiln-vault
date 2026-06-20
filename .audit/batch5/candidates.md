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

## B5-005: Pending fee solvency after shareholder exit (Resolved)

**Classification**: EXPECTED BEHAVIOR

### Numerical Proof

Test `test_shareholderExitsAfterDepositFee`:

- Alice deposits 100k with 10% deposit fee
- 10k fee idle, 90k invested through connector
- `maxRedeem(Alice)` returns ~81k (limited by connector's `maxWithdraw` of 90k)
- Alice's actual share balance is ~90k (in share terms)
- `assertLt(maxRedeem, shares, ...)` PASSES — Alice CANNOT fully exit
- Total supply remains > 0 — fee cannot be stranded without a shareholder

**The contradiction is resolved**: Shareholders cannot fully exit while pending fees remain because `maxRedeem()` is limited by the connector's `maxWithdraw()`, which excludes idle fee assets. The fee assets are always backed by idle balance equal to or greater than the pending liability.

### When can fees become undercollateralized?

Only if:

1. A connector reports more `maxWithdraw()` than actual recoverable assets, AND
2. Shareholders withdraw those over-reported assets, consuming the idle fee backing

This requires a malfunctioning connector (admin power scenario).

## B5-006: Fee dispatch requires vault approval

The FeeDispatcher uses `safeTransferFrom(vault, recipient, amount)` during dispatch. The vault must have approved the FeeDispatcher for the asset. This approval is set during vault initialization (`forceApprove(feeDispatcher, type(uint256).max)`) and persists indefinitely.

**Classification**: EXPECTED BEHAVIOR.

## B5-007: Recipient split rounding dust

When multiple recipients exist, `_pendingDepositFee * split_i / maxScale [Floor]` for each recipient may leave a remainder. This remainder stays as pending balance in the FeeDispatcher, accumulating until the next dispatch. The dust is bounded by `number_of_recipients * maxScale` and is always returned to future dispatches.

**Classification**: EXPECTED BEHAVIOR.
