# Batch 2 — Storage Layout Review

## 1. Vault Storage Layout

### 1.1 Custom Storage (ERC-7201)

```solidity
bytes32 private constant VaultStorageLocation =
    0x6bb5a2a0ae924c2ea94f037035a09f65614421e2a7d96c9bcbd59acdd32e6000;
```

Layout at this slot:

```
+slot 0: IConnectorRegistry _connectorRegistry      (160 bits)
+slot 0: bytes32 _connectorName                      (256 bits)
+slot 1: uint256 _depositFee
+slot 2: uint256 _rewardFee
+slot 3: uint256 _lastTotalAssets
+slot 4: uint256 _minTotalSupply
+slot 5: bool _transferable + uint8 _offset          (packed)
+slot 6: uint256 _collectableRewardFeesShares
+slot 7: BlockList _blockList                        (160 bits)
+slot 7: bool _depositPaused                         (8 bits)
+slot 7: AdditionalRewardsStrategy _additionalRewardsStrategy (enum, 8 bits)
+slot 8: IFeeDispatcher _feeDispatcher               (160 bits)
```

**Total**: 9 storage slots for custom data.

### 1.2 Inherited OZ Storage (ERC-7201 namespaces)

- **ERC20Upgradeable**: `0x52c63247`... namespace → `_balances`, `_allowances`, `_totalSupply`, `_name`, `_symbol`
- **ERC4626Upgradeable**: `0x2c18f5`... namespace → `_asset` (at specific namespace slot)
- **AccessControlUpgradeable**: `0x40c6a2`... namespace → `_roles` mapping
- **AccessControlDefaultAdminRulesUpgradeable**: `0x2c18f5`... namespace → default admin + delay state
- **ReentrancyGuardUpgradeable**: `0xce26a9`... namespace → `_status`

### 1.3 Immutables (NOT in storage)

```solidity
address internal immutable _self;                    // Not referenced in code
IAccessControl internal immutable _externalAccessControl;  // Used for SPENDER_ROLE checks
address public immutable vaultFactory;               // Used for onlyFactory modifier
```

Immutables are baked into the bytecode at construction. They are NOT part of the storage layout and cannot be changed across upgrades.

---

## 2. VaultFactory Storage Layout

### 2.1 Custom Storage (ERC-7201)

```solidity
bytes32 private constant VaultFactoryStorageLocation =
    0xb15b0e5184d023350edf2480f9c9912300640d68c5b0243b52371c071431c400;
```

Layout at this slot:

```
+slot 0: Vault[] _deployedVaults     (dynamic array, slot = keccak256(0))
+slot 1: address _vaultBeacon
+slot 2: IConnectorRegistry _connectorRegistry
+slot 3: address _feeDispatcher
```

### 2.2 Inherited OZ Storage

- **AccessControlDefaultAdminRulesUpgradeable**: Same namespace as Vault (shared base)

---

## 3. FeeDispatcher Storage Layout

### 3.1 Custom Storage (ERC-7201)

```solidity
bytes32 private constant FeeDispatcherStorageLocation =
    0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300;
```

Layout at this slot (current FeeDispatcher):

```
+slot 0: mapping(address => IFeeDispatcher.Dispatch) _dispatches
```

Where `Dispatch`:

```
+ per-vault mapping entry:
  + slot 0 (of dispatch): uint256 _pendingDepositFee
  + slot 1: uint256 _pendingRewardFee
  + slot 2+: FeeRecipient[] _feeRecipients (dynamic array, slot = keccak256(dispatch_key))
```

### 3.2 Old FeeDispatcher_1_0_0 Storage (SAME SLOT)

The old (`_archive/FeeDispatcher_1_0_0.sol`) used a struct stored at the same slot:

```
// slot 0xfdd5e928...
struct FeeDispatcherStorage {
    uint256 _pendingManagementFee;   // Slot 0
    uint256 _pendingPerformanceFee;  // Slot 1
    FeeRecipient[] _feeRecipients;  // Slot 2+ (dynamic array)
}
```

**Compatibility**: The old and new FeeDispatcher use the same ERC-7201 slot but with different internal structures. The migration in `VaultFactory.upgradeVault()` explicitly reads the old format and writes the new format. After migration, the old slots are never read again.

---

## 4. BlockList Storage Layout

### 4.1 Custom Storage (ERC-7201)

```solidity
bytes32 private constant BlockListStorageLocation =
    0x95688183686c3ec8efadb488883ac1d27f5a2b91d991ab031b02fd896646bd00;
```

Layout at this slot:

```
+slot 0: ISanctionsList _underlyingSanctionsList      (160 bits)
+slot 0: <padding>                                     (96 bits)
+slot 1: mapping(address => bool) _blockList
+slot 2: string _name                                  (dynamic)
```

---

## 5. OZ Shared Storage Slots

Both Vault and VaultFactory inherit from `AccessControlDefaultAdminRulesUpgradeable`, which means they share the SAME OZ storage namespaces:

### Initializable Slot (shared by all upgradeable contracts)

```
0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00
```

Data: `uint64 _initialized` + `bool _initializing`

### AccessControl Slot

Uses ERC-7201 namespace: `openzeppelin.storage.AccessControl`

### AccessControlDefaultAdminRules Slot

Uses ERC-7201 namespace: `openzeppelin.storage.AccessControlDefaultAdminRules`

---

## 6. Storage Collision Analysis

### 6.1 Vault ↔ VaultFactory (via delegateToFactory)

When `delegateToFactory` executes factory code in the Vault's storage context:

| Operation                                       | Writes to Slot | Vault Data at That Slot           | Collision Risk                |
| ----------------------------------------------- | -------------- | --------------------------------- | ----------------------------- |
| Factory writes to `VaultFactoryStorageLocation` | `0xb15b0e...`  | Vault has no data at this slot    | LOW — different namespace     |
| Factory OZ access control writes                | `0x40c6a2...`  | Vault has ITS access control here | **HIGH** — same OZ namespace! |

**Critical Insight**: If a factory function modifies OZ AccessControl storage (e.g., through `grantRole()`), it would modify the VAULT's access control, not the factory's! This is because the code runs in the Vault's storage context.

### 6.2 FeeDispatcher ↔ Vault

The FeeDispatcher is a separate contract, not sharing storage with any vault. Fee per vault is tracked via `msg.sender` key in a mapping. No collision.

### 6.3 Vault ↔ BlockList

BlockList is a separate beacon proxy. No storage overlap with Vault.

### 6.4 Old FeeDispatcher Storage Migration

The old `FeeDispatcher_1_0_0` was inherited by the Vault (as an `abstract contract`). Its storage at `0xfdd5e928...` WAS part of the Vault's storage layout. After migration to the new FeeDispatcher (which is a separate contract), the old storage slots in the Vault still contain stale data but are no longer actively managed.

---

## 7. Upgrade Compatibility Matrix

| Upgrade Scenario                   | Source → Target             | Layout Compatible?                           | Risk                               |
| ---------------------------------- | --------------------------- | -------------------------------------------- | ---------------------------------- |
| Vault impl upgrade (beacon)        | Vault_v1 → Vault_v2         | Must maintain `VaultStorageLocation`         | Beacon upgrade hits ALL vaults     |
| VaultFactory impl upgrade (proxy)  | Factory_v1 → Factory_v2     | Must maintain `VaultFactoryStorageLocation`  | Proxy admin controlled             |
| BlockList impl upgrade (beacon)    | BlockList_v1 → BlockList_v2 | Must maintain `BlockListStorageLocation`     | Beacon upgrade hits ALL blocklists |
| FeeDispatcher impl upgrade (proxy) | FD_v1 → FD_v2               | Must maintain `FeeDispatcherStorageLocation` | Proxy admin controlled             |

### Vault Beacon Upgrade Constraints

The beacon upgrade changes implementation for ALL vaults simultaneously. The new implementation MUST:

1. Use the same `VaultStorageLocation` constant
2. Not add storage before existing fields in VaultStorage
3. Not remove fields from VaultStorage
4. Be compatible with existing VaultStorage data
5. Return the same `vaultFactory` immutable (impossible to change!)
6. Return the same `_externalAccessControl` immutable (impossible to change!)

**Constraint 5 is critical**: The `vaultFactory` immutable is baked into the Vault implementation bytecode. If the factory address needs to change, a new implementation with a new immutable must be deployed, and the beacon must point to it. The old implementation's vaults will be upgraded to use the new implementation, which has the new factory address... but the old vaults' proxies will still use the old implementation's storage but with new code.

Wait, that's not right. The beacon stores the implementation address. All proxies pointing to this beacon will use the new implementation. The new implementation has its own constructor, which sets its own `vaultFactory` immutable. But the OLD proxies don't run the new constructor — they just execute the new code. The `vaultFactory` immutable in the new implementation will be whatever was passed in the new implementation's constructor, which has nothing to do with the old proxies.

Actually, this is a problem. When the old proxies delegatecall to the new implementation:

- `vaultFactory` in the new code refers to the NEW implementation's immutable
- But the old proxies never ran the new constructor, so the immutable is just a constant value in the bytecode
- The `onlyFactory` modifier in the new code would check against the NEW implementation's `vaultFactory` immutable, NOT the old one

This is BY DESIGN — it's how beacon upgrades work. The new implementation's immutables are fixed at its deployment time. If `vaultFactory` is different, then `onlyFactory` would check against a different address than what the proxies expect.

In practice, when upgrading the Vault implementation:

1. Deploy new Vault implementation with SAME constructor params (same factory, same access control)
2. Call `VaultUpgradeableBeacon.upgradeTo(newImpl)`
3. All proxies now use new code with the SAME immutable values (because constructor params match)

This is expected behavior but MUST be verified during each upgrade.

---

## 8. Storage Layout Verification Checklist

For each future upgrade:

- [ ] `VaultStorageLocation` constant unchanged
- [ ] No fields removed from VaultStorage struct
- [ ] New fields appended at END of VaultStorage struct only
- [ ] OZ upgradeable contract inheritance order unchanged
- [ ] New implementation constructor matches old factory/access control addresses
- [ ] FeeDispatcherStorageLocation unchanged
- [ ] BlockListStorageLocation unchanged
- [ ] VaultFactoryStorageLocation unchanged
