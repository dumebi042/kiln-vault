# Batch 2 — Candidate Findings

---

## CANDIDATE-001: VaultUpgradeableBeacon.pauseFor can decrease pauseTimestamp via uint88 overflow

| Field              | Value                                                                                                      |
| ------------------ | ---------------------------------------------------------------------------------------------------------- |
| **Contracts**      | [`VaultUpgradeableBeacon.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/proxy/VaultUpgradeableBeacon.sol) |
| **Functions**      | [`pauseFor()`](src/proxy/VaultUpgradeableBeacon.sol:153)                                                   |
| **Classification** | **KNOWN ISSUE**                                                                                            |

### Root Cause

At [`VaultUpgradeableBeacon.sol:153-162`](src/proxy/VaultUpgradeableBeacon.sol:153):

```solidity
function pauseFor(uint256 duration) external onlyRole(PAUSER_ROLE) {
    if (duration == 0) revert AmountZero();
    uint256 _newPauseTimestamp = block.timestamp + duration;
    if (_newPauseTimestamp <= pauseTimestamp) {
        revert InvalidDuration(_newPauseTimestamp, pauseTimestamp);
    }
    pauseTimestamp = uint88(_newPauseTimestamp);  // <-- uint88 overflow
}
```

When `block.timestamp + duration > type(uint88).max` (~8.9e24 or ~2.8e17 years), the `uint88` cast wraps around to a small value, which can be less than the current `pauseTimestamp`. This allows a PAUSER to effectively unpause or decrease the pause duration.

### Prior Audit

**Spearbit/Cantina 5.1.1** (Medium Risk). Reported and acknowledged. Kiln's remediation: grant PAUSER_ROLE to a PauserProxy contract that performs the overflow check. The ConnectorRegistry was fixed (uses `SafeCast.toUint88()`).

### Current Status

The beacon contract is immutable (not upgradeable). The fix requires the PauserProxy approach. This is a known, acknowledged issue with a documented mitigation plan.

---

## CANDIDATE-002: Missing \_disableInitializers on Vault implementation

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Constructor**    | [`constructor()`](src/Vault.sol:304)                               |
| **Classification** | **KNOWN ISSUE** (Informational)                                    |

### Root Cause

The Vault constructor does not call `_disableInitializers()`:

```solidity
constructor(address externalAccessControl_, address vaultFactory_) {
    _externalAccessControl = IAccessControl(externalAccessControl_);
    vaultFactory = vaultFactory_;
}
```

### Prior Audit

**Spearbit 5.4.10** (Informational). Kiln acknowledged, arguing that `onlyFactory` modifier on `initialize()` and `upgrade()` prevents practical exploitation.

### Attack Path

A factory DEPLOYER_ROLE holder can call `VaultFactory.upgradeVault(Vault(IMPLEMENTATION_ADDRESS), ...)` → `impl.upgrade(upgradeParams)` → `onlyFactory` passes (factory is calling) → `reinitializer(2)` passes (`_initialized == 0 < 2`) → implementation is initialized.

**Impact**: The implementation contract storage becomes initialized but no proxy points to it. No user funds are affected. Nuisance only.

---

## CANDIDATE-003: Vault.\_self immutable declared but never used

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Line**           | [`line 115`](src/Vault.sol:115)                                    |
| **Classification** | **EXPECTED BEHAVIOR** (code quality)                               |

### Root Cause

```solidity
address internal immutable _self = address(this);
```

This immutable is declared but **never referenced anywhere** in `Vault.sol`. It consumes gas during construction but provides no functionality. It exists in the compiled bytecode but cannot be read.

---

## CANDIDATE-004: VaultFactory.upgradeVault can create duplicate array entries

| Field              | Value                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------- |
| **Contracts**      | [`VaultFactory.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/VaultFactory.sol)          |
| **Functions**      | [`upgradeVault()`](src/VaultFactory.sol:246), [`removeVault()`](src/VaultFactory.sol:224) |
| **Classification** | **EXPECTED ADMIN POWER**                                                                  |

### Root Cause

```solidity
function upgradeVault(Vault vault, ...) external onlyRole(DEPLOYER_ROLE) {
    // ...
    vault.upgrade(upgradeParams);
    _getVaultFactoryStorage()._deployedVaults.push(vault);  // Always pushes
    emit VaultUpgraded(address(vault));
}
```

No check if `vault` is already in `_deployedVaults`. Calling `upgradeVault` multiple times on the same vault creates duplicate entries. Since `removeVault` uses swap-and-pop, removal could remove a duplicate instead of the intended entry.

**Requires**: DEPLOYER_ROLE. Admin power that could cause operational inconvenience.

---

## CANDIDATE-005: VaultFactory.initialize accepts zero-address deployer

| Field              | Value                                                                            |
| ------------------ | -------------------------------------------------------------------------------- |
| **Contracts**      | [`VaultFactory.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/VaultFactory.sol) |
| **Functions**      | [`initialize()`](src/VaultFactory.sol:116)                                       |
| **Classification** | **FALSE POSITIVE** (zero address check for deployer role is on the admin)        |

### Root Cause

`_grantRole(DEPLOYER_ROLE, params.initialDeployer_)` does not validate `initialDeployer_ != address(0)`. However, OZ's AccessControl internally allows granting roles to `address(0)` (it just won't have any effect since no one can be `address(0)`).

Setting deployer to `address(0)` means no one can deploy vaults until the admin grants DEPLOYER_ROLE. This is a configuration error, not a protocol vulnerability.

---

## CANDIDATE-006: Beacon pause can DoS all vault view functions

| Field              | Value                                                                                                                 |
| ------------------ | --------------------------------------------------------------------------------------------------------------------- |
| **Contracts**      | [`VaultUpgradeableBeacon.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/proxy/VaultUpgradeableBeacon.sol)            |
| **Functions**      | [`pause()`](src/proxy/VaultUpgradeableBeacon.sol:145), [`implementation()`](src/proxy/VaultUpgradeableBeacon.sol:117) |
| **Classification** | **EXPECTED ADMIN POWER**                                                                                              |

### Root Cause

`implementation()` has `whenNotPaused` modifier. When beacon is paused, all VaultBeaconProxy calls (which call `implementation()` via `_implementation()`) revert. This includes ALL view functions.

### Prior Audit

**Spearbit 5.4.4** (Informational). Acknowledged by Kiln: "Beacon will only be paused in critical situations."

---

## CANDIDATE-007: VaultFactory initializer modifies OZ AccessControl storage shared with delegateToFactory context

| Field              | Value                                                                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol), [`VaultFactory.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/VaultFactory.sol) |
| **Functions**      | [`delegateToFactory()`](src/Vault.sol:423)                                                                                                           |
| **Classification** | **NEEDS PRODUCTION CHECK**                                                                                                                           |

### Root Cause

`delegateToFactory()` runs factory code in the Vault's storage context. Since both Vault and Factory inherit from `AccessControlDefaultAdminRulesUpgradeable`, they share OZ storage namespaces.

If `delegateToFactory` is called with calldata that executes `grantRole()` or other OZ access control functions on the factory, it would modify the Vault's access control instead.

### Mitigating Factors

1. The production code path (`upgradeVault()`) only calls `__getFeeDispatcherStorage()`, which is a `pure` function that doesn't write storage
2. `delegateToFactory` requires `onlyFactory` — only the factory can trigger it
3. The factory's `upgradeVault()` hardcodes the calldata — no user injection

**Risk**: If a future factory implementation introduces a function that calls `delegateToFactory` with user-controlled calldata, this could be exploited. As-is, this is not exploitable.

---

## CANDIDATE-008: ForceWithdraw is permissionless with no role check

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Functions**      | [`forceWithdraw()`](src/Vault.sol:1015)                            |
| **Classification** | **EXPECTED BEHAVIOR**                                              |

### Final Determination

After comprehensive closure review with 8 targeted tests (all passing), forceWithdraw is **EXPECTED BEHAVIOR**. Here is the complete analysis:

### Q1: Is permissionless forceWithdraw explicitly intended or documented?

The natspec says "Force withdraws a user from the vault" with no role specification. The absence of `onlyRole` is intentional — it ensures blocked users can always be exited even if the operator is malicious or unavailable.

### Q2: Can the caller redirect assets, receive value, influence the conversion rate, or profit?

**NO**. [`forceWithdraw`](src/Vault.sol:1036) calls:

```solidity
_withdraw(blockedUser, blockedUser, blockedUser, _assets, _maxRedeemable);
```

The receiver is hardcoded to `blockedUser`. The caller (`msg.sender`) is never the receiver. Test `test_attackerDoesNotReceiveFunds` proves: attacker balance is unchanged after forceWithdraw.

### Q3: Can the blocked user lose principal compared with calling redeem at the same block?

**NO**. The blocked user **cannot** call `redeem()` because they're blocked (the `notBlocked` modifier reverts). ForceWithdraw is the **only** exit path for blocked users. The alternative is indefinite lockup.

Test `test_fairValue` proves: the blocked user receives deposit + yield (minus pro-rata fees, same as redeem).

### Q4: Can the blocked user lose already-accrued rewards or fees?

**NO**. [`forceWithdraw`](src/Vault.sol:1026) calls `_accrueRewardFee()` which is the **same** function called by [`redeem()`](src/Vault.sol:596). Both compute reward fees on the interest since `_lastTotalAssets` using identical `_convertToAssets(Math.Rounding.Floor, ...)` logic. Test `test_rewardFee` proves the reward fee path is preserved.

### Q5: Can an attacker time forceWithdraw during temporary illiquidity, exchange-rate manipulation, protocol loss, reward distribution, or fee updates to cause measurable additional harm?

**NO** for the following reasons:

- **Illiquidity**: Protected by [`_maxRedeem == balanceOf(owner)`](src/Vault.sol:1030) — if the connector can't serve the full position, forceWithdraw reverts with `InsufficientLiquidity`. Test `test_fullExitRequired` proves this.
- **Rate manipulation**: The attacker captures NO value — funds go to the blocked user, not the caller. Rate fluctuations affect ALL users equally (pro-rata). Test suite covers rate increase and decrease scenarios.
- **Fee updates**: The blocked user's shares convert using the same ERC4626 math as redeem. Fee changes cannot be exploited by the caller since the caller doesn't participate in the conversion.
- **No profit path**: The caller spends gas and receives zero value. No economic incentive exists.

### Q6: Does forceWithdraw bypass allowance, ownership, receiver, slippage, minimum-output, cooldown, lockup, or user-choice protections?

The only bypasses are:

- **Receiver**: Hardcoded to `blockedUser` — the user cannot choose a different receiver (but the funds go to themselves)
- **Partial exit**: Not allowed — user must exit their entire position (this is a safety check, not an attack vector)
- **Allowance**: Not needed — the caller is not taking the user's allowance, the shares are burned by the contract

All other protections (ownership, slippage, etc.) are not applicable or are handled identically to `redeem`.

### Q7: Can blocklisting be triggered by an unprivileged attacker?

**NO**. [`addToBlockList()`](src/BlockList.sol:130) requires `onlyRole(OPERATOR_ROLE)`. The OPERATOR_ROLE is a privileged role managed by DEFAULT_ADMIN_ROLE on the BlockList contract. Test `test_cannotTriggerBlocklist` proves this.

### Q8: Is the behavior already described or accepted in an audit or protocol specification?

**YES**. Prior audits found and classified specific forceWithdraw issues:

| Finding                                          | Severity | Status                                                         |
| ------------------------------------------------ | -------- | -------------------------------------------------------------- |
| Spearbit 5.2.5: Blind transfers in forceWithdraw | Low      | **Fixed**                                                      |
| Spearbit 5.2.6: Inaccurate event emission        | Low      | **Fixed**                                                      |
| Spearbit 5.2.8: Sanctioned users can withdraw    | Medium   | **Fixed** (current code checks `isSanctionedByUnderlyingList`) |

None of these findings classified the **permissionless nature** as a vulnerability. The fixes addressed specific behavioral issues, not the access control model.

### Q9: Is any active production vault configured in a way that makes the harm reproducible?

The code is identical in production (beacon points to matching implementation). The behavior is consistent.

### Final Classification Rationale

**EXPECTED BEHAVIOR** because:

1. **No value extraction**: The caller receives nothing. Funds go to the blocked user.
2. **No blocklisting trigger**: Attacker cannot cause a user to become blocked.
3. **Same accounting as redeem**: Same `_accrueRewardFee`, same `_convertToAssets(Floor)`, same `_withdraw` path.
4. **Full-withdrawal protection**: Reverts if connector can't serve the full amount — prevents partial forced exits.
5. **Prior audits accepted it**: Spearbit classified specific sub-behaviors (not the permissionless model) as issues, which were fixed.
6. **Design necessity**: Making forceWithdraw role-gated would create centralization risk — a malicious or inactive operator could trap blocked users indefinitely. The permissionless design ensures blocked users can always be rescued.

### Supporting Test Evidence

All 8 closure tests in [`test/audit/batch2/ForceWithdrawClosure.t.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/test/audit/batch2/ForceWithdrawClosure.t.sol) pass:

| Test                               | Verdict | Proof                                       |
| ---------------------------------- | ------- | ------------------------------------------- |
| `test_attackerDoesNotReceiveFunds` | PASS    | Attacker gets 0, blocked user gets funds    |
| `test_fairValue`                   | PASS    | Returns fair value (deposit + yield - fees) |
| `test_fullExitRequired`            | PASS    | Reverts on insufficient liquidity           |
| `test_rewardFee`                   | PASS    | Reward fee path preserved                   |
| `test_cannotForceNonBlocked`       | PASS    | Non-blocked user protected                  |
| `test_griefOnly`                   | PASS    | No economic gain for attacker               |
| `test_cannotTriggerBlocklist`      | PASS    | Blocklisting requires OPERATOR_ROLE         |
| `test_worksAfterDepositPause`      | PASS    | Works during deposit pause                  |

---

## CANDIDATE-009: BlockList isSanctionedByUnderlyingList can revert, bricking vault

| Field              | Value                                                                                             |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| **Contracts**      | [`BlockList.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/BlockList.sol)                        |
| **Functions**      | [`isSanctionedByUnderlyingList()`](src/BlockList.sol:178), [`isBlocked()`](src/BlockList.sol:160) |
| **Classification** | **NEEDS PRODUCTION CHECK**                                                                        |

### Root Cause

`isBlocked()` calls `ISanctionsList($._underlyingSanctionsList).isSanctioned(addr)`. If the Chainalysis oracle contract reverts (e.g., due to upgrade or deprecation), all `notBlocked` modifier checks in the Vault would revert, blocking ALL deposits, withdrawals, and transfers.

### Attacker Vectors

- No direct attacker vector — the oracle reverting is an external dependency failure
- However, if the oracle can be griefed or DOS'd, it affects the vaults
- The `setUnderlyingSanctionsList()` (OPERATOR_ROLE) can replace it, but only the operator can do this

**Mitigating**: The `isBlocked` function calls the oracle directly. If the oracle reverts, the entire vault's `notBlocked` modifier chain reverts. Moving to a `try/catch` pattern could mitigate this.

---

## CANDIDATE-010: VaultFactory immutable storage prevents updating core dependencies

| Field              | Value                                                                            |
| ------------------ | -------------------------------------------------------------------------------- |
| **Contracts**      | [`VaultFactory.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/VaultFactory.sol) |
| **Storage**        | [`VaultFactoryStorage`](src/VaultFactory.sol:54)                                 |
| **Classification** | **EXPECTED ADMIN POWER**                                                         |

The factory stores `_vaultBeacon`, `_connectorRegistry`, and `_feeDispatcher` during initialization and provides NO setters to update them. To change any of these, the factory implementation itself must be upgraded (UUPS proxy).

This is by design but means:

- If the beacon needs replacement (e.g., deployed to wrong address), the factory must be upgraded
- If the connector registry needs replacement, the factory must be upgraded
- If the fee dispatcher needs replacement, the factory must be upgraded

---

## CANDIDATE-011: Vault.initialize accepts address(0) as asset

| Field              | Value                                                              |
| ------------------ | ------------------------------------------------------------------ |
| **Contracts**      | [`Vault.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/Vault.sol) |
| **Functions**      | [`_initialize()`](src/Vault.sol:350)                               |
| **Classification** | **FALSE POSITIVE** (only deployable by factory DEPLOYER)           |

`__ERC4626_init(params.asset_)` does not validate that `asset_ != address(0)`. A vault deployed with `address(0)` as asset would be permanently broken. However, only DEPLOYER_ROLE can create vaults, and a DEPLOYER has no incentive to deploy a broken vault.

---

## CANDIDATE-012: VaultUpgradeableBeacon.implementation view-reverts when paused — breaks all vault RPC calls

Already covered in CANDIDATE-006. This is a KNOWN ISSUE.

---

## Summary

| ID  | Title                                           | Classification             |
| --- | ----------------------------------------------- | -------------------------- |
| 001 | VaultUpgradeableBeacon.pauseFor uint88 overflow | **KNOWN ISSUE**            |
| 002 | Missing \_disableInitializers on Vault          | **KNOWN ISSUE**            |
| 003 | Unused \_self immutable                         | **EXPECTED BEHAVIOR**      |
| 004 | Factory upgradeVault duplicate entries          | **EXPECTED ADMIN POWER**   |
| 005 | Factory init accepts zero deployer              | **FALSE POSITIVE**         |
| 006 | Beacon pause DoS on view functions              | **EXPECTED ADMIN POWER**   |
| 007 | delegateToFactory OZ storage collision          | **NEEDS PRODUCTION CHECK** |
| 008 | forceWithdraw permissionless                    | **EXPECTED BEHAVIOR**
| 009 | Sanctions oracle revert bricks vault            | **NEEDS PRODUCTION CHECK**
| 010 | Factory immutable dependencies                  | **EXPECTED ADMIN POWER**     |
| 009 | Sanctions oracle revert bricks vault            | **NEEDS PRODUCTION CHECK** |
| 010 | Factory immutable dependencies                  | **EXPECTED ADMIN POWER**   |
| 011 | Zero-asset vault deployable                     | **FALSE POSITIVE**         |
| 012 | Beacon pause view revert                        | **KNOWN ISSUE**            |

No **VALID** high/critical initialization or upgrade vulnerabilities were identified in the current source code. The most impactful issues are:

1. **KNOWN ISSUE**: VaultUpgradeableBeacon.pauseFor overflow (Medium — acknowledged with PauserProxy mitigation)
3. **NEEDS PRODUCTION CHECK**: Sanctions oracle revert DoS (Low-Medium — external dependency)
