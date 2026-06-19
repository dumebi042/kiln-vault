# Role Map — Kiln OmniVault

## Complete Privilege Matrix

### 1. Vault (AccessControlDefaultAdminRulesUpgradeable)

| Role                   | Role Value            | Grants                  | Functions Protected                                          | Notes                                                                                                         |
| ---------------------- | --------------------- | ----------------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------- |
| DEFAULT_ADMIN_ROLE     | `0x00`                | Full admin              | `grantRole`, `revokeRole`, `renounceRole`                    | Can manage all roles including itself. Dangerous if renounced.                                                |
| FEE_MANAGER_ROLE       | `"FEE_MANAGER"`       | Fee configuration       | `setFeeRecipients()`, `setDepositFee()`, `setRewardFee()`    | Controls fee rates and distribution. Can set up to 35% max.                                                   |
| FEE_COLLECTOR_ROLE     | `"FEE_COLLECTOR"`     | Reward fee collection   | `collectRewardFees()`                                        | Withdraws reward fees from protocol.                                                                          |
| SANCTIONS_MANAGER_ROLE | `"SANCTIONS_MANAGER"` | Blocklist management    | `setBlockList()`                                             | Can replace entire BlockList contract.                                                                        |
| CLAIM_MANAGER_ROLE     | `"CLAIM_MANAGER"`     | Claim/reward management | `claimAdditionalRewards()`, `setAdditionalRewardsStrategy()` | Controls reward claiming and strategy.                                                                        |
| PAUSER_ROLE            | `"PAUSER"`            | Deposit pausing         | `pauseDeposit()`                                             | Can pause all deposits.                                                                                       |
| UNPAUSER_ROLE          | `"UNPAUSER"`          | Deposit unpausing       | `unpauseDeposit()`                                           | Can unpause deposits.                                                                                         |
| SPENDER_ROLE           | `"SPENDER"`           | Transfer exemption      | (checked by `_checkTransferability()`)                       | Managed on **ExternalAccessControl**, not on Vault itself. Allows transfers when shares are non-transferable. |

**Role Management**: DEFAULT_ADMIN_ROLE manages all roles via `grantRole` / `revokeRole` (inherited OZ).

---

### 2. VaultFactory (AccessControlDefaultAdminRulesUpgradeable)

| Role               | Role Value   | Grants                     | Functions Protected                                |
| ------------------ | ------------ | -------------------------- | -------------------------------------------------- |
| DEFAULT_ADMIN_ROLE | `0x00`       | Full admin                 | Role management                                    |
| DEPLOYER_ROLE      | `"DEPLOYER"` | Vault deployment & upgrade | `createVault()`, `removeVault()`, `upgradeVault()` |

**Note**: VaultFactory is behind a UUPS proxy. The proxy admin can upgrade the factory implementation.

---

### 3. VaultUpgradeableBeacon (AccessControlDefaultAdminRules)

| Role                        | Role Value                 | Grants           | Functions Protected                                          |
| --------------------------- | -------------------------- | ---------------- | ------------------------------------------------------------ |
| DEFAULT_ADMIN_ROLE          | `0x00`                     | Full admin       | Role management                                              |
| IMPLEMENTATION_MANAGER_ROLE | `"IMPLEMENTATION_MANAGER"` | Beacon upgrade   | `upgradeTo()` — changes implementation for ALL vault proxies |
| PAUSER_ROLE                 | `"PAUSER"`                 | Beacon pausing   | `pause()`, `pauseFor()` — pauses ALL vault proxies           |
| UNPAUSER_ROLE               | `"UNPAUSER"`               | Beacon unpausing | `unpause()`                                                  |
| FREEZER_ROLE                | `"FREEZER"`                | Beacon freezing  | `freeze()` — permanently freezes beacon (irreversible)       |

---

### 4. ConnectorRegistry (AccessControlDefaultAdminRules)

| Role                   | Role Value            | Grants              | Functions Protected                                         |
| ---------------------- | --------------------- | ------------------- | ----------------------------------------------------------- |
| DEFAULT_ADMIN_ROLE     | `0x00`                | Full admin          | Role management                                             |
| CONNECTOR_MANAGER_ROLE | `"CONNECTOR_MANAGER"` | Connector lifecycle | `add()`, `update()`, `remove()`                             |
| PAUSER_ROLE            | `"PAUSER"`            | Connector pausing   | `pause()`, `pauseFor()` — pauses a specific connector       |
| UNPAUSER_ROLE          | `"UNPAUSER"`          | Connector unpausing | `unPause()`                                                 |
| FREEZER_ROLE           | `"FREEZER"`           | Connector freezing  | `freeze()` — permanently freezes a connector (irreversible) |

---

### 5. BlockList (AccessControlDefaultAdminRulesUpgradeable)

| Role               | Role Value   | Grants               | Functions Protected                                                         |
| ------------------ | ------------ | -------------------- | --------------------------------------------------------------------------- |
| DEFAULT_ADMIN_ROLE | `0x00`       | Full admin           | Role management                                                             |
| OPERATOR_ROLE      | `"OPERATOR"` | Blocklist management | `addToBlockList()`, `removeFromBlockList()`, `setUnderlyingSanctionsList()` |

---

### 6. BlockListUpgradeableBeacon (AccessControlDefaultAdminRules)

| Role                        | Role Value                 | Grants          | Functions Protected |
| --------------------------- | -------------------------- | --------------- | ------------------- |
| DEFAULT_ADMIN_ROLE          | `0x00`                     | Full admin      | Role management     |
| IMPLEMENTATION_MANAGER_ROLE | `"IMPLEMENTATION_MANAGER"` | Beacon upgrade  | `upgradeTo()`       |
| FREEZER_ROLE                | `"FREEZER"`                | Beacon freezing | `freeze()`          |

---

### 7. BlockListFactory (AccessControlDefaultAdminRules)

| Role               | Role Value   | Grants               | Functions Protected |
| ------------------ | ------------ | -------------------- | ------------------- |
| DEFAULT_ADMIN_ROLE | `0x00`       | Full admin           | Role management     |
| DEPLOYER_ROLE      | `"DEPLOYER"` | BlockList deployment | `createBlockList()` |

---

### 8. ExternalAccessControl (AccessControlDefaultAdminRulesUpgradeable)

| Role               | Role Value      | Grants       | Functions Protected              |
| ------------------ | --------------- | ------------ | -------------------------------- |
| DEFAULT_ADMIN_ROLE | `0x00`          | Full admin   | Role management                  |
| _(any custom)_     | set during init | Role-defined | Vault's SPENDER_ROLE stored here |

---

## Cross-Contract Authorization Map

| Protected Action     | Calls                                                | Ultimately Requires                   | Delegation Chain                                           |
| -------------------- | ---------------------------------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| Deploy vault         | `VaultFactory.createVault()`                         | DEPLOYER_ROLE on VaultFactory         | Direct                                                     |
| Initialize vault     | `Vault.initialize()`                                 | onlyFactory                           | Checked: `msg.sender == vaultFactory`                      |
| Upgrade vault        | `Vault.upgrade()`                                    | onlyFactory                           | Via `VaultFactory.upgradeVault()` → requires DEPLOYER_ROLE |
| Upgrade beacon       | `VaultUpgradeableBeacon.upgradeTo()`                 | IMPLEMENTATION_MANAGER_ROLE on beacon | Direct                                                     |
| Change connector     | `ConnectorRegistry.update()`                         | CONNECTOR_MANAGER_ROLE on registry    | Direct                                                     |
| Freeze connector     | `ConnectorRegistry.freeze()`                         | FREEZER_ROLE on registry              | Direct                                                     |
| Pause deposits       | `Vault.pauseDeposit()`                               | PAUSER_ROLE on Vault                  | Direct                                                     |
| Claim rewards        | `Vault.claimAdditionalRewards()`                     | CLAIM_MANAGER_ROLE on Vault           | Direct                                                     |
| Collect fees         | `Vault.collectRewardFees()`                          | FEE_COLLECTOR_ROLE on Vault           | Direct                                                     |
| Set fee recipients   | `Vault.setFeeRecipients()`                           | FEE_MANAGER_ROLE on Vault             | Direct                                                     |
| Set blocklist        | `Vault.setBlockList()`                               | SANCTIONS_MANAGER_ROLE on Vault       | Direct                                                     |
| Block user           | `BlockList.addToBlockList()`                         | OPERATOR_ROLE on BlockList            | Direct                                                     |
| Force withdraw       | `Vault.forceWithdraw()`                              | _(no role check)_                     | Public, but guarded by blocklist checks                    |
| Beacon delegate call | `Vault.delegateToFactory()`                          | onlyFactory                           | Restricted to VaultFactory                                 |
| Self-delegate        | `ISelf(vaultFactory)._self().functionDelegateCall()` | onlyFactory on Vault                  | Via `delegateToFactory`                                    |

---

## Role Conflict Analysis

### Risk: Same entity holds multiple critical roles

| Combination                                            | Risk Severity | Impact                                                          |
| ------------------------------------------------------ | ------------- | --------------------------------------------------------------- |
| DEFAULT_ADMIN + DEPLOYER on Factory                    | High          | Can deploy vaults, manage roles, and upgrade factory            |
| IMPLEMENTATION_MANAGER on beacon + DEPLOYER on factory | Critical      | Can change implementation AND trigger upgrade on all vaults     |
| PAUSER + UNPAUSER + FEE_MANAGER on Vault               | Medium        | Can pause deposits and change fees simultaneously               |
| CONNECTOR_MANAGER + FREEZER on Registry                | High          | Can add malicious connector AND prevent anyone from updating it |
| OPERATOR on BlockList + SANCTIONS_MANAGER on Vault     | High          | Can block users AND replace the blocklist contract              |

### Risk: Renounced roles

| Role                              | Impact if Renounced                | Recovery Path                                                   |
| --------------------------------- | ---------------------------------- | --------------------------------------------------------------- |
| DEFAULT_ADMIN_ROLE (any contract) | No role management possible        | None (unless AccessControlDefaultAdminRules delay admin exists) |
| DEPLOYER_ROLE (Factory)           | Can't deploy new vaults            | Only DEFAULT_ADMIN can regrant                                  |
| CONNECTOR_MANAGER_ROLE (Registry) | Can't add/update/remove connectors | Only DEFAULT_ADMIN can regrant                                  |
| OPERATOR_ROLE (BlockList)         | Can't manage blocklist             | Only DEFAULT_ADMIN can regrant                                  |

---

## AccessControlDefaultAdminRules Delay Analysis

| Contract                   | Delay Admin Scheme                          | Notes                                                                      |
| -------------------------- | ------------------------------------------- | -------------------------------------------------------------------------- |
| Vault                      | `AccessControlDefaultAdminRulesUpgradeable` | Has delay; access delay configured in `InitializationParams.initialDelay_` |
| VaultFactory               | `AccessControlDefaultAdminRulesUpgradeable` | Has delay; configured in `InitializationParams.initialDelay_`              |
| VaultUpgradeableBeacon     | `AccessControlDefaultAdminRules`            | Has delay; configured in constructor `initialDelay`                        |
| ConnectorRegistry          | `AccessControlDefaultAdminRules`            | Has delay; configured in constructor                                       |
| BlockList                  | `AccessControlDefaultAdminRulesUpgradeable` | Has delay; configured in init params                                       |
| BlockListUpgradeableBeacon | `AccessControlDefaultAdminRules`            | Has delay; configured in constructor                                       |
| BlockListFactory           | `AccessControlDefaultAdminRules`            | Has delay; configured in constructor                                       |
| ExternalAccessControl      | `AccessControlDefaultAdminRulesUpgradeable` | Has delay; configured in init params                                       |
| FeeDispatcher              | _(none — ReentrancyGuardUpgradeable only)_  | No access control                                                          |

---

## Privilege Escalation Vectors

1. **DEFAULT_ADMIN_ROLE on any contract**: Can grant itself any role via `grantRole()`, then use that role.
2. **VaultFactory proxy upgrade**: A malicious factory implementation could deploy vaults pointing to a malicious beacon.
3. **VaultUpgradeableBeacon implementation change**: Changes logic for ALL vaults instantly.
4. **BlockList replacement via `setBlockList()`**: New blocklist could have different rules.
5. **Connector update during operation**: `ConnectorRegistry.update()` changes the address an existing vault resolves to.
