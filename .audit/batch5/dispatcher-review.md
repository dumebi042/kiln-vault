# Dispatcher Review

## State Keying
FeeDispatcher keys all state by `msg.sender`. Each vault's fees, recipients, and dispatch are isolated.

## Dispatch Flow
1. Vault calls `dispatchFees(asset, decimals)`
2. FeeDispatcher reads `_dispatches[vault]._pendingDepositFee` and `_pendingRewardFee`
3. Iterates recipients, computing each split
4. Calls `safeTransferFrom(vault, recipient, amount)` for each
5. Reduces pending by transferred amount

## Risks
- Reverting recipient blocks entire dispatch
- Pending state only updated after ALL transfers
- `safeTransferFrom` requires vault approval
- Split rounding leaves dust in pending
