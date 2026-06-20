# Batch 7 — Access Control Candidates

## Summary

| ID     | Title                                                                  | Severity | Classification                                     |
| ------ | ---------------------------------------------------------------------- | -------- | -------------------------------------------------- |
| B7-001 | SPENDER_ROLE is global across all vaults sharing ExternalAccessControl | Info     | **EXPECTED BEHAVIOR**                              |
| B7-002 | forceWithdraw is permissionless with no role check                     | Low      | **EXPECTED BEHAVIOR** (already analyzed in B2-008) |
| B7-003 | Vault roles are per-Vault, properly isolated                           | N/A      | **EXPECTED BEHAVIOR**                              |
| B7-004 | Role-admin graph is flat — all roles admin'd by DEFAULT_ADMIN          | N/A      | **EXPECTED BEHAVIOR**                              |
| B7-005 | PAUSER/UNPAUSER are strictly separated                                 | N/A      | **EXPECTED BEHAVIOR**                              |
| B7-006 | Frozen connector cannot be updated/removed                             | N/A      | **EXPECTED BEHAVIOR**                              |
| B7-007 | FeeDispatcher uses msg.sender keying for Vault isolation               | N/A      | **EXPECTED BEHAVIOR**                              |
| B7-008 | ExternalAccessControl SPENDER_ROLE only bypasses transferable flag     | N/A      | **EXPECTED BEHAVIOR**                              |

**No VALID vulnerabilities found.** All access-control mechanisms are properly structured with:

- Flat role-admin graph (all roles → DEFAULT_ADMIN)
- DefaultAdminRules protection for admin transfer
- Vault-local roles per-proxy
- Separate PAUSER/UNPAUSER roles
- Frozen protection against CONNECTOR_MANAGER override
- FeeDispatcher msg.sender isolation
