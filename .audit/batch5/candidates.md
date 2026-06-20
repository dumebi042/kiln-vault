# Batch 5 — Fee Accounting Candidates

## Summary

| ID     | Title                                                   | Classification           |
| ------ | ------------------------------------------------------- | ------------------------ |
| B5-001 | Deposit fee assets isolated from shareholder withdrawal | **EXPECTED BEHAVIOR**    |
| B5-002 | Reward fee checkpoint prevents double-charge            | **EXPECTED BEHAVIOR**    |
| B5-003 | FeeDispatcher multi-vault isolation by msg.sender       | **EXPECTED BEHAVIOR**    |
| B5-004 | Deposit fee round-trip dust accumulation                | **FALSE POSITIVE**       |
| B5-005 | Pending fee dispatch after shareholder exit             | **EXPECTED ADMIN POWER** |

## B5-001: Deposit fee assets isolated from shareholder withdrawal

`maxRedeem()` limits shareholder withdrawal to connector-accessible assets. The idle fee balance is not accessible via `maxWithdraw()`. Verified by test: Alice's maxRedeem < her share balance.

**Classification**: EXPECTED BEHAVIOR.

## B5-002: Reward fee checkpoint prevents double-charge

`_lastTotalAssets` is updated after each reward fee accrual. Subsequent accrual calls with no new yield produce zero fee shares. Verified by test: reward shares unchanged after second accrual.

**Classification**: EXPECTED BEHAVIOR.

## B5-003: FeeDispatcher multi-vault isolation by msg.sender

FeeDispatcher keys all state by `msg.sender`. Each vault's pending fees, recipients, and dispatch state are cryptographically isolated. An EOA or another vault cannot read or modify another vault's fee state.

**Classification**: EXPECTED BEHAVIOR.

## B5-004: Deposit fee round-trip dust accumulation

Floor rounding in deposit fee calculation (`fee = amount * fee / maxScale [Floor]`) means each micro-deposit loses less than 1 unit to rounding. Over many micro-deposits, the cumulative rounding is bounded and always favors the user (lower fee).

**Classification**: FALSE POSITIVE.

## B5-005: Pending fee dispatch after shareholder exit

If all shareholders exit, pending fees remain as liabilities in the FeeDispatcher with no idle balance. The FeeDispatcher uses `safeTransferFrom(vault, recipient, amount)` to dispatch, which pulls from the vault's balance. If the vault has no assets, dispatch reverts. Only an admin restoring liquidity (or the connector returning assets via collectRewardFees) can fix this.

**Classification**: EXPECTED ADMIN POWER.
