# Batch 7 — Factory and Beacon Authorization Review

## VaultFactory

| Function         | Role             | Can Revert On                |
| ---------------- | ---------------- | ---------------------------- |
| `createVault()`  | DEPLOYER_ROLE    | Non-deployer, zero addresses |
| `removeVault()`  | DEPLOYER_ROLE    | Wrong index, wrong vault     |
| `upgradeVault()` | DEPLOYER_ROLE    | Non-deployer                 |
| `initialize()`   | onlyDelegateCall | Direct call                  |

## VaultUpgradeableBeacon

| Function      | Role                   | Can Revert On                     |
| ------------- | ---------------------- | --------------------------------- |
| `upgradeTo()` | IMPLEMENTATION_MANAGER | Non-manager, frozen, non-contract |
| `pause()`     | PAUSER_ROLE            | Non-pauser                        |
| `pauseFor()`  | PAUSER_ROLE            | Duration zero                     |
| `unpause()`   | UNPAUSER_ROLE          | Not paused                        |
| `freeze()`    | FREEZER_ROLE           | Already frozen                    |

## Key Properties

- DEPLOYER_ROLE can create/remove/upgrade vaults
- IMPLEMENTATION_MANAGER can change ALL vault implementations
- CONNECTOR_MANAGER (in ConnectorRegistry) controls which connectors vaults use
- Only factory can call `initialize()` and `upgrade()` on vault proxies
- `delegateToFactory()` is factory-only and factory-validated

## Test Results

| Scenario                        | Result                       |
| ------------------------------- | ---------------------------- |
| Unauthorized createVault        | **Reverts**                  |
| Unauthorized upgradeTo (beacon) | **Reverts**                  |
| upgradeTo non-contract address  | **Reverts**                  |
| upgradeTo when frozen           | **Reverts**                  |
| Remove vault wrong index        | **Reverts**                  |
| Remove vault twice              | First OK, second **Reverts** |
