# Batch 3 — ERC4626 Accounting Model

**Commit audited**: `74170e72ae3a07148b1684dedc942e82705caf15`

---

## 1. Core Variables

| Variable                       | Type      | Source                                      | Description                                 |
| ------------------------------ | --------- | ------------------------------------------- | ------------------------------------------- |
| `totalAssets()`                | `uint256` | `connector.totalAssets(asset)`              | Platform-reported value of all vault assets |
| `totalSupply()`                | `uint256` | ERC20 `_totalSupply`                        | Total share supply                          |
| `_offset`                      | `uint8`   | `VaultStorage._offset`                      | Decimal offset for virtual shares (0–23)    |
| `_lastTotalAssets`             | `uint256` | `VaultStorage._lastTotalAssets`             | Snapshot for reward fee computation         |
| `_minTotalSupply`              | `uint256` | `VaultStorage._minTotalSupply`              | Minimum share supply after deposit          |
| `_depositFee`                  | `uint256` | `VaultStorage._depositFee`                  | Fee per deposit (scaled to asset decimals)  |
| `_rewardFee`                   | `uint256` | `VaultStorage._rewardFee`                   | Fee on yield (scaled to asset decimals)     |
| `_collectableRewardFeesShares` | `uint256` | `VaultStorage._collectableRewardFeesShares` | Accumulated reward fee shares               |
| `balanceOf(user)`              | `uint256` | ERC20 `_balances`                           | User's share balance                        |
| `_underlyingDecimals()`        | `uint8`   | `IERC20Metadata(asset()).decimals()`        | Asset decimals                              |

---

## 2. Conversion Formulas (Overridden by Vault)

### 2.1 `_convertToShares` (Vault override at L789)

```solidity
function _convertToShares(uint256 assets, Math.Rounding rounding, uint256 total, uint256 supply)
    internal view returns (uint256)
{
    return assets.mulDiv(supply + 10 ** _decimalsOffset(), total + 1, rounding);
}
```

**Formula**: `shares = assets * (supply + 10^offset) / (total + 1)`

Virtual supply offset: `10^offset` (when offset=6, virtual supply = 1,000,000 shares)
Virtual assets: `total + 1` (always 1 wei of virtual assets)

### 2.2 `_convertToAssets` (Vault override at L799)

```solidity
function _convertToAssets(uint256 shares, Math.Rounding rounding, uint256 total, uint256 supply)
    internal view returns (uint256)
{
    return shares.mulDiv(total + 1, supply + 10 ** _decimalsOffset(), rounding);
}
```

**Formula**: `assets = shares * (total + 1) / (supply + 10^offset)`

### 2.3 OZ Default (not used by Vault — shown for reference)

The inherited OZ `_convertToShares(assets, rounding)` calls `totalAssets()` and `totalSupply()` internally. The Vault **overrides** all conversion functions to pass explicit values.

---

## 3. Operation Formulas

### 3.1 `deposit(assets, receiver)` — Vault L507

```
1. maxAssets = _maxDeposit() = connector.maxDeposit(asset)
2. Revert if assets > maxAssets
3. newTotalAssets = _accrueRewardFee()
4. (shares, depositFeeAmount) = _previewDeposit(assets, newTotalAssets, totalSupply())
5. Revert if shares == 0
6. _deposit(caller, receiver, assets, shares, depositFeeAmount)
```

**`_previewDeposit`** (L729):

```
depositFeeAmount = assets * _depositFee / (100 * 10^underlyingDecimals)
netAssets = assets - depositFeeAmount
shares = _roundDownPartialShares(_convertToShares(netAssets, Floor, newTotalAssets, supply))
```

**`_deposit`** (internal, L624):

```
balanceBefore = asset.balanceOf(vault)
safeTransferFrom(caller, vault, assets)
_mint(receiver, shares)
Check: totalSupply >= _minTotalSupply
connector.delegatecall(deposit(asset, balanceOf(vault) - balanceBefore - depositFeeAmount))
_lastTotalAssets = totalAssets()
feeDispatcher.incrementPendingDepositFee(depositFeeAmount)
Emit Deposit(caller, receiver, assets, shares)
```

### 3.2 `mint(shares, receiver)` — Vault L532

```
1. Revert if shares == 0
2. _checkPartialShares(shares) — revert if shares % 10^offset != 0
3. newTotalAssets = _accrueRewardFee()
4. newTotalSupply = totalSupply()
5. maxShares = _maxMint(newTotalAssets, newTotalSupply)
6. Revert if shares > maxShares
7. (assets, depositFeeAmount) = _previewMint(shares, newTotalAssets, newTotalSupply)
8. Revert if assets == 0
9. _deposit(caller, receiver, assets, shares, depositFeeAmount)
```

**`_previewMint`** (L754):

```
rawAssetValue = _convertToAssets(shares, Ceil, newTotalAssets, supply)
scaledRawAssetValue = rawAssetValue * 10^underlyingDecimals
adjustedMaxPercent = (100 * 10^underlyingDecimals) - _depositFee
assets = scaledRawAssetValue * 100 / adjustedMaxPercent       [Ceil rounding]
depositFeeAmount = assets * _depositFee / (100 * 10^underlyingDecimals) [Floor]
```

### 3.3 `withdraw(assets, receiver, owner)` — Vault L559

```
1. Revert if assets == 0
2. maxAssets = _maxWithdraw(owner)
3. Revert if assets > maxAssets
4. shares = _convertToShares(assets, Ceil, _accrueRewardFee(), totalSupply())
5. Revert if shares == 0
6. shares = _roundDownPartialShares(shares)
7. _withdraw(caller, receiver, owner, assets, shares)
```

**`_withdraw`** (internal, L656):

```
if caller != owner: _spendAllowance(owner, caller, shares)
_burn(owner, shares)
balanceBefore = asset.balanceOf(vault)
connector.delegatecall(withdraw(asset, assets))
safeTransfer(vault, receiver, balanceOf(vault) - balanceBefore)
_lastTotalAssets = totalAssets()
Emit Withdraw(caller, receiver, owner, assets, shares)
```

### 3.4 `redeem(shares, receiver, owner)` — Vault L583

```
1. Revert if shares == 0
2. _checkPartialShares(shares)
3. newTotalAssets = _accrueRewardFee()
4. newTotalSupply = totalSupply()
5. maxShares = _maxRedeem(owner, newTotalAssets, newTotalSupply)
6. Revert if shares > maxShares
7. assets = _convertToAssets(shares, Floor, newTotalAssets, newTotalSupply)
8. Revert if assets == 0
9. _withdraw(caller, receiver, owner, assets, shares)
```

---

## 4. Preview Functions

### 4.1 `previewDeposit(assets)` — Vault L473

```
(rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares()
shares = _previewDeposit(assets, newTotalAssets, totalSupply() + rewardFeeShares)
Return shares
```

**IMPORTANT**: Preview includes reward fee shares in `supply` but does NOT include deposit fee in the result (deposit fee is deducted in `_previewDeposit` via netAssets).

### 4.2 `previewMint(shares)` — Vault L480

```
(rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares()
assets = _previewMint(shares, newTotalAssets, totalSupply() + rewardFeeShares)
Return assets
```

### 4.3 `previewWithdraw(assets)` — Vault L487

```
(rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares()
shares = _roundDownPartialShares(
    assets * (totalSupply() + rewardFeeShares + 10^offset) / (newTotalAssets + 1)  [Ceil]
)
Return shares
```

### 4.4 `previewRedeem(shares)` — Vault L498

```
(rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares()
assets = shares * (newTotalAssets + 1) / (totalSupply() + rewardFeeShares + 10^offset)  [Floor]
Return assets
```

---

## 5. Fee Accounting

### 5.1 Deposit Fee

```
depositFeeAmount = assets * _depositFee / (100 * 10^underlyingDecimals)
```

- Applied IN the preview (deducted from assets before share conversion)
- Does NOT go to the vault — goes to pending deposit fees in FeeDispatcher
- Max value: `_MAX_FEE * 10^underlyingDecimals` = 35 \* 10^decimal
- The fee is in asset terms, not share terms

### 5.2 Reward Fee (Yield Fee)

**`_accruedRewardFeeShares()`** — L827:

```
newTotalAssets = totalAssets()
(_, reward) = newTotalAssets.trySub(_lastTotalAssets)   // saturating subtraction
if reward > 0 && _rewardFee > 0:
    rewardFeeAmount = reward * _rewardFee / (100 * 10^underlyingDecimals)  [Floor]
    rewardFeeShares = _convertToShares(rewardFeeAmount, Floor, newTotalAssets - rewardFeeAmount, totalSupply())
```

**`_accrueRewardFee()`** — L814:

```
(rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares()
if rewardFeeShares > 0:
    _mint(address(this), rewardFeeShares)
    _collectableRewardFeesShares += rewardFeeShares
```

Key property: reward fee shares are minted to `address(this)` (the vault itself), not burned or sent to recipients. They sit in the vault's balance as `_collectableRewardFeesShares` until `collectRewardFees()` is called.

---

## 6. Max Operation Formulas

### 6.1 `maxDeposit(address)` — Vault L437

```
if connector.paused(name) || _depositPaused: return 0
return _maxDeposit() = connector.maxDeposit(asset)
```

### 6.2 `maxMint(address)` — Vault L446

```
if connector.paused(name) || _depositPaused: return 0
return _maxMint(totalAssets(), totalSupply())
     = if maxDeposit == type(uint256).max: type(uint256).max
       else: _convertToShares(maxDeposit, Floor, totalAssets(), totalSupply())
```

### 6.3 `maxWithdraw(address owner)` — Vault L455

```
if connector.paused(name): return 0
return min(connector.maxWithdraw(asset), previewRedeem(balanceOf(owner)))
```

### 6.4 `maxRedeem(address owner)` — Vault L464

```
if connector.paused(name): return 0
return _maxRedeem(owner, totalAssets(), totalSupply())
     = if connector.maxWithdraw == type(uint256).max: balanceOf(owner)
       else: min(_convertToShares(connector.maxWithdraw, Floor, totalAssets(), totalSupply()), balanceOf(owner))
```

---

## 7. Rounding Direction Summary

| Operation         | Conversion      | Rounding                   | Direction           | Safe Side                         |
| ----------------- | --------------- | -------------------------- | ------------------- | --------------------------------- |
| `deposit`         | assets → shares | `Floor`                    | Shares rounded DOWN | Protocol (user gets fewer shares) |
| `mint`            | shares → assets | `Ceil` (in `_previewMint`) | Assets rounded UP   | Protocol (user pays more assets)  |
| `withdraw`        | assets → shares | `Ceil`                     | Shares rounded UP   | Protocol (user burns more shares) |
| `redeem`          | shares → assets | `Floor`                    | Assets rounded DOWN | Protocol (user gets fewer assets) |
| `previewDeposit`  | assets → shares | `Floor`                    | Same as execution   | —                                 |
| `previewMint`     | shares → assets | `Ceil`                     | Same as execution   | —                                 |
| `previewWithdraw` | assets → shares | `Ceil`                     | Same as execution   | —                                 |
| `previewRedeem`   | shares → assets | `Floor`                    | Same as execution   | —                                 |
| reward fee        | assets → shares | `Floor`                    | Lower fee shares    | Protocol (lower fee)              |
| deposit fee       | assets → amount | `Floor`                    | Lower fee amount    | User (lower fee)                  |

All rounding favors the protocol/vault, not the user. This is standard ERC4626.

---

## 8. Virtual Assets and Shares Analysis

### 8.1 The Virtual Model

The OZ v5 implementation uses virtual assets and shares to mitigate the donation/inflation attack:

```
_conversion denominator = supply + 10^offset       (virtual supply offset)
_conversion numerator   = total + 1                (virtual assets)
```

When `supply = 0` and `total = 0`:

- Effective supply = `0 + 10^offset` = `10^offset` virtual shares
- Effective total = `0 + 1` = 1 virtual wei
- Exchange rate: 1 virtual wei = 10^offset virtual shares
- On first deposit of `A` assets: shares = `A * 10^offset / 1` = `A * 10^offset`

### 8.2 Offset Effect on First Deposit

For a 6-decimal token with offset=6:

- Virtual shares: 1,000,000
- First depositor deposits 100,000 USDC (100,000,000,000 units)
- Shares minted: 100,000,000,000 _ (0 + 1,000,000) / (0 + 1) = 100,000,000,000 _ 1,000,000 / 1

Wait, that's wrong. Let me recalculate:

`_convertToShares(100_000e6, Floor, 100_000e6, 0)`:
= 100,000e6 _ (0 + 10^6) / (100,000e6 + 1)
= 100,000,000,000 _ 1,000,000 / 100,000,000,001
≈ 999,999.99... → Floor → 999,999

So first depositor gets 999,999 shares for 100,000,000,000 units of a 6-decimal asset.

Exchange rate after first deposit:

- totalAssets = 100,000,000,000 (in connector), totalSupply = 999,999
- 1 share ≈ 100,000.1 units ≈ 0.1000001 USDC (very low price due to offset)

### 8.3 Donation Attack with Offset

Without offset (offset=0): virtual supply = 1, donation of D assets makes first depositor lose ~D/(A+D) of their shares.

With offset=6: virtual supply = 1,000,000. A donation of D changes the rate from:

- Before: rate = S / (A + 1) ≈ S/A
- After donation: total = A + D, supply unchanged
- New depositor gets: shares = deposit \* (S + 1M) / (A + D + 1)

The offset makes the donation attack much more expensive because the attacker must donate enough to meaningfully inflate the rate relative to 1M virtual shares.

---

## 9. Partial Share Mechanism

### 9.1 `_checkPartialShares(shares)`

```solidity
if (_offset > 0) {
    if (shares % 10 ** _offset > 0) revert RemainderNotZero(shares);
}
```

When offset > 0, shares must be multiples of `10^offset`. This is checked in:

- `mint()` — the requested shares must be aligned
- `redeem()` — the requested shares must be aligned
- `transfer()` — the amount must be aligned
- `transferFrom()` — the amount must be aligned

**NOT** checked in:

- `deposit()` — shares are computed and rounded down, so they're always aligned
- `withdraw()` — shares are computed and rounded down
- `forceWithdraw()` — burns ALL shares (including remainder)

### 9.2 `_roundDownPartialShares(shares)`

```solidity
if (_offset > 0) {
    shares -= shares % 10 ** _offset;
}
return shares;
```

Used in `deposit()` and `withdraw()` to ensure minted/burned shares are aligned. The remainder stays with the user (it's already been accounted for in the share price).

**Important implication**: When offset > 0, a user with shares that are NOT multiples of `10^offset` cannot transfer or redeem those shares. Only `forceWithdraw()` can handle them (by withdrawing everything).

---

## 10. State Changes Per Operation

### 10.1 deposit(assets, receiver)

| Variable                    | Before | After                                            |
| --------------------------- | ------ | ------------------------------------------------ |
| caller's asset balance      | A      | A - assets                                       |
| vault's asset balance       | B      | B + assets - depositFee (then sent to connector) |
| vault's managed (connector) | M      | M + (assets - depositFee)                        |
| receiver's share balance    | S      | S + shares                                       |
| totalSupply                 | TS     | TS + shares                                      |
| \_lastTotalAssets           | LTA    | totalAssets()                                    |
| pendingDepositFee           | PDF    | PDF + depositFeeAmount                           |

### 10.2 redeem(shares, receiver, owner)

| Variable                    | Before | After                                   |
| --------------------------- | ------ | --------------------------------------- |
| owner's share balance       | S      | S - shares                              |
| vault's managed (connector) | M      | M - withdrawAmount                      |
| vault's asset balance       | B      | B + withdrawAmount - transferToReceiver |
| receiver's asset balance    | R      | R + receivedAmount                      |
| totalSupply                 | TS     | TS - shares                             |
| \_lastTotalAssets           | LTA    | totalAssets()                           |

### 10.3 Reward Fee Accrual

| Variable                      | Before | After                                |
| ----------------------------- | ------ | ------------------------------------ |
| totalSupply                   | TS     | TS + rewardFeeShares                 |
| vault share balance           | 0      | rewardFeeShares                      |
| \_collectableRewardFeesShares | CR     | CR + rewardFeeShares                 |
| \_lastTotalAssets             | LTA    | newTotalAssets (current totalAssets) |

---

## 11. Fee Conservation

### Deposit Fee Path

```
deposit(assets, receiver)
  → depositFeeAmount = assets * fee / maxScale
  → netAssets = assets - depositFeeAmount  → converted to shares
  → depositFeeAmount stays in vault balance (sent to vault, not to connector)
  → feeDispatcher.incrementPendingDepositFee(depositFeeAmount)
```

The deposit fee is:

1. Received by the vault as part of the asset transfer
2. NOT sent to the connector (stays idle in vault)
3. Tracked as a pending liability in FeeDispatcher
4. Dispatched to recipients via `dispatchFees()`

### Reward Fee Path

```
_accrueRewardFee()
  → reward = totalAssets() - _lastTotalAssets   [saturating]
  → rewardFeeAmount = reward * fee / maxScale   [Floor]
  → rewardFeeShares = convertToShares(rewardFeeAmount)
  → _mint(vault, rewardFeeShares)   → dilutes other shareholders
  → _collectableRewardFeesShares += rewardFeeShares
```

The reward fee is:

1. Computed from the INCREASE in totalAssets since last snapshot
2. Represented as SHARES, not assets
3. Minted to the vault itself (diluting all shareholders proportionally)
4. Later, `collectRewardFees()` converts those shares to assets via connector.withdraw
5. Those assets become pending reward fees in FeeDispatcher
6. Dispatched to recipients via `dispatchFees()`

---

## 12. Accounting Invariants

From the code analysis, these invariants should hold:

1. **Solvency**: `totalAssets() >= sum(balanceOf(user) for all users)` up to rounding
2. **Share price monotonicity**: between state changes, `previewRedeem(shares)` does not increase
3. **Deposit integrity**: shares minted ≤ maximum based on actual assets received
4. **Withdraw integrity**: assets withdrawn ≤ maximum based on actual shares burned
5. **Fee non-double-counting**: reward fees are only charged on the delta between `totalAssets()` and `_lastTotalAssets`
6. **Round-trip**: deposit(redeem(balance)) or redeem(deposit(assets)) cannot increase user balance
7. **Supply minimum**: after any deposit, `totalSupply >= _minTotalSupply`
8. **No free shares**: cannot mint shares without transferring assets
9. **No free assets**: cannot withdraw assets without burning shares
10. **Offset alignment**: shares involved in transfers/mint/redeem are multiples of `10^offset`
