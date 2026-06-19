# Batch 2 — Upgrade Review

## 1. Beacon Upgrade Analysis

### 1.1 VaultUpgradeableBeacon.upgradeTo

```solidity
function upgradeTo(address newImplementation) external whenNotFrozen onlyRole(IMPLEMENTATION_MANAGER_ROLE) {
    _setImplementation(newImplementation);
}
```

**Protections**:

- `whenNotFrozen` — cannot upgrade if frozen
- `onlyRole(IMPLEMENTATION_MANAGER_ROLE)` — specific role required
- `_setImplementation` checks `newImplementation.code.length > 0`

**Attack paths**:

| Path                                | Blocked?      | Reason                                  |
| ----------------------------------- | ------------- | --------------------------------------- |
| Upgrade to EOA                      | YES           | `code.length == 0` check                |
| Upgrade when frozen                 | YES           | `whenNotFrozen` modifier                |
| Upgrade without role                | YES           | `onlyRole(IMPLEMENTATION_MANAGER_ROLE)` |
| Upgrade to self-destructed impl     | YES           | `code.length == 0` after self-destruct  |
| Upgrade to malicious impl with role | NO (expected) | Admin power                             |

### 1.2 Freeze Permanence

```solidity
function freeze() external onlyRole(FREEZER_ROLE) whenNotFrozen {
    frozen = true;
    emit Frozen();
}
```

There is NO `unfreeze()` function. Once frozen, the beacon is permanently frozen. This is by design.

**Effect of freeze**:

- `upgradeTo()` reverts (due to `whenNotFrozen`)
- `implementation()` does NOT revert (it has no `whenNotFrozen` modifier... check)
- Looking at the code: `implementation()` has `whenNotPaused` but NOT `whenNotFrozen`
- So frozen ≠ paused. After freeze, vaults still function normally, but no more implementation upgrades.

**Risk**: If `FREEZER_ROLE` is accidentally granted to a malicious or irresponsible address, all vaults are permanently locked to their current implementation.

### 1.3 Pause Behavior

```solidity
function implementation() external view override whenNotPaused returns (address) {
    return _implementation;
}
```

When paused, `implementation()` reverts. Since `VaultBeaconProxy._implementation()` calls `IBeacon(_getBeacon()).implementation()`, ALL vault view functions revert when the beacon is paused.

**Prior audit**: Spearbit 5.4.4 (Informational) noted this. Kiln acknowledged.

**Attack path**: A PAUSER_ROLE holder can pause the beacon, making all vault view functions unreachable. This is a DoS vector.

---

## 2. VaultFactory Upgrade Path

### 2.1 upgradeVault Function

```solidity
function upgradeVault(Vault vault, UpgradeVaultParams memory upgradeVaultParams) external onlyRole(DEPLOYER_ROLE) {
    bytes memory _call = abi.encodeCall(VaultFactory.__getFeeDispatcherStorage, ());
    FeeDispatcher_1_0_0.FeeDispatcherStorage memory previousStorage =
        abi.decode(vault.delegateToFactory(_call), (FeeDispatcher_1_0_0.FeeDispatcherStorage));
    // ... build UpgradeParams from old storage ...
    vault.upgrade(upgradeParams);
    _getVaultFactoryStorage()._deployedVaults.push(vault);
    emit VaultUpgraded(address(vault));
}
```

**Call sequence**:

1. Factory calls `vault.delegateToFactory(_call)` → vault executes `ISelf(factory)._self().functionDelegateCall(_call)` → runs factory's `__getFeeDispatcherStorage()` in vault's storage
2. Factory calls `vault.upgrade(upgradeParams)` → vault executes `_upgrade()` → `reinitializer(2)`

**Potential issues**:

#### 2.1.1 Duplicate Vault Entries

`upgradeVault` ALWAYS pushes `vault` to `_deployedVaults`, even if it's already in the array. Calling `upgradeVault` multiple times on the same vault adds duplicate entries.

```solidity
// After first upgradeVault: [vault]
// After second upgradeVault: [vault, vault]
// After third upgradeVault:  [vault, vault, vault]
```

Impact: The `_deployedVaults` array grows unboundedly. This wastes storage and makes `getDeployedVaults()` more expensive. `removeVault` with swap-and-pop means a duplicate could be removed while the original remains.

**Severity**: LOW (requires DEPLOYER_ROLE, no fund loss)

#### 2.1.2 Malicious Vault in upgradeVault

The `vault` parameter in `upgradeVault` is user-controlled (within DEPLOYER_ROLE). If a DEPLOYER calls `upgradeVault` with a malicious contract at `vault`:

```solidity
vault.delegateToFactory(_call);  // Can be any code
```

The malicious vault's `delegateToFactory()` runs. Since `delegateToFactory` has `onlyFactory`, and the factory is calling it, `_msgSender() == vaultFactory` passes. The malicious vault could execute arbitrary code in response.

Then `vault.upgrade(upgradeParams)` is called, which has `onlyFactory` — same issue. A malicious vault could implement `upgrade()` to do anything.

**Mitigation**: This requires DEPLOYER_ROLE, which is already a highly privileged position. The DEPLOYER could deploy a malicious vault directly without going through `upgradeVault`. So this is not a privilege escalation.

#### 2.1.3 Old FeeDispatcherStorage Not Cleared

**Prior audit**: Spearbit 5.2.4 (Low) — "Vault upgrade process does not reset the old FeeDispatcherStorage state of vault."

The old `FeeDispatcher_1_0_0.FeeDispatcherStorage` struct (at slot `0xfdd5e928...`) stores `_pendingManagementFee`, `_pendingPerformanceFee`, and `_feeRecipients[]`. After migration to the new FeeDispatcher, these slots are no longer actively managed but may still contain stale data.

The new `FeeDispatcher` uses the same ERC-7201 slot but stores a mapping (`_dispatches`) rather than direct fields. So the old storage slot is now interpreted differently.

Old storage at `0xfdd5e928...`:

```
slot 0: _pendingManagementFee (uint256)
slot 1: _pendingPerformanceFee (uint256)
slot 2+: _feeRecipients[] (dynamic array)
```

New storage at `0xfdd5e928...`:

```
slot 0: _dispatches mapping (mapping(address => Dispatch))
```

The types are incompatible. The old uint256 at slot 0 would be interpreted as the first entry of the mapping (key=address(0)). This is stale data, but since the `Vault.__Vault_upgrade()` reads the old values and explicitly migrates them to the new FeeDispatcher, and then the old storage is never read again, this is safe.

---

## 3. delegateToFactory Deep Dive

```solidity
function delegateToFactory(bytes calldata data) external onlyFactory returns (bytes memory) {
    return ISelf(vaultFactory)._self().functionDelegateCall(data);
}
```

### 3.1 Intended Use

Read `FeeDispatcher_1_0_0.FeeDispatcherStorage` from the vault's storage during migration to the new FeeDispatcher. The factory's `__getFeeDispatcherStorage()` is a `pure` function that reads from the ERC-7201 slot and returns the data.

### 3.2 Unintended Reachable Functions

Since `data` is hardcoded in `upgradeVault()` to `abi.encodeCall(VaultFactory.__getFeeDispatcherStorage, ())`, callers cannot inject arbitrary calldata through the production upgrade path.

**However**, if a future factory implementation uses `delegateToFactory` with user-controlled calldata, the following factory functions could be reached in the Vault's storage context:

| Factory Function          | Protected By                                         | Effect in Vault Storage                    |
| ------------------------- | ---------------------------------------------------- | ------------------------------------------ |
| `initialize()`            | `onlyDelegateCall` — PASSES, `initializer` — REVERTS | Would overwrite AccessControl storage      |
| `createVault()`           | `onlyRole(DEPLOYER_ROLE)` — msg.sender = factory     | Would deploy new proxy in vault's context  |
| `upgradeVault()`          | `onlyRole(DEPLOYER_ROLE)`                            | Would call delegateToFactory recursively   |
| `removeVault()`           | `onlyRole(DEPLOYER_ROLE)`                            | Would modify factory storage slot in vault |
| `grantRole()` (inherited) | No explicit guard (OZ's AccessControl)               | Would modify vault's access control!       |

**Important**: All `onlyRole` checks use `_msgSender()` which is the factory address during this delegatecall. If the factory has granted itself DEPLOYER_ROLE or DEFAULT_ADMIN_ROLE, these functions would pass.

Since the production code only calls `__getFeeDispatcherStorage()` through this path, this is currently NOT exploitable.

### 3.3 Storage Corollary

Since `delegateToFactory` executes factory code in the Vault's storage, any storage writes by factory functions modify Vault storage at the same slot positions. The factory's `VaultFactoryStorage` layout:

```solidity
struct VaultFactoryStorage {
    Vault[] _deployedVaults;      // slot 0 (dynamic array)
    address _vaultBeacon;          // slot 1
    IConnectorRegistry _connectorRegistry; // slot 2
    address _feeDispatcher;        // slot 3
}
```

These slots (0-3) would overwrite whatever the Vault has at those positions. In the Vault's layout:

- Slot 0: ERC20 `_balances` mapping
- Slot 1: ERC20 `_allowances` mapping (actually, in v5 OZ uses ERC-7201)

Wait, I need to check the actual storage layout. The Vault uses ERC-7201 for its custom storage, but OZ upgradeable contracts also use ERC-7201. So the exact slot positions depend on the namespace hashes.

Since Vault and Factory use different ERC-7201 namespaces for their custom storage, but share the same OZ base contracts (AccessControl, ReentrancyGuard), there would be conflicts at the OZ storage level.

**Key insight**: `delegateToFactory` runs factory code, which writes to factory's `VaultFactoryStorageLocation` slot. But this writes to the same slot in the Vault's storage. If the Vault has unrelated data at that slot, it gets corrupted.

The Vault's `VaultStorageLocation` is:

```
0x6bb5a2a0ae924c2ea94f037035a09f65614421e2a7d96c9bcbd59acdd32e6000
```

The Factory's `VaultFactoryStorageLocation` is:

```
0xb15b0e5184d023350edf2480f9c9912300640d68c5b0243b52371c071431c400
```

These are completely different. No collision.

**The OZ storage** (AccessControl, Initializable, ReentrancyGuard) uses ERC-7201 namespaces. These are shared between Vault and Factory since both inherit from the same base contracts. So OZ storage IS shared:

- Initializable: `0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00`
- AccessControl: Standard OZ v5 ERC-7201 slot
- ReentrancyGuard: Standard OZ v5 ERC-7201 slot

If factory code modifies these slots (e.g., through `grantRole`), it would corrupt the Vault's access control!

---

## 4. CREATE2 Deployment Analysis

### 4.1 VaultFactory.createVault

```solidity
address payable _newVault = payable(
    Create2.deploy(
        0,
        salt,
        abi.encodePacked(type(VaultBeaconProxy).creationCode, abi.encode($._vaultBeacon, _initCalldata))
    )
);
```

Each vault is deployed with a user-specified salt. The address is deterministic:

```
address = keccak256(0xff + factory_address + salt + keccak256(creationCode + abi.encode(beacon, initData)))
```

**Attack paths**:

| Path                                    | Feasible?               | Reason                                            |
| --------------------------------------- | ----------------------- | ------------------------------------------------- |
| Predict vault address before creation   | YES (by design)         | CREATE2 is deterministic                          |
| Deploy to an existing address           | NO                      | CREATE2 reverts if address has code               |
| Salt collision between different params | Possible but irrelevant | Different init data → different address           |
| Front-run creation with same salt       | NO                      | Only factory can call createVault (DEPLOYER_ROLE) |

### 4.2 BlockListFactory.createBlockList

Same CREATE2 pattern. Safe for the same reasons.

---

## 5. Upgrade Authority Summary

| Operation                      | Required Role                   | Administering Role      | Can Bypass?                     |
| ------------------------------ | ------------------------------- | ----------------------- | ------------------------------- |
| Vault implementation upgrade   | IMPLEMENTATION_MANAGER (beacon) | DEFAULT_ADMIN (beacon)  | Freeze prevents                 |
| Vault per-vault upgrade        | DEPLOYER (factory)              | DEFAULT_ADMIN (factory) | Factory UUPS upgrade            |
| Beacon freeze                  | FREEZER (beacon)                | DEFAULT_ADMIN (beacon)  | Irreversible                    |
| Beacon pause                   | PAUSER (beacon)                 | DEFAULT_ADMIN (beacon)  | UNPAUSER can unpause            |
| Factory implementation upgrade | Proxy admin (not in code)       | Proxy deployer          | If EOA, single point of failure |
| Fee dispatcher change          | Not directly modifiable         | Factory upgrade needed  | Depends on factory upgrade      |

### 5.1 DefaultAdminRules Delay

All contracts use `AccessControlDefaultAdminRules` or `AccessControlDefaultAdminRulesUpgradeable`. The `initialDelay` parameter:

- Affects `DEFAULT_ADMIN_ROLE` changes only (accepting/renouncing)
- Does NOT affect role management for other roles (grantRole/revokeRole have no delay)
- Does NOT affect beacon upgrades, connector management, etc.

### 5.2 Critical Role Observations

1. **Beacon IMPLEMENTATION_MANAGER** controls ALL vaults' logic
2. **Factory DEPLOYER** controls which vaults exist and can trigger per-vault upgrades
3. **Beacon FREEZER** can permanently stop upgrades (one-way)
4. **Beacon PAUSER** can DoS all view functions (one-way until unpaused by UNPAUSER)
