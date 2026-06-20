# Batch 7 — Sanctions and Blocklist Role Review

## Role Map

| Role                   | Contract  | Functions                                                                   |
| ---------------------- | --------- | --------------------------------------------------------------------------- |
| SANCTIONS_MANAGER_ROLE | Vault     | `setBlockList()`                                                            |
| OPERATOR_ROLE          | BlockList | `addToBlockList()`, `removeFromBlockList()`, `setUnderlyingSanctionsList()` |
| None                   | Vault     | `forceWithdraw()` — **permissionless**                                      |

## Key Properties

- SANCTIONS_MANAGER can swap the entire BlockList contract for a Vault
- OPERATOR manages the blocklist entries
- `forceWithdraw()` requires user to be internally blocked AND not OFAC-sanctioned
- Blocked user can be force-withdrawn by ANYONE (permissionless)

## SANCTIONS_MANAGER Power Analysis

SANCTIONS_MANAGER can:

- Replace the BlockList contract → affecting all future `isBlocked()` checks
- NOT directly steal funds (forceWithdraw sends to blocked user)
- NOT redirect forceWithdraw proceeds (proceeds go to blocked user)

## OPERATOR Power Analysis

OPERATOR can:

- Add/remove addresses from blocklist
- Replace underlying sanctions oracle
- NOT steal funds (cannot call forceWithdraw or redirect)
- NOT affect FeeDispatcher or Vault accounting

## Separation Tests

| Scenario                                          | Result                                  |
| ------------------------------------------------- | --------------------------------------- |
| SANCTIONS_MANAGER replaces BlockList              | **OK**                                  |
| SANCTIONS_MANAGER adds to blocklist               | **Reverts** (no OPERATOR role)          |
| OPERATOR adds to blocklist                        | **OK**                                  |
| OPERATOR replaces BlockList                       | **Reverts** (no SANCTIONS_MANAGER role) |
| Permissionless forceWithdraw on non-blocked user  | **Reverts**                             |
| Permissionless forceWithdraw on blocked+OFAC user | **Reverts** (sanctioned)                |
