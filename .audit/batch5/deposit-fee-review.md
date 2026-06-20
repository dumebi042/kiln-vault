# Deposit Fee Review

## Calculation

`depositFeeAmount = assets * _depositFee / (100 * 10^decimals) [Floor]`

## Lifecycle

1. User deposits A assets
2. Fee = A \* fee% [Floor], stays idle in vault
3. Net = A - fee → converted to shares → invested via connector
4. `feeDispatcher.incrementPendingDepositFee(fee)` tracks liability
5. Dispatch: FeeDispatcher pulls fee from vault to recipients via `safeTransferFrom`

## Protection

`maxRedeem()` limits shareholder withdrawal to connector-accessible assets. The idle fee balance is excluded from `connector.maxWithdraw()`. Verified by test.
