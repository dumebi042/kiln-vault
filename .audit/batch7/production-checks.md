# Batch 7 — Production Checks

Deployment-specific. Requires on-chain queries. Key values to verify:

- VaultFactory admin
- ConnectorRegistry admin + role holders
- ExternalAccessControl SPENDER holders
- Active Vault default admin
- Beacon owner/IMPLEMENTATION_MANAGER
- BlockListFactory admin

Commands for on-chain verification would use `cast` or `chisel` against deployed contracts.
