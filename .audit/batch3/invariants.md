# Batch 3 — ERC4626 Accounting Invariants

---

## Formal Invariant Definitions

### I-1: Solvency

```
totalAssets() >= sum of all user share values at the current exchange rate
```

**Test**: After every operation, the recoverable assets (via connector) must be sufficient to cover all outstanding shares (excluding the vault's own fee shares).

### I-2: No Free Shares

```
deposit(assets, receiver) → receiver.balanceOf increases by ≤ maxShares(assets)
mint(shares, receiver) → assetsTransferred from caller ≥ minAssets(shares)
```

**Test**: A user cannot increase their share balance without transferring at least the corresponding net asset amount.

### I-3: No Free Assets

```
redeem(shares, receiver, owner) → receiver gets ≤ assets = convertToAssets(shares, Floor)
withdraw(assets, receiver, owner) → sharesBurned ≥ convertToShares(assets, Ceil)
```

**Test**: A user cannot receive assets without burning at least the corresponding shares.

### I-4: Round-Trip Conservation

```
deposit(A, user) → redeem(balanceOf(user), user, user) → finalBalanceOf(user) = initialBalanceOf(user) - fees
```

**Test**: In the absence of yield and fees, a deposit followed by immediate full redemption cannot increase the user's balance.

### I-5: Fee Non-Double-Counting

```
_accrueRewardFee() called N times consecutively without yield produces the same state as calling it once
```

**Test**: Reward fees are only computed on the delta between `totalAssets()` and `_lastTotalAssets`. Calling `_accrueRewardFee()` repeatedly without yield changes does not produce additional fees.

### I-6: Preview Consistency

```
deposit(assets).shares ≈ previewDeposit(assets)
mint(shares).assets ≈ previewMint(shares)
withdraw(assets).shares ≈ previewWithdraw(assets)
redeem(shares).assets ≈ previewRedeem(shares)
```

**Test**: The difference between preview and execution is bounded by one unit of rounding plus any state changes between the preview and execution.

### I-7: Minimum Supply Enforced

```
deposit(...) → totalSupply >= _minTotalSupply OR revert
```

**Test**: After any deposit, if totalSupply < \_minTotalSupply, the transaction reverts.

### I-8: Partial Share Integrity

```
transfer(shares) → shares % 10^offset == 0 OR revert
mint(shares) → shares % 10^offset == 0 OR revert
redeem(shares) → shares % 10^offset == 0 OR revert
```

**Test**: Transfers and voluntary redemptions only allow offset-aligned share amounts.

### I-9: Deposit Fee Isolation

```
deposit(assets) → depositFeeAmount ≤ assets * maxFee / maxScale
depositFeeAmount is NOT deposited into the connector
```

**Test**: The deposit fee is deducted from the deposited amount before the connector deposit call, and is tracked as a pending fee liability.

### I-10: Reward Fee on Yield Only

```
totalAssets() <= _lastTotalAssets → no reward fee minted
```

**Test**: When total assets have not increased, no reward fee shares are minted.

### I-11: Supply-Dependent Share Price

```
totalSupply >= _minTotalSupply → all operations permitted
totalSupply < _minTotalSupply → deposits blocked, withdrawals still allowed
```

**Test**: The minimum supply check only applies to deposit operations, not withdrawals.

### I-12: First-Depositor Protection (Offset)

```
First deposit of A assets → shares minted >= A * 10^offset / (A + 1)
Donation of D assets after first deposit → attacker cannot extract more than D from subsequent depositors
```

**Test**: The virtual shares offset prevents inflation attacks by requiring the attacker to over-collateralize the donation.
