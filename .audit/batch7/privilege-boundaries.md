# Batch 7 — Privilege Boundaries

## Summary

All operational roles are administered by DEFAULT_ADMIN via OZ's `AccessControlDefaultAdminRules`. Each Vault proxy has independent role storage. Global contracts (ConnectorRegistry, ExternalAccessControl, beacons, factories) have their own admin.

## Key Boundaries

### Vault-Local Roles (Per-Proxy)

Each Vault proxy stores its own:

- FEE_MANAGER_ROLE
- FEE_COLLECTOR_ROLE
- SANCTIONS_MANAGER_ROLE
- CLAIM_MANAGER_ROLE
- PAUSER_ROLE
- UNPAUSER_ROLE
- DEFAULT_ADMIN_ROLE

**Boundary**: A role granted in Vault A does NOT affect Vault B.

### Global Roles (Shared)

| Contract               | Roles                                             | Shared Impact                                               |
| ---------------------- | ------------------------------------------------- | ----------------------------------------------------------- |
| ConnectorRegistry      | CONNECTOR_MANAGER, PAUSER, UNPAUSER, FREEZER      | Controls connector state for ALL vaults using this registry |
| ExternalAccessControl  | SPENDER_ROLE, DEFAULT_ADMIN                       | Controls transfer exemptions for ALL vaults using this EAC  |
| VaultUpgradeableBeacon | IMPLEMENTATION_MANAGER, PAUSER, UNPAUSER, FREEZER | Controls ALL vault implementations                          |
| VaultFactory           | DEPLOYER_ROLE, DEFAULT_ADMIN                      | Controls vault creation/removal                             |

### FeeDispatcher Isolation

FeeDispatcher keys state by `msg.sender` (the Vault proxy address via delegatecall from `dispatchFees()`, or direct call from `setFeeRecipients()`). Each Vault has isolated fee state even though the dispatcher is shared.

## No Across-Boundary Escalation Found

No operational role in one Vault can affect another Vault's privileged state. The shared global contracts are designed to be shared (single ConnectorRegistry, single ExternalAccessControl per deployment).
