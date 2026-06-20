# Batch 7 — Role-Admin Graph

## Directed Graph

```
DEFAULT_ADMIN_ROLE (per-contract, DefaultAdminRules)
├── FEE_MANAGER_ROLE
├── FEE_COLLECTOR_ROLE
├── SANCTIONS_MANAGER_ROLE
├── CLAIM_MANAGER_ROLE
├── PAUSER_ROLE
├── UNPAUSER_ROLE
├── FREEZER_ROLE
├── CONNECTOR_MANAGER_ROLE (ConnectorRegistry only)
├── IMPLEMENTATION_MANAGER_ROLE (Beacons only)
├── DEPLOYER_ROLE (Factories only)
├── OPERATOR_ROLE (BlockList only)
└── SPENDER_ROLE (ExternalAccessControl only)
```

## Admin Rules

- Every operational role has `getRoleAdmin() == DEFAULT_ADMIN_ROLE` (0x00)
- DEFAULT_ADMIN_ROLE uses `AccessControlDefaultAdminRules` with configurable delay
- DEFAULT_ADMIN can grant/revoke any role
- No role can grant/revoke itself
- No operational role can grant any other role
- No role can grant DEFAULT_ADMIN_ROLE (OZ prevents this)

## Escalation Tests

| Test                                   | Result                                            |
| -------------------------------------- | ------------------------------------------------- |
| PAUSER grants UNPAUSER                 | **Impossible** — PAUSER is not admin of any role  |
| FEE_MANAGER grants CLAIM_MANAGER       | **Impossible** — FEE_MANAGER is not admin         |
| CONNECTOR_MANAGER grants DEFAULT_ADMIN | **Impossible**                                    |
| Old admin after acceptance             | **Revoked** — DefaultAdminRules transfers cleanly |
| New admin before acceptance            | **Cannot act** — pending status                   |
