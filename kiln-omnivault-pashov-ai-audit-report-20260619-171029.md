# 🔐 Security Review — Kiln OmniVault

---

## Scope

|                                  |                                                        |
| -------------------------------- | ------------------------------------------------------ |
| **Mode**                         | default                                                |
| **Files reviewed**               | `Vault.sol` · `VaultFactory.sol`<br>`FeeDispatcher.sol` · `ConnectorRegistry.sol`<br>`ExternalAccessControl.sol` · `BlockList.sol`<br>`BlockListFactory.sol` · `AaveV3Connector.sol`<br>`CompoundV3Connector.sol` · `SDAIConnector.sol`<br>`MetamorphoConnector.sol` · `AngleSavingConnector.sol`<br>`SUSDSConnector.sol` · `MultisendLib.sol` |
| **Confidence threshold (1-100)** | 65                                                     |

---

## Findings

[65] **1. `Vault.forceWithdraw` is permissionless — any caller can force-close a blocked user's position**

`Vault.forceWithdraw` · Confidence: 65

**Description**
`forceWithdraw` has `nonReentrant` but no `onlyRole()` or caller authorization — any address can force-withdraw any internally-blocked (non-OFAC) user, burning their shares and closing their yield position at any time.

**Fix**

```diff
- function forceWithdraw(address blockedUser) public nonReentrant returns (uint256) {
+ function forceWithdraw(address blockedUser) public nonReentrant onlyRole(SANCTIONS_MANAGER_ROLE) returns (uint256) {
```

---

[65] **2. `FeeDispatcher.dispatchFees` rounding dust accumulates permanently in pending fee accumulators**

`FeeDispatcher.dispatchFees` · Confidence: 65

**Description**
Each `dispatchFees` call uses Floor-rounding `mulDiv` for each recipient, producing truncation dust that accumulates permanently in `_pendingDepositFee` and `_pendingRewardFee` without any sweep or dust-collection mechanism, potentially blocking accurate fee accounting over long timeframes.

**Fix**

```diff
+   // After distributing proportional amounts to all recipients,
+   // distribute remaining dust to the first recipient
+   if (_pendingDepositFee - _depositFeeTransferred > 0) {
+       asset.safeTransferFrom(msg.sender, $._dispatches[msg.sender]._feeRecipients[0].recipient, _pendingDepositFee - _depositFeeTransferred);
+   }
```

---

[65] **3. `Vault._accrueRewardFee` mints reward shares without offset alignment, breaking the share-rounding invariant**

`Vault._accrueRewardFee` · Confidence: 65

**Description**
Reward fee shares are minted via `_convertToShares` without `_roundDownPartialShares`, while all user-facing functions (`transfer`, `redeem`, `mint`) enforce alignment via `_checkPartialShares` — the vault itself holds unaligned reward shares that cannot be transferred to any user.

**Fix**

```diff
-   rewardFeeShares = _convertToShares(...);
+   rewardFeeShares = _roundDownPartialShares(_convertToShares(...));
```

---

## Leads

- **`FeeDispatcher.setFeeRecipients` redistributes pending fees under new split ratios** — `Vault.setFeeRecipients` — Code smells: pending fee layout erased, old recipients lose entitlement — When fee recipients are changed via `setFeeRecipients`, the pending fees accrued under the old recipient configuration are distributed using the new split ratios, effectively transferring the old recipients' unpaid fees to the new recipients.

- **`Vault._accruedRewardFeeShares` doesn't update `_lastTotalAssets` on value decrease, potentially double-feeing on recovery** — `Vault._accruedRewardFeeShares` — Code smells: `trySub` returns 0 on negative yield, high-water mark persists — When connector value drops, `trySub` silently returns 0 and `_lastTotalAssets` is never updated downward. If assets later recover to the previous high, the "recovery" is treated as new yield and reward fees are taken on it a second time.

- **`Vault._previewMint` intermediate overflow with extreme values** — `Vault._previewMint` — Code smells: `_rawAssetValue * 10**_decimals` before `mulDiv` — For unrealistically large share amounts or very-high-decimal tokens, the intermediate multiplication `_rawAssetValue * 10**_decimals` can overflow `uint256` before `mulDiv`'s internal division rescues it.

- **`ConnectorRegistry.update` bypasses pause while `remove` is blocked by pause** — `ConnectorRegistry.update/remove` — Code smells: asymmetric state machine — `update` requires `whenNotFrozen` (no pause check) while `remove` requires both `whenNotFrozen` AND `whenNotPaused`, creating an asymmetry where a paused connector can be replaced but not deleted.

- **`Vault._deposit` performs connector pause check after asset transfer and share mint** — `Vault._deposit` — Code smells: late-bound connector state check — If a connector is paused between `_maxDeposit()` (pre-check) and `getOrRevert()` (in `_deposit`), the transaction reverts after assets were transferred and shares minted — while atomicity prevents fund loss, this creates a gas-waste scenario.

---

> ⚠️ This review was performed by an AI assistant. AI analysis can never verify the complete absence of vulnerabilities and no guarantee of security is given. Team security reviews, bug bounty programs, and on-chain monitoring are strongly recommended. For a consultation regarding your projects' security, visit [https://www.pashov.com](https://www.pashov.com)

Findings List

| # | Confidence | Title |
|---|---|---|
| 1 | [65] | Vault.forceWithdraw is permissionless |
| 2 | [65] | FeeDispatcher.dispatchFees rounding dust accumulation |
| 3 | [65] | Vault._accrueRewardFee offset alignment |

---
