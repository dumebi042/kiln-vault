# Active Vaults & Connectors — Kiln OmniVault

> **Status**: Code-level analysis. On-chain verification required for live deployment data.

---

## 1. Available Connectors

Based on source code analysis, the following connectors are implemented in [`src/connectors/`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/):

| Connector                | File                                                                                                        | Protocol                 | Asset Type           | Verification Needed                                    |
| ------------------------ | ----------------------------------------------------------------------------------------------------------- | ------------------------ | -------------------- | ------------------------------------------------------ |
| **AaveV3Connector**      | [`AaveV3Connector.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/AaveV3Connector.sol)           | Aave V3                  | aTokens              | Supply caps, reserve status, pool address              |
| **CompoundV3Connector**  | [`CompoundV3Connector.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/CompoundV3Connector.sol)   | Compound V3 (Comet)      | Base asset           | Comet address, base asset, supply/withdraw pause state |
| **MetamorphoConnector**  | [`MetamorphoConnector.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/MetamorphoConnector.sol)   | Morpho Blue / MetaMorpho | ERC4626 vault shares | Market address, vault caps, withdrawal queue           |
| **SDAIConnector**        | [`SDAIConnector.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/SDAIConnector.sol)               | MakerDAO sDAI            | sDAI                 | sDAI rate, DSR changes, withdrawal limits              |
| **SUSDSConnector**       | [`SUSDSConnector.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/SUSDSConnector.sol)             | MakerDAO sUSDS           | sUSDS                | sUSDS rate, SKY changes                                |
| **AngleSavingConnector** | [`AngleSavingConnector.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/connectors/AngleSavingConnector.sol) | Angle Protocol           | agEUR / stEUR        | Savings rate, stablecoin accounting                    |

### Connector Registry Names (bytes32)

Each connector is registered in the `ConnectorRegistry` under a `bytes32` name. The source `_setConnectorName()` function validates via `connectorRegistry.connectorExists()`. The canonical name format is unknown without on-chain data but likely follows a convention like:

```
keccak256("AAVE_V3")
keccak256("COMPOUND_V3")
keccak256("METAMORPHO")
keccak256("SDAI")
keccak256("SUSDS")
keccak256("ANGLE_SAVINGS")
```

> **Production check**: Must verify actual `bytes32` names used in the deployed registry.

---

## 2. Connector Registry Contract

Located at: [`src/ConnectorRegistry.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/ConnectorRegistry.sol)

| Property             | Value                                                      |
| -------------------- | ---------------------------------------------------------- |
| Type                 | Standalone (not proxy)                                     |
| Access control       | `AccessControlDefaultAdminRules`                           |
| Connector storage    | `mapping(bytes32 => ConnectorInfo)`                        |
| ConnectorInfo fields | `address _address`, `uint88 pauseTimestamp`, `bool frozen` |

### Registry State Machine

```
ADD (CONNECTOR_MANAGER)
  └─> EXISTS
        ├─> UPDATE (CONNECTOR_MANAGER, not frozen) — change address
        ├─> PAUSE (PAUSER) — set pauseTimestamp
        ├─> FREEZE (FREEZER) — permanently frozen (irreversible)
        └─> REMOVE (CONNECTOR_MANAGER, not frozen, not paused) — delete
```

---

## 3. Active Vaults (Code-Level Analysis)

Per [`VaultFactory.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/VaultFactory.sol#L55), deployed vaults are stored in:

```solidity
Vault[] _deployedVaults;  // FactoryStorage
```

### Vault Configuration Schema

Each deployed vault stores (in `VaultStorage`):

| Field                          | Type                        | Set During Initialize | Mutable Post-Init?                  |
| ------------------------------ | --------------------------- | --------------------- | ----------------------------------- |
| `_connectorRegistry`           | `IConnectorRegistry`        | Yes (from factory)    | No                                  |
| `_connectorName`               | `bytes32`                   | Yes                   | No                                  |
| `_depositFee`                  | `uint256`                   | Yes                   | Yes (FEE_MANAGER, max 35e(decimal)) |
| `_rewardFee`                   | `uint256`                   | Yes                   | Yes (FEE_MANAGER, max 35e(decimal)) |
| `_lastTotalAssets`             | `uint256`                   | Initializes to 0      | Updated on deposit/withdraw/accrue  |
| `_minTotalSupply`              | `uint256`                   | Yes                   | No                                  |
| `_transferable`                | `bool`                      | Yes                   | No                                  |
| `_offset`                      | `uint8`                     | Yes                   | No                                  |
| `_collectableRewardFeesShares` | `uint256`                   | 0                     | Updated on reward fee accrual       |
| `_blockList`                   | `BlockList`                 | Yes (via upgrade)     | Yes (SANCTIONS_MANAGER)             |
| `_depositPaused`               | `bool`                      | false                 | Yes (PAUSER/UNPAUSER)               |
| `_additionalRewardsStrategy`   | `AdditionalRewardsStrategy` | Yes (via upgrade)     | Yes (CLAIM_MANAGER)                 |
| `_feeDispatcher`               | `IFeeDispatcher`            | Yes (via upgrade)     | No                                  |

### Vault Immutables (Constructor-Set, Never Change)

| Field                    | Value Source          |
| ------------------------ | --------------------- |
| `_self`                  | `address(this)`       |
| `_externalAccessControl` | Constructor parameter |
| `vaultFactory`           | Constructor parameter |

---

## 4. Vault Lifecycle

```
VaultFactory created (with beacon, connector registry, fee dispatcher)
    │
    ├── createVault(params, salt)
    │       └── Deploy VaultBeaconProxy
    │       └── Constructor executes initialize(initParams, upgradeParams)
    │       │       ├── _initialize(): init asset, name, symbol, reentrancy guard, access control
    │       │       └── _upgrade(): init blocklist, rewards strategy, fee dispatcher, recipients
    │       └── Push to _deployedVaults[]
    │
    ├── upgradeVault(vault, params)
    │       └── Read old FeeDispatcher_1_0_0 storage via delegateToFactory
    │       └── vault.upgrade(upgradeParams) → reinitializer(2)
    │
    └── removeVault(index, vault)
            └── Swap-and-pop from _deployedVaults[]
            └── Does NOT destroy vault or withdraw funds
```

---

## 5. FeeDispatcher Architecture

Located at: [`src/FeeDispatcher.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/FeeDispatcher.sol)

The `FeeDispatcher` is a **shared contract** that tracks fee state per-vault (via `msg.sender`).

### Fee Flow

```
Deposit (Vault)
    ├── deposit fee: computed in _previewDeposit(), deducted from deposited assets
    │   └── stored as pending: FeeDispatcher.incrementPendingDepositFee(amount)
    └── reward fee: computed from interest accrued between _lastTotalAssets updates
        └── shares minted to Vault itself
        └── Vault.collectRewardFees() → withdraws assets → stores as pending reward fee

Dispatch (FeeDispatcher.dispatchFees)
    └── called by Vault (msg.sender = vault address)
    └── iterates fee recipients → transfers their split
    └── uses safeTransferFrom (vault → recipient)
```

### Fee Recipient Schema

```solidity
struct FeeRecipient {
    address recipient;
    uint256 depositFeeSplit;
    uint256 rewardFeeSplit;
}
```

Both splits must sum to `_MAX_PERCENT * 10 ** underlyingDecimals` (100% scaled to decimals).

---

## 6. External Access Control

Located at: [`src/ExternalAccessControl.sol`](/Volumes/Dumebi-SSD/Bounty/kiln-vault/src/ExternalAccessControl.sol)

- A shared access control contract for roles that span multiple vaults
- Currently used for: **SPENDER_ROLE** (share transfer exemption)
- All vaults reference the same `ExternalAccessControl` instance via immutable
- The SPENDER_ROLE is granted to addresses that can transfer shares even when `_transferable == false`

---

## 7. On-Chain Verification Checklist

For production validation (per Batch 16 methodology), each network requires:

### Factory Verification

- [ ] VaultFactory address is correct for network
- [ ] VaultUpgradeableBeacon address in factory storage matches deployed beacon
- [ ] ConnectorRegistry address in factory storage matches deployed registry
- [ ] FeeDispatcher address in factory storage matches deployed dispatcher
- [ ] Beacon's `implementation()` returns expected Vault implementation
- [ ] Vault implementation's `vaultFactory()` returns the factory address

### Connector Registry Verification

- [ ] All expected connectors are registered
- [ ] Connector addresses point to valid contracts
- [ ] No connectors are paused or frozen unexpectedly
- [ ] Connector implementations match source code (verified via bytecode)

### Vault Verification (per vault)

- [ ] Vault is in `_deployedVaults` array
- [ ] Vault is initialized (not stuck in uninitialized state)
- [ ] Correct connector name
- [ ] Correct asset
- [ ] Fee parameters within expected range
- [ ] Blocklist is deployed and operational
- [ ] FeeDispatcher is operational
- [ ] Vault's `vaultFactory` matches the deployed factory

### BlockList Verification

- [ ] BlockListFactory is deployed
- [ ] BlockListUpgradeableBeacon `implementation()` matches BlockList source
- [ ] Underlying sanctions list (Chainalysis) is set to correct address
- [ ] Active blocklist instances are operational
