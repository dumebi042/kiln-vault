# Batch 4 — Connector State Map

## Connector Storage Architecture

All connectors use **only immutable variables** — no storage state. This is critical because connectors execute via `functionDelegateCall`, which would map any connector storage to vault storage.

| Connector            | Immutables                                                 | Storage Writes During Execution     |
| -------------------- | ---------------------------------------------------------- | ----------------------------------- |
| AaveV3Connector      | aave, rewardsController, swapTarget, poolAddressesProvider | None (external protocol calls only) |
| CompoundV3Connector  | compoundMarketRegistry, cometRewards, swapTarget, comp     | None                                |
| MetamorphoConnector  | metamorpho                                                 | None                                |
| SDAIConnector        | sDAI                                                       | None                                |
| SUSDSConnector       | sUSDS                                                      | None                                |
| AngleSavingConnector | stakingVault                                               | None                                |

## Delegatecall Context Summary

For ALL connectors:

| Context                          | Value                                               |
| -------------------------------- | --------------------------------------------------- |
| `address(this)` inside connector | Vault proxy address                                 |
| `msg.sender` inside connector    | Original user (deposit/withdraw caller)             |
| Storage writes                   | Vault proxy storage (at connector's slot positions) |
| External calls                   | Regular external calls (not delegatecalls)          |

## Who Holds What

| Asset Type                          | Held By                                  | After                             |
| ----------------------------------- | ---------------------------------------- | --------------------------------- |
| Underlying tokens (USDC, DAI, etc.) | Vault proxy → then sent to protocol      | Vault proxy holds receipt tokens  |
| aTokens (Aave)                      | Vault proxy (credited by Aave pool)      | Vault proxy                       |
| Comet balance (Compound)            | Vault proxy (tracked by Comet)           | Vault proxy                       |
| MetaMorpho/sDAI/sUSDS/Angle shares  | Vault proxy (credited by external vault) | Vault proxy                       |
| Reward tokens                       | Vault proxy (claimed by connector)       | Vault proxy or sent to recipients |
| Fee tokens (pending)                | Vault proxy (idle balance)               | Dispatched to fee recipients      |
