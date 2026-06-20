# Fee Migration Review

## Storage Compatibility

Old (`FeeDispatcher_1_0_0`) and new (`FeeDispatcher`) use the same ERC-7201 storage slot:
`0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300`

## Migration Path

1. `VaultFactory.upgradeVault()` reads old storage via `delegateToFactory`
2. Old `FeeDispatcherStorage {_pendingManagementFee, _pendingPerformanceFee, _feeRecipients[]}` is read
3. Values are mapped to new `Dispatch {_pendingDepositFee, _pendingRewardFee, _feeRecipients[]}`
4. Vault.upgrade() initializes new FeeDispatcher with migrated values
5. New FeeDispatcher stores as `_dispatches[vault]`

## Key Properties

- Same storage slot → no data loss
- Values are read-once, never duplicated
- Repeated upgrade calls revert (reinitializer(2) consumed)
- No allowance drain path (old FeeDispatcher used internal transfers, not approvals)
