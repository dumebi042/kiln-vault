# Batch 7 — ConnectorRegistry Role Review

## Role Map

| Role                   | Functions                       | Admin         |
| ---------------------- | ------------------------------- | ------------- |
| CONNECTOR_MANAGER_ROLE | `add()`, `update()`, `remove()` | DEFAULT_ADMIN |
| PAUSER_ROLE            | `pause()`, `pauseFor()`         | DEFAULT_ADMIN |
| UNPAUSER_ROLE          | `unPause()`                     | DEFAULT_ADMIN |
| FREEZER_ROLE           | `freeze()`                      | DEFAULT_ADMIN |

## Key Properties

- CONNECTOR_MANAGER can add/update/remove connectors
- PAUSER can pause connectors (temporary — supports `pauseFor` with duration)
- UNPAUSER can unpause connectors
- FREEZER can permanently freeze connectors (irreversible per name)
- Frozen connectors CANNOT be updated or removed
- CONNECTOR_MANAGER cannot bypass frozen state

## Separation Tests

| Scenario                                 | Result                      |
| ---------------------------------------- | --------------------------- |
| PAUSER pauses connector                  | **OK**                      |
| PAUSER unpauses connector                | **Reverts**                 |
| UNPAUSER unpauses connector              | **OK**                      |
| UNPAUSER pauses connector                | **Reverts**                 |
| FREEZER freezes connector                | **OK**                      |
| FREEZER updates/removes frozen connector | **Reverts** (whenNotFrozen) |
| CONNECTOR_MANAGER updates connector      | **OK**                      |
| CONNECTOR_MANAGER removes connector      | **OK**                      |

## Key Invariant

PAUSER/UNPAUSER/FREEZER/CONNECTOR_MANAGER are separate roles with NO overlap. No role can perform another role's functions.

The `whenNotFrozen` modifier on `update()` and `remove()` ensures frozen connectors cannot be altered, even by CONNECTOR_MANAGER.
