# Batch 4 — Connector Registry Transition Review

## How Registry Updates Work

The `ConnectorRegistry` maps a `bytes32 name` to a `ConnectorInfo {address, pauseTimestamp, frozen}`. When a vault calls `getOrRevert(name)`, it reads the current connector address for that name.

## Position Ownership

All assets are tied to the **Vault proxy address**, not the connector address:

- Receipt tokens (aTokens, MetaMorpho shares, sDAI) are held by the vault
- The external protocol tracks `balanceOf(vault)`
- When the connector delegatecalls, `address(this)` = vault proxy

## Compatible vs Incompatible Transitions

| Transition                            | Effect on Existing Positions                                                                                                                       | Recovery                          |
| ------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| Same connector type, same market      | **Transparent** — new connector reads same protocol state                                                                                          | None needed                       |
| Same connector type, different market | **Positions hidden** — old receipt tokens still held by vault, but new connector reads different market. totalAssets() reports 0 for old position. | Restore old connector to withdraw |
| Different connector type              | **Incompatible** — receipt token types differ (aToken vs MetaMorpho shares). New connector cannot interact with old position.                      | Restore old connector             |

## Risk

Updating to an incompatible connector requires CONNECTOR_MANAGER role. If done accidentally:

1. Existing positions become invisible to `totalAssets()`
2. Withdrawals fail (or report 0)
3. Recovery requires restoring the original connector

This is an admin power, not an unprivileged attack.
