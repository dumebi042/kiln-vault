# Batch 7 — Role Map

## Role Definitions

| Role                            | Contract                                                              | Identifier                          | Admin             | Global/Per-Vault                   | Functions                                                                   |
| ------------------------------- | --------------------------------------------------------------------- | ----------------------------------- | ----------------- | ---------------------------------- | --------------------------------------------------------------------------- |
| **DEFAULT_ADMIN_ROLE**          | All AccessControl contracts                                           | `0x00` (OZ default)                 | DefaultAdminRules | Per-contract                       | Grant/revoke all roles, transfer admin                                      |
| **FEE_MANAGER_ROLE**            | Vault                                                                 | `bytes32("FEE_MANAGER")`            | DEFAULT_ADMIN     | Per-Vault                          | `setDepositFee()`, `setRewardFee()`, `setFeeRecipients()`                   |
| **FEE_COLLECTOR_ROLE**          | Vault                                                                 | `bytes32("FEE_COLLECTOR")`          | DEFAULT_ADMIN     | Per-Vault                          | `collectRewardFees()`                                                       |
| **SANCTIONS_MANAGER_ROLE**      | Vault                                                                 | `bytes32("SANCTIONS_MANAGER")`      | DEFAULT_ADMIN     | Per-Vault                          | `setBlockList()`                                                            |
| **CLAIM_MANAGER_ROLE**          | Vault                                                                 | `bytes32("CLAIM_MANAGER")`          | DEFAULT_ADMIN     | Per-Vault                          | `claimAdditionalRewards()`, `setAdditionalRewardsStrategy()`                |
| **PAUSER_ROLE**                 | Vault, VaultUpgradeableBeacon, ConnectorRegistry                      | `bytes32("PAUSER")`                 | DEFAULT_ADMIN     | Per-contract                       | `pauseDeposit()`, `pause()`, `pauseFor()`                                   |
| **UNPAUSER_ROLE**               | Vault, VaultUpgradeableBeacon, ConnectorRegistry                      | `bytes32("UNPAUSER")`               | DEFAULT_ADMIN     | Per-contract                       | `unpauseDeposit()`, `unpause()`                                             |
| **FREEZER_ROLE**                | VaultUpgradeableBeacon, BlockListUpgradeableBeacon, ConnectorRegistry | `bytes32("FREEZER")`                | DEFAULT_ADMIN     | Per-contract                       | `freeze()`                                                                  |
| **CONNECTOR_MANAGER_ROLE**      | ConnectorRegistry                                                     | `bytes32("CONNECTOR_MANAGER")`      | DEFAULT_ADMIN     | Global (per registry)              | `add()`, `update()`, `remove()`                                             |
| **IMPLEMENTATION_MANAGER_ROLE** | VaultUpgradeableBeacon, BlockListUpgradeableBeacon                    | `bytes32("IMPLEMENTATION_MANAGER")` | DEFAULT_ADMIN     | Global                             | `upgradeTo()`                                                               |
| **DEPLOYER_ROLE**               | VaultFactory, BlockListFactory                                        | `bytes32("DEPLOYER")`               | DEFAULT_ADMIN     | Global (per factory)               | `createVault()`, `removeVault()`, `upgradeVault()`, `createBlockList()`     |
| **OPERATOR_ROLE**               | BlockList                                                             | `bytes32("OPERATOR")`               | DEFAULT_ADMIN     | Per-BlockList                      | `addToBlockList()`, `removeFromBlockList()`, `setUnderlyingSanctionsList()` |
| **SPENDER_ROLE**                | ExternalAccessControl                                                 | `bytes32("SPENDER")`                | DEFAULT_ADMIN     | Global (per ExternalAccessControl) | Bypass transfer restrictions                                                |

## Privilege Escalation Vectors

| Path                           | From                  | To            | Risk                                                               |
| ------------------------------ | --------------------- | ------------- | ------------------------------------------------------------------ |
| DEFAULT_ADMIN grants any role  | DEFAULT_ADMIN         | All roles     | Low — protected by DefaultAdminRules delay                         |
| FEE_MANAGER grants other roles | FEE_MANAGER           | —             | **None** — FEE_MANAGER cannot grant roles (only DEFAULT_ADMIN can) |
| PAUSER grants UNPAUSER         | PAUSER                | —             | **None** — PAUSER cannot grant roles                               |
| CONNECTOR_MANAGER → deployer   | ConnReg DEFAULT_ADMIN | DEPLOYER      | Low — same contract admin                                          |
| SPENDER in Vault A → Vault B   | ExternalAccessControl | Cross-vault   | **INTENTIONAL** — shared ExternalAccessControl                     |
| Old admin after transfer       | Old DEFAULT_ADMIN     | —             | **Mitigated** — DefaultAdminRules revokes old admin                |
| Pending admin front-run        | Pending admin         | DEFAULT_ADMIN | **Mitigated** — acceptance required                                |

## Role Storage Location

| Contract                   | Role Storage                                 | Shared Across Vaults?                             |
| -------------------------- | -------------------------------------------- | ------------------------------------------------- |
| Vault (per-proxy)          | OZ AccessControlUpgradeable (own storage)    | **No** — each Vault proxy has independent storage |
| VaultFactory               | OZ AccessControlDefaultAdminRules            | **Yes** — global to factory                       |
| ConnectorRegistry          | OZ AccessControlDefaultAdminRules            | **Yes** — global to registry                      |
| FeeDispatcher              | Uses `msg.sender` keyed storage              | **No** — vault-isolated by design                 |
| ExternalAccessControl      | OZ AccessControlDefaultAdminRulesUpgradeable | **Yes** — shared across all vaults using it       |
| BlockList (per-proxy)      | OZ AccessControlDefaultAdminRulesUpgradeable | **No** — per-blocklist proxy                      |
| BlockListFactory           | OZ AccessControlDefaultAdminRules            | **Yes** — global                                  |
| VaultUpgradeableBeacon     | OZ AccessControlDefaultAdminRules            | **Yes** — controls ALL vault implementations      |
| BlockListUpgradeableBeacon | OZ AccessControlDefaultAdminRules            | **Yes** — controls ALL blocklist implementations  |
