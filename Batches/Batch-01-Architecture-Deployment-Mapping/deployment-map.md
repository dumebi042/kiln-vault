# Deployment Map — Kiln OmniVault

## Overview

The Kiln OmniVault system uses a **beacon proxy architecture** with two independent proxy families:

1. **Vault system** (Vault → VaultBeaconProxy → VaultUpgradeableBeacon → Vault implementation)
2. **BlockList system** (BlockList → BlockListBeaconProxy → BlockListUpgradeableBeacon → BlockList implementation)

Plus standalone contracts: `VaultFactory`, `ConnectorRegistry`, `FeeDispatcher`, `ExternalAccessControl`.

---

## 1. Contract Dependency Graph

```
ExternalAccessControl (standalone)
    └── referenced by Vault (immutable _externalAccessControl)

VaultUpgradeableBeacon (standalone)
    └── implementation() → Vault implementation address
    └── VaultBeaconProxy reads from this beacon

VaultFactory (UUPS proxy)
    ├── owns VaultBeacon (stored in VaultFactoryStorage._vaultBeacon)
    ├── owns ConnectorRegistry (stored in VaultFactoryStorage._connectorRegistry)
    ├── owns FeeDispatcher (stored in VaultFactoryStorage._feeDispatcher)
    └── deploys VaultBeaconProxy instances via CREATE2

VaultBeaconProxy (minimal beacon proxy, OpenZeppelin)
    ├── constructor: reads implementation from VaultUpgradeableBeacon
    ├── delegates to Vault implementation
    └── immutable: stores beacon address + initialization data in constructor

Vault (upgradeable via beacon)
    ├── immutable: _self, _externalAccessControl, vaultFactory
    ├── storage: VaultStorage (ERC-7201 slot)
    ├── reads connector from ConnectorRegistry via _connectorName
    ├── calls FeeDispatcher for fee accounting
    ├── checks BlockList for sanctions
    └── delegates to IConnector via functionDelegateCall

ConnectorRegistry (standalone, AccessControlDefaultAdminRules)
    ├── mapping: bytes32 name → ConnectorInfo {address, pauseTimestamp, frozen}
    ├── getOrRevert(): used by Vault during deposit/withdraw (reverts if paused)
    └── get(): used by Vault for preview functions

FeeDispatcher (upgradeable via initializer)
    ├── storage: mapping vault → Dispatch {_pendingDepositFee, _pendingRewardFee, _feeRecipients[]}
    ├── called by Vault via incrementPendingDepositFee / incrementPendingRewardFee
    └── dispatchFees() transfers assets from Vault to recipients

BlockListUpgradeableBeacon (standalone)
    └── implementation() → BlockList implementation address

BlockListFactory (standalone)
    └── deploys BlockListBeaconProxy instances via CREATE2

BlockListBeaconProxy (minimal beacon proxy)
    └── delegates to BlockList implementation

BlockList (upgradeable via beacon)
    ├── storage: _underlyingSanctionsList, _blockList mapping, _name
    ├── isBlocked(): internal list + Chainalysis sanctions oracle
    ├── isBlockedByInternalList(): internal blocklist only
    └── isSanctionedByUnderlyingList(): sanctions oracle only
```

---

## 2. Deployment Flow

### 2.1 Vault System Deployment

```
1. Deploy Vault implementation (constructor sets immutables)
   └─ constructor(externalAccessControl_, vaultFactory_)
   └─ _self = address(this)
   └─ _externalAccessControl = externalAccessControl_
   └─ vaultFactory = vaultFactory_

2. Deploy VaultUpgradeableBeacon
   └─ constructor(implementation_, admin, implManager, pauser, unpauser, freezer, delay)
   └─ calls _setImplementation(implementation_) → stores in _implementation

3. Deploy VaultFactory (upgradeable via AccessControlDefaultAdminRules)
   └─ constructor() → no logic (empty)
   └─ initialize(InitializationParams):
       └─ requires onlyDelegateCall
       └─ __AccessControlDefaultAdminRules_init(...)
       └─ reads VaultUpgradeableBeacon.implementation() → verifies vaultFactory == address(this)
       └─ stores _vaultBeacon, _connectorRegistry, _feeDispatcher
       └─ grants DEPLOYER_ROLE

4. Deploy VaultBeaconProxy (via VaultFactory.createVault)
   └─ CREATE2 with salt
   └─ constructor(beacon, initData) → BeaconProxy(beacon, initData)
   └─ initData = abi.encodeCall(Vault.initialize, (initParams, upgradeParams))
   └─ initialize() called during construction (beacon proxy executes in constructor)
```

### 2.2 BlockList System Deployment

```
1. Deploy BlockList implementation
   └─ constructor() → empty (upgradeable, delay rules not needed in impl)

2. Deploy BlockListUpgradeableBeacon
   └─ constructor(implementation_, admin, implManager, freezer, delay)

3. Deploy BlockListFactory
   └─ constructor(admin, deployer, delay, beacon)

4. Deploy BlockListBeaconProxy (via BlockListFactory.createBlockList)
   └─ CREATE2 with salt
   └─ constructor(beacon, initData) → BeaconProxy(beacon, initData)
   └─ initData = abi.encodeCall(BlockList.initialize, params)
```

### 2.3 Standalone Deployments

```
- ConnectorRegistry: direct deployment
  └─ constructor(admin, pauser, unpauser, freezer, connectorMgr, delay)

- FeeDispatcher: proxy pattern
  └─ deploy implementation → deploy proxy → initialize()

- ExternalAccessControl: proxy pattern
  └─ deploy implementation → deploy proxy → initialize()
```

---

## 3. Contract Address Relationships

| Contract                                 | Address Type    | Set By                                       | Mutable?                          |
| ---------------------------------------- | --------------- | -------------------------------------------- | --------------------------------- |
| `Vault._self`                            | immutable       | constructor                                  | No                                |
| `Vault._externalAccessControl`           | immutable       | constructor                                  | No                                |
| `Vault.vaultFactory`                     | immutable       | constructor                                  | No                                |
| `VaultUpgradeableBeacon._implementation` | private storage | `_setImplementation()`                       | Yes (IMPLEMENTATION_MANAGER_ROLE) |
| `VaultFactory._vaultBeacon`              | storage         | `initialize()`                               | No (not settable post-init)       |
| `VaultFactory._connectorRegistry`        | storage         | `initialize()`                               | No (not settable post-init)       |
| `VaultFactory._feeDispatcher`            | storage         | `initialize()`                               | No (not settable post-init)       |
| `Vault._connectorRegistry`               | storage         | `_setConnectorRegistry()`                    | No (not settable post-init)       |
| `Vault._connectorName`                   | storage         | `_setConnectorName()`                        | No (not settable post-init)       |
| `Vault._blockList`                       | storage         | `_setBlockList()`                            | Yes (SANCTIONS_MANAGER_ROLE)      |
| `Vault._feeDispatcher`                   | storage         | `_setFeeDispatcher()`                        | No (not settable post-init)       |
| `ConnectorRegistry.connectorInfo`        | storage         | `add()` / `update()`                         | Yes (CONNECTOR_MANAGER_ROLE)      |
| `BlockList._blockList`                   | storage         | `addToBlockList()` / `removeFromBlockList()` | Yes (OPERATOR_ROLE)               |
| `BlockList._underlyingSanctionsList`     | storage         | `_setUnderlyingSanctionsList()`              | Yes (OPERATOR_ROLE)               |
| `FeeDispatcher._dispatches`              | storage         | various functions                            | Per-vault                         |

---

## 4. Critical Immutable Address Verification Points

| Verification                                    | Where                           | What to Check                                          |
| ----------------------------------------------- | ------------------------------- | ------------------------------------------------------ |
| Vault implementation has correct `vaultFactory` | `VaultFactory.initialize()`     | `Vault(beacon.impl()).vaultFactory() == address(this)` |
| Beacon implementation is a contract             | `VaultFactory.initialize()`     | `params.vaultBeacon_.code.length > 0`                  |
| ConnectorRegistry is a contract                 | `VaultFactory.initialize()`     | `params.connectorRegistry_.code.length > 0`            |
| FeeDispatcher is a contract                     | `VaultFactory.initialize()`     | `params.feeDispatcher_.code.length > 0`                |
| Connector exists before setting                 | `Vault._setConnectorName()`     | `connectorRegistry.connectorExists(name)`              |
| ConnectorRegistry address is contract           | `Vault._setConnectorRegistry()` | `code.length > 0`                                      |
| FeeDispatcher address is contract               | `Vault._setFeeDispatcher()`     | `code.length > 0`                                      |

---

## 5. Network-Specific Deployment Differences

_This section must be filled with live data from on-chain inspection._

| Network          | VaultFactory | VaultUpgradeableBeacon | ConnectorRegistry | FeeDispatcher | ExternalAccessControl |
| ---------------- | ------------ | ---------------------- | ----------------- | ------------- | --------------------- |
| Ethereum Mainnet | TBD          | TBD                    | TBD               | TBD           | TBD                   |
| Polygon          | TBD          | TBD                    | TBD               | TBD           | TBD                   |
| Arbitrum         | TBD          | TBD                    | TBD               | TBD           | TBD                   |
| Optimism         | TBD          | TBD                    | TBD               | TBD           | TBD                   |
| Base             | TBD          | TBD                    | TBD               | TBD           | TBD                   |

### Known Differences Between Networks

- **L1 vs L2**: Gas costs, block times, and sequencer behavior
- **Sanctions lists**: Chainalysis oracle address varies by network
- **Connector set**: Some connectors may not be deployed on all networks
- **Fee parameters**: May differ by network

---

## 6. Upgrade Path Architecture

```
VaultUpgradeableBeacon.upgradeTo(newImpl)
    └─ requires: IMPLEMENTATION_MANAGER_ROLE, not frozen
    └─ effect: all VaultBeaconProxies pointing to this beacon now use new implementation

BlockListUpgradeableBeacon.upgradeTo(newImpl)
    └─ requires: IMPLEMENTATION_MANAGER_ROLE, not frozen
    └─ effect: all BlockListBeaconProxies pointing to this beacon now use new implementation

Vault.upgrade(upgradeParams) (onlyFactory)
    └─ called by VaultFactory.upgradeVault()
    └─ reinitializer(2) — second version
    └─ sets: blockList, additionalRewardsStrategy, feeDispatcher, feeRecipients, connectorRegistry

Vault.delegateToFactory(data) (onlyFactory)
    └─ allows VaultFactory to access Vault storage via delegatecall
    └─ used for migration from FeeDispatcher_1_0_0 to FeeDispatcher
```
