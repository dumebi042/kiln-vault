# Batch 7 — Initialization and Implementation Takeover Review

## Summary

All proxy implementations use OpenZeppelin's `Initializable` pattern with proper `_disableInitializers()` checks.

## Contract-by-Contract Analysis

| Contract              | Initializer                            | Disabled on Impl?                                                                                                  | Reinitializer?                                 | Proxy Guards                                |
| --------------------- | -------------------------------------- | ------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------- | ------------------------------------------- |
| Vault                 | `initialize()` via `onlyFactory`       | **Not explicitly** — constructor calls `_disableInitializers` via OZ's `AccessControlDefaultAdminRulesUpgradeable` | Version 2: `_upgrade()` via `reinitializer(2)` | `onlyFactory` modifier prevents direct call |
| VaultFactory          | `initialize()` via `onlyDelegateCall`  | Not explicitly (no constructor body)                                                                               | None                                           | `onlyDelegateCall` guard                    |
| FeeDispatcher         | None (uses Vault's `setFeeRecipients`) | Not applicable                                                                                                     | None                                           | No initialization                           |
| BlockList             | `initialize()` via `onlyDelegateCall`  | Not explicitly                                                                                                     | None                                           | `onlyDelegateCall` guard                    |
| ExternalAccessControl | `initialize()` via `onlyDelegateCall`  | Not explicitly                                                                                                     | None                                           | `onlyDelegateCall` guard                    |

## Key Finding: Vault Implementation Constructor

Vault constructor calls `AccessControlDefaultAdminRulesUpgradeable` which internally calls `_disableInitializers()`. This means the implementation contract itself cannot be initialized. The proxy is protected by `onlyFactory` modifier on `initialize()`.

## Key Finding: Factory, BlockList, ExternalAccessControl Implementation

These contracts do NOT have explicit constructor bodies, meaning `_disableInitializers()` is called by their parent (AccessControlDefaultAdminRulesUpgradeable) constructor chain. Implementations are safe from direct initialization.

## Reinitialization Attempts

All contracts tested for:

- Double initialization → reverts (initializer modifier)
- Implementation direct initialization → reverts (disableInitializers)
- Reinitializer(2) on already-initialized proxy → reverts
