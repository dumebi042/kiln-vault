# Batch 2 — Architecture Map: Initialization & Upgrade Safety

## 1. Contract Topology & Proxy Patterns

| Contract                   | Type           | Proxy Pattern                                      | Implementation Locked?      | Storage Layout                          |
| -------------------------- | -------------- | -------------------------------------------------- | --------------------------- | --------------------------------------- |
| Vault                      | Implementation | Beacon proxy (via VaultBeaconProxy)                | No `_disableInitializers()` | ERC-7201 VaultStorage + OZ slots        |
| VaultBeaconProxy           | Proxy          | Minimal OZ BeaconProxy                             | Immutable beacon            | EIP-1967 beacon slot (immutable)        |
| VaultUpgradeableBeacon     | Beacon         | Standalone (AccessControlDefaultAdminRules)        | Non-upgradeable itself      | Direct storage                          |
| VaultFactory               | Implementation | UUPS-compatible (generic proxy)                    | No `_disableInitializers()` | ERC-7201 VaultFactoryStorage + OZ slots |
| BlockList                  | Implementation | Beacon proxy (via BlockListBeaconProxy)            | No `_disableInitializers()` | ERC-7201 BlockListStorage + OZ slots    |
| BlockListBeaconProxy       | Proxy          | Minimal OZ BeaconProxy                             | Immutable beacon            | EIP-1967 beacon slot (immutable)        |
| BlockListUpgradeableBeacon | Beacon         | Standalone (AccessControlDefaultAdminRules)        | Non-upgradeable itself      | Direct storage                          |
| BlockListFactory           | Standalone     | Direct deployment (AccessControlDefaultAdminRules) | N/A                         | Direct storage                          |
| FeeDispatcher              | Implementation | Generic proxy (SimpleProxy-style)                  | No `_disableInitializers()` | ERC-7201 FeeDispatcherStorage           |
| ExternalAccessControl      | Implementation | Generic proxy (SimpleProxy-style)                  | No `_disableInitializers()` | OZ AccessControl slots                  |

---

## 2. Initialization Chain

### 2.1 Vault Creation (VaultFactory.createVault)

```
VaultFactory.createVault(params, salt) [DEPLOYER_ROLE]
│
├── Build InitializationParams (from params + factory storage)
├── Build UpgradeParams (from params + factory storage)
├── Encode Vault.initialize(initParams, upgradeParams)
│
└── Create2.deploy(0, salt, VaultBeaconProxy.creationCode + abi.encode(beacon, initData))
    │
    └── VaultBeaconProxy.constructor(beacon, initData)
        │
        ├── ERC1967Utils.upgradeBeaconToAndCall(beacon, initData)
        │   ├── _setBeacon(beacon)             → EIP-1967 beacon slot
        │   ├── emit BeaconUpgraded(beacon)
        │   └── Address.functionDelegateCall(  → delegatecall with initData
        │         IBeacon(beacon).implementation(),
        │         initData
        │       )
        │       │
        │       └── Vault.initialize(initParams, upgradeParams) [executes in proxy storage]
        │           │
        │           ├── onlyFactory: _msgSender() == vaultFactory  ✓
        │           │
        │           ├── _initialize(initParams) [initializer modifier]
        │           │   ├── __ERC4626_init(asset)     → ERC20Upgradeable init
        │           │   ├── __ERC20_init(name, symbol)
        │           │   ├── __ReentrancyGuard_init()
        │           │   ├── __AccessControlDefaultAdminRules_init(delay, admin)
        │           │   └── __Vault_init(params) [onlyInitializing]
        │           │       ├── _setOffset
        │           │       ├── _setRewardFee
        │           │       ├── _setDepositFee
        │           │       ├── _setConnectorRegistry
        │           │       ├── _setConnectorName
        │           │       ├── _setTransferable
        │           │       ├── _setMinTotalSupply
        │           │       └── _grantRole calls (FEE_MANAGER, SANCTIONS_MANAGER, etc.)
        │           │
        │           └── _upgrade(upgradeParams) [reinitializer(2) modifier]
        │               └── __Vault_upgrade(params) [onlyInitializing]
        │                   ├── _setBlockList
        │                   ├── _setAdditionalRewardsStrategy
        │                   ├── _setFeeDispatcher
        │                   ├── feeDispatcher.incrementPendingDepositFee
        │                   ├── feeDispatcher.incrementPendingRewardFee
        │                   ├── feeDispatcher.setFeeRecipients
        │                   ├── _grantRole(FEE_COLLECTOR_ROLE)
        │                   ├── _setConnectorRegistry
        │                   └── forceApprove(asset, feeDispatcher, max)
        │
        └── _beacon = beacon (immutable)  ✓
```

### 2.2 Vault Upgrade Path (VaultFactory.upgradeVault)

```
VaultFactory.upgradeVault(vault, upgradeVaultParams) [DEPLOYER_ROLE]
│
├── Build callData = abi.encodeCall(__getFeeDispatcherStorage, ())
├── previousStorage = vault.delegateToFactory(callData)
│   │
│   └── Vault.delegateToFactory(data) [onlyFactory]
│       └── ISelf(vaultFactory)._self().functionDelegateCall(data)
│           │  delegatecall INTO factory IMPL with Vault's storage context
│           └── VaultFactory.__getFeeDispatcherStorage()
│               └── reads FeeDispatcherStorageLocation slot
│
├── Build UpgradeParams (migrate old FeeDispatcher state)
│
└── vault.upgrade(upgradeParams)
    │
    └── Vault.upgrade(upgradeParams) [onlyFactory]
        └── _upgrade(upgradeParams) [reinitializer(2)]
            └── __Vault_upgrade(params)
                ├── _setBlockList
                ├── _setAdditionalRewardsStrategy
                ├── _setFeeDispatcher
                ├── feeDispatcher.incrementPendingDepositFee(pendingDepositFee_)
                ├── feeDispatcher.incrementPendingRewardFee(pendingRewardFee_)
                ├── feeDispatcher.setFeeRecipients(recipients_, underlyingDecimals)
                ├── _grantRole(FEE_COLLECTOR_ROLE, initialFeeCollector_)
                ├── _setConnectorRegistry(connectorRegistry_)
                └── forceApprove(asset(), feeDispatcher_, type(uint256).max)
```

### 2.3 Beacon Upgrade Path

```
VaultUpgradeableBeacon.upgradeTo(newImplementation)
    └── whenNotFrozen (frozen == false)
    └── onlyRole(IMPLEMENTATION_MANAGER_ROLE)
    └── _setImplementation(newImplementation)
        ├── require(code.length > 0)
        └── _implementation = newImplementation
        └── emit Upgraded(newImplementation)
```

Effect: ALL VaultBeaconProxy instances immediately use the new implementation.

---

## 3. Constructor/Initializer Summary

### 3.1 Vault Implementation Constructor

```solidity
constructor(address externalAccessControl_, address vaultFactory_) {
    _externalAccessControl = IAccessControl(externalAccessControl_);
    vaultFactory = vaultFactory_;
}
// No _disableInitializers() call!
```

### 3.2 VaultUpgradeableBeacon Constructor

```solidity
constructor(implementation_, admin, implManager, pauser, unpauser, freezer, delay)
    AccessControlDefaultAdminRules(delay, admin)
{
    _setImplementation(implementation_);
    _grantRole(IMPLEMENTATION_MANAGER_ROLE, initialImplementationManager);
    _grantRole(PAUSER_ROLE, initialPauser);
    _grantRole(UNPAUSER_ROLE, initialUnpauser);
    _grantRole(FREEZER_ROLE, initialFreezer);
}
```

### 3.3 VaultFactory Implementation Constructor

```solidity
// Empty constructor - no initialization, no _disableInitializers()
```

### 3.4 VaultFactory.initialize (delegatecall-only)

```solidity
function initialize(InitializationParams calldata params) public onlyDelegateCall initializer {
    __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialAdmin_);
    // Verify beacon points to correct Vault implementation
    address vaultAddress = IBeacon(params.vaultBeacon_).implementation();
    if (Vault(vaultAddress).vaultFactory() != address(this)) revert VaultMisconfigured();
    // Store beacon, registry, dispatcher
    $._vaultBeacon = params.vaultBeacon_;     // NEVER RESETTABLE
    $._connectorRegistry = IConnectorRegistry(params.connectorRegistry_);  // NEVER RESETTABLE
    $._feeDispatcher = params.feeDispatcher_;   // NEVER RESETTABLE
    _grantRole(DEPLOYER_ROLE, params.initialDeployer_);
}
```

### 3.5 Vault.initialize (factory-only, initializer + reinitializer(2))

```solidity
function initialize(InitializationParams calldata initializationParams, UpgradeParams calldata upgradeParams)
    public onlyFactory
{
    _initialize(initializationParams);    // initializer
    _upgrade(upgradeParams);              // reinitializer(2)
}
```

### 3.6 FeeDispatcher.initialize (delegatecall-only)

```solidity
function initialize() public initializer onlyDelegateCall {
    _initialize();  // __ReentrancyGuard_init()
}
```

### 3.7 BlockList.initialize (delegatecall-only)

```solidity
function initialize(InitializationParams calldata params) public onlyDelegateCall initializer {
    __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialDefaultAdmin_);
    __BlockList_init(params);
}
```

### 3.8 ExternalAccessControl.initialize (delegatecall-only)

```solidity
function initialize(InitializationParams calldata params) public onlyDelegateCall initializer {
    __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialDefaultAdmin_);
    _grantRole(params.initialRole_.role, params.initialRole_.account);
}
```

---

## 4. Immutable Address Table

| Contract              | Immutable                | Value Source      | Used For                                       |
| --------------------- | ------------------------ | ----------------- | ---------------------------------------------- |
| Vault                 | `_self`                  | `address(this)`   | (declared but never referenced in Vault.sol)   |
| Vault                 | `_externalAccessControl` | Constructor param | SPENDER_ROLE check                             |
| Vault                 | `vaultFactory`           | Constructor param | `onlyFactory` modifier                         |
| VaultBeaconProxy      | `_beacon` (inherited)    | Constructor param | `_getBeacon()` → `_implementation()`           |
| VaultFactory          | `_self`                  | `address(this)`   | `onlyDelegateCall`, `delegateToFactory` target |
| BlockList             | `_self`                  | `address(this)`   | `onlyDelegateCall`                             |
| BlockListBeaconProxy  | `_beacon` (inherited)    | Constructor param | `_getBeacon()` → `_implementation()`           |
| BlockListFactory      | `blockListBeacon`        | Constructor param | Used to deploy blocklists                      |
| FeeDispatcher         | `_self`                  | `address(this)`   | `onlyDelegateCall`                             |
| ExternalAccessControl | `_self`                  | `address(this)`   | `onlyDelegateCall`                             |

---

## 5. Upgrade Routes & Required Authority

| Route                    | Entry Point                                       | Authority                   | Scope          | Storage Impact                        |
| ------------------------ | ------------------------------------------------- | --------------------------- | -------------- | ------------------------------------- |
| Beacon upgrade           | `VaultUpgradeableBeacon.upgradeTo()`              | IMPLEMENTATION_MANAGER_ROLE | ALL vaults     | Implementation pointer changes only   |
| Beacon freeze            | `VaultUpgradeableBeacon.freeze()`                 | FREEZER_ROLE                | ALL vaults     | `frozen = true` (permanent)           |
| Beacon pause             | `VaultUpgradeableBeacon.pause()`                  | PAUSER_ROLE                 | ALL vaults     | View functions revert                 |
| Vault upgrade            | `VaultFactory.upgradeVault()` → `Vault.upgrade()` | DEPLOYER_ROLE (via factory) | Single vault   | Reinitializer(2) writes new state     |
| Vault delegate           | `Vault.delegateToFactory()`                       | onlyFactory                 | Single vault   | Factory code in vault storage context |
| Factory upgrade          | Proxy admin (UUPS)                                | Proxy admin                 | Factory itself | Entire factory                        |
| Connector add/update     | `ConnectorRegistry.add/update()`                  | CONNECTOR_MANAGER_ROLE      | Registry       | Connector address mapping             |
| BlockList beacon upgrade | `BlockListUpgradeableBeacon.upgradeTo()`          | IMPLEMENTATION_MANAGER_ROLE | ALL blocklists | Implementation pointer                |
| BlockList deploy         | `BlockListFactory.createBlockList()`              | DEPLOYER_ROLE               | New blocklist  | New proxy                             |

---

## 6. msg.sender / address(this) Tracking Across Delegatecall Boundaries

| Context                                    | Caller      | msg.sender  | address(this) | Storage Context    |
| ------------------------------------------ | ----------- | ----------- | ------------- | ------------------ |
| User → Vault proxy (direct)                | User        | User        | Vault proxy   | Vault proxy        |
| Vault proxy → Vault impl                   | BeaconProxy | User        | Vault proxy   | Vault proxy        |
| Vault → Connector (delegatecall)           | Vault proxy | User        | Vault proxy   | Vault proxy        |
| Vault → FeeDispatcher (direct call)        | Vault proxy | Vault proxy | FeeDispatcher | FeeDispatcher      |
| Factory → Vault (direct call)              | Factory     | Factory     | Vault proxy   | Vault proxy        |
| Factory → Vault.delegateToFactory          | Factory     | Factory     | Vault proxy   | Vault proxy        |
| delegateToFactory → Factory (delegatecall) | Factory     | Factory     | Vault proxy   | Vault proxy (!!! ) |
| Factory → BlockList (direct call)          | Factory     | Factory     | BlockList     | BlockList          |
