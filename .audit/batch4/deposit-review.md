# Batch 4 — Deposit Review

## Deposit Flow

```
deposit(assets, receiver)
  → _accrueRewardFee()                    [before any asset transfer]
  → _previewDeposit(assets, total, supply)  [compute shares & fee]
  → _deposit(caller, receiver, assets, shares, fee)
     → balanceBefore = asset.balanceOf(vault)
     → safeTransferFrom(caller, vault, assets)  [actual transfer]
     → _mint(receiver, shares)
     → check: totalSupply >= _minTotalSupply
     → connector.delegatecall(deposit(asset, balanceOf(vault) - balanceBefore - fee))
     → _lastTotalAssets = totalAssets()
     → feeDispatcher.incrementPendingDepositFee(fee)
```

## Key Observations

1. **safeTransferFrom before \_mint**: The asset transfer happens before shares are minted. If transferFrom fails, the tx reverts and no shares are minted. This prevents "free shares."

2. **Balance-delta deposit**: The connector receives `balanceOf(vault) - balanceBefore - fee`, which is the ACTUAL amount transferred (not the requested amount). This correctly handles fee-on-transfer tokens — only the net received amount is invested.

3. **Fee isolated**: The deposit fee stays in the vault as idle balance, tracked in FeeDispatcher.

4. **No reentrancy window**: `nonReentrant` protects the entire deposit flow. The external call (connector delegatecall) happens at the end, after all state changes.

## Edge Cases

| Scenario                | Handling                                          | Safe? |
| ----------------------- | ------------------------------------------------- | ----- |
| Standard ERC20 transfer | Exact amount                                      | Yes   |
| Fee-on-transfer         | Net amount invested, fee stays idle               | Yes   |
| Rebasing token          | Rebasing during transfer handled by balance-delta | Yes   |
| Connector consumes less | Remaining stays as idle vault balance             | Yes   |
| Connector reverts       | Entire tx reverts (shares unminted)               | Yes   |
| Zero transfer           | `amount == 0` reverts with `AmountZero`           | Yes   |
