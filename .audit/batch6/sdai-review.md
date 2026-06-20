# sDAI/SUSDS/Angle Savings Connector Reviews

## sDAI Connector

Immutable: `sDAI` (ERC4626 vault). Deposit: `sDAI.deposit(amount, vault)`. Withdraw: `sDAI.withdraw(amount, vault, vault)`. totalAssets: `sDAI.previewRedeem(sDAI.balanceOf(vault))`. All ERC4626 standard.

**Risk**: DSR rate changes between preview and execution. Vault's balance-delta handles this. sDAI `withdraw()` guarantees exact DAI output.

## sUSDS Connector

Identical to sDAI. Immutable: `sUSDS` (ERC4626 vault).

**Risk**: Sky protocol migration (DAI→USDS) may affect sUSDS contract address. The immutable binding prevents automatic migration.

## Angle Saving Connector

Immutable: `stakingVault` (IPausableERC4626). Constructor validates `totalAssets() > 0`. Withdraw: `stakingVault.withdraw(amount, vault, vault)`. Pause check in `maxDeposit`/`maxWithdraw`.
