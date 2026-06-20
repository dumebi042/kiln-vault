# MetaMorpho Connector Review

## Immutable Dependencies

- `metamorpho`: External ERC4626 MetaMorpho vault

## Critical Analysis

| Area          | Verdict                                                                                                   |
| ------------- | --------------------------------------------------------------------------------------------------------- |
| Asset binding | Single immutable vault. No validation that caller's asset matches vault's asset.                          |
| Deposit       | `forceApprove(metamorpho, amount)` → `metamorpho.deposit(amount, vault)`. Correct.                        |
| Withdraw      | `metamorpho.withdraw(amount, vault, vault)`. **This may burn more shares than expected if rate changed.** |
| totalAssets   | `metamorpho.previewRedeem(metamorpho.balanceOf(vault))`. Double conversion. Correct.                      |
| maxDeposit    | Delegates to `metamorpho.maxDeposit(vault)`. Correct.                                                     |
| maxWithdraw   | Delegates to `metamorpho.maxWithdraw(vault)`. Correct — but may be stale.                                 |

## Key Risk: Asynchronous withdrawal

`metamorpho.withdraw(amount, vault, vault)` burns external vault shares to deliver `amount` of underlying. If the MetaMorpho vault's withdrawal queue has insufficient liquidity, it either reverts or delivers on a timelag. The Vault's balance-delta approach handles this safely.

## Key Risk: No asset validation

The connector does not verify that `asset` matches `metamorpho.asset()`. If called with wrong asset, deposit would approve wrong token. But since connectors are called via delegatecall from vault (which controls which asset to use), this is admin power.
