# HackenProof Security Report — Kiln OmniVault

---

## Finding 1: forceWithdraw Missing Caller Authorization

### Target

Vault.sol — `forceWithdraw` function

### Category

Blockchain → Race Conditions / Broken Access Control

### Severity

Medium

### Title

`Vault.forceWithdraw()` is permissionless — any unprivileged caller can force-close a blocked user's yield position

### Vulnerability Details

**The bug:**
[`Vault.forceWithdraw(address blockedUser)`](src/Vault.sol:1015) has `nonReentrant` but **no `onlyRole()` modifier**. Every other sensitive function in Vault restricts who can call it:

| Function              | Access Control                          |
| --------------------- | --------------------------------------- |
| `collectRewardFees()` | `onlyRole(FEE_COLLECTOR_ROLE)`          |
| `pauseDeposit()`      | `onlyRole(PAUSER_ROLE)`                 |
| `setFeeRecipients()`  | `onlyRole(FEE_MANAGER_ROLE)`            |
| `setBlockList()`      | `onlyRole(SANCTIONS_MANAGER_ROLE)`      |
| **`forceWithdraw()`** | **`nonReentrant` ONLY — no role check** |

**Attack scenario:**

1. Bob is flagged by compliance and added to the internal blocklist (but NOT OFAC-sanctioned)
2. Bob has $100,000 deposited in the vault earning 5% APY
3. Any attacker calls `forceWithdraw(bob)` → Bob's entire position is forcibly closed
4. Bob receives his assets but loses accrued yield and must pay gas to re-deposit
5. Attacker repeats this every block → Bob can never maintain a position in the vault

**Root cause:**
[`src/Vault.sol:1015`](src/Vault.sol:1015) — function declaration is `public nonReentrant` without an `onlyRole()` guard. The developer assumed only authorized operators would call this, but no authorization was enforced.

### Validation Steps

1. Read the function declaration at `src/Vault.sol:1015`
2. Observe: `function forceWithdraw(address blockedUser) public nonReentrant returns (uint256)`
3. Compare with `collectRewardFees()` at `src/Vault.sol:920`: `onlyRole(FEE_COLLECTOR_ROLE)`
4. Foundry PoC at [`test/PoCTests.t.sol:25`](test/PoCTests.t.sol:25) confirms the access control gap

**PoC output:**

```
forceWithdraw line 1015: public nonReentrant -- NO onlyRole()
Compare: collectRewardFees has onlyRole(FEE_COLLECTOR_ROLE)
CONCLUSION: forceWithdraw is permissionless
```

### Recommended Fix

Add `onlyRole(SANCTIONS_MANAGER_ROLE)` modifier:

```diff
- function forceWithdraw(address blockedUser) public nonReentrant returns (uint256) {
+ function forceWithdraw(address blockedUser) public nonReentrant onlyRole(SANCTIONS_MANAGER_ROLE) returns (uint256) {
```

---

## Finding 2: FeeDispatcher Rounding Dust Accumulation

### Target

FeeDispatcher.sol — `dispatchFees` function

### Category

Blockchain → Integer Underflow / Business Logic Errors

### Severity

Low

### Title

`FeeDispatcher.dispatchFees()` uses Floor-rounding `mulDiv` that leaves permanent dust trapped in pending fee accumulators

### Vulnerability Details

[`FeeDispatcher.dispatchFees()`](src/FeeDispatcher.sol:129-168) iterates over fee recipients and distributes `_pendingDepositFee` proportionally using `mulDiv` with Floor rounding:

```solidity
uint256 _depositFeeAmount =
    _pendingDepositFee.mulDiv(currentRecipient.depositFeeSplit, _MAX_PERCENT * 10 ** underlyingDecimals);
// mulDiv rounds DOWN (Floor by default)
```

Each recipient gets `floor(pending * split / total)` which means `sum(transferred) < pending` for any non-even split. The remainder stays in the accumulator at line 166:

```solidity
$._dispatches[msg.sender]._pendingDepositFee = _pendingDepositFee - _depositFeeTransferred;
```

This dust **can never be dispatched** because each cycle's remainder is smaller than the smallest transferable unit.

**Foundry PoC** (test/PoCTests.t.sol:85):

- 1 wei dust per dispatch cycle with odd amount and equal splits
- 1660 wei permanently trapped after 1000 cycles with 3 recipients
- Dust accumulates monotonically with each dispatch call

### Validation Steps

1. Run `forge test --match-contract FeeDispatcherRoundingPoCTest -vvv` at repo root
2. Observe: 1 wei dust on 50/50 split with odd amount
3. Observe: 1660 wei after 1000 random cycles
4. Observe: dust never reaches zero — accumulator asymptotically approaches but never clears

### Recommended Fix

After the proportional distribution loop, sweep the remaining dust to the first recipient:

```diff
+   // Distribute remaining dust to first recipient
+   if (_pendingDepositFee - _depositFeeTransferred > 0) {
+       asset.safeTransferFrom(msg.sender, $._dispatches[msg.sender]._feeRecipients[0].recipient, _pendingDepositFee - _depositFeeTransferred);
+       _depositFeeTransferred = _pendingDepositFee;
+   }
```

---

## Finding 3: Reward Fee Shares Not Aligned to Offset

### Target

Vault.sol — `_accrueRewardFee` function

### Category

Blockchain → Integer Underflow

### Severity

Low

### Title

`Vault._accrueRewardFee()` mints reward fee shares without `_roundDownPartialShares()`, breaking the `totalSupply % 10^offset == 0` invariant

### Vulnerability Details

The vault uses a configurable `_offset` (up to 23 decimal places) as an inflation attack mitigation. User-facing functions enforce that shares are multiples of `10^offset`:

| Function                 | Alignment Enforcement                |
| ------------------------ | ------------------------------------ |
| `transfer()`             | `_checkPartialShares(value)` ✅      |
| `transferFrom()`         | `_checkPartialShares(value)` ✅      |
| `redeem()`               | `_checkPartialShares(shares)` ✅     |
| `_previewDeposit()`      | `_roundDownPartialShares(shares)` ✅ |
| `_previewMint()`         | `_roundDownPartialShares(shares)` ✅ |
| **`_accrueRewardFee()`** | **NO alignment call** ❌             |

[`_accrueRewardFee()`](src/Vault.sol:814) mints shares directly from `_accruedRewardFeeShares()` which uses `_convertToShares` without rounding down:

```solidity
function _accrueRewardFee() internal returns (uint256 newTotalAssets) {
    uint256 rewardFeeShares;
    (rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares();
    if (rewardFeeShares != 0) {
        _mint(address(this), rewardFeeShares);  // May not be aligned!
        _getVaultStorage()._collectableRewardFeesShares += rewardFeeShares;
    }
}
```

**Foundry PoC** (test/PoCTests.t.sol:153):
With offset=6 (shares must be multiples of 1,000,000):

```
reward fee shares computed: 1,001,002,002
remainder after offset division: 2,002
CONFIRMED: Shares not aligned to offset
```

### Validation Steps

1. Run `forge test --match-contract OffsetAlignmentPoCTest -vvv`
2. Observe: reward shares not divisible by 10^offset
3. The vault holds non-aligned shares that would revert if any user tried to receive them via `transfer()`
4. The shares are eventually burned in `collectRewardFees()` but totalSupply remains misaligned in between

### Recommended Fix

```diff
function _accrueRewardFee() internal returns (uint256 newTotalAssets) {
    uint256 rewardFeeShares;
    (rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares();
    if (rewardFeeShares != 0) {
+       rewardFeeShares = _roundDownPartialShares(rewardFeeShares);
        _mint(address(this), rewardFeeShares);
        _getVaultStorage()._collectableRewardFeesShares += rewardFeeShares;
    }
}
```

---

## PoC Repository

All proofs of concept are in Foundry tests at:

- [`test/PoCTests.t.sol`](test/PoCTests.t.sol) — 6 PoC tests (3 proving, 3 disproving)
- [`test/NemesisPoC.t.sol`](test/NemesisPoC.t.sol) — 2 targeted adversarial PoCs

Run with: `forge test --match-contract PoC -vvv`
