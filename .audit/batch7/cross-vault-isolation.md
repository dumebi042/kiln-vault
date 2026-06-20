# Batch 7 — Cross-Vault Role Isolation

## Architecture

Each Vault proxy uses `AccessControlDefaultAdminRulesUpgradeable` which stores roles in the Vault's own storage slot (ERC-7201 or OZ default slot). Two Vaults deployed from the same factory have completely independent role storage.

## Shared Contracts

| Contract               | Shared?             | Cross-Vault Impact                                                   |
| ---------------------- | ------------------- | -------------------------------------------------------------------- |
| ExternalAccessControl  | **Yes** — singleton | SPENDER_ROLE is GLOBAL — applies to ALL vaults using this EAC        |
| ConnectorRegistry      | **Yes** — singleton | CONNECTOR_MANAGER, PAUSER, FREEZER affect ALL vaults' connectors     |
| FeeDispatcher          | **Yes** — singleton | Storage keyed by `msg.sender` (vault address), so naturally isolated |
| VaultUpgradeableBeacon | **Yes** — singleton | IMPLEMENTATION_MANAGER affects ALL vaults                            |
| VaultFactory           | **Yes** — singleton | DEPLOYER_ROLE is factory-scoped                                      |

## Test Results

| Scenario                                               | Result                                     |
| ------------------------------------------------------ | ------------------------------------------ |
| FEE_MANAGER in Vault A → modify Vault B fees           | **Reverts** — roles are per-Vault          |
| PAUSER in Vault A → pause Vault B deposits             | **Reverts**                                |
| CLAIM_MANAGER in Vault A → claim on Vault B            | **Reverts**                                |
| SPENDER in ExternalAccessControl → transfer on Vault A | **SUCCEEDS** (intentional — global)        |
| SPENDER in ExternalAccessControl → transfer on Vault B | **SUCCEEDS** (intentional — global)        |
| CONNECTOR_MANAGER → pause connector for Vault A        | **SUCCEEDS** (global — affects all vaults) |

## Conclusion

Vault-local roles are properly isolated. SPENDER_ROLE and connector roles are intentionally global.
