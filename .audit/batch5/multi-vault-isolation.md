# Multi-Vault Isolation

## How Isolation Works

FeeDispatcher uses `_dispatches[msg.sender]` for all state: pending fees, recipients, dispatch. Each vault's state is cryptographically isolated by the vault's address as the mapping key.

## Verified Properties

- Vault A cannot read Vault B's pending fees
- Vault A cannot modify Vault B's state
- Vault A cannot dispatch Vault B's fees
- EOA callers create their own isolated state (harmless)
- No cross-vault fee theft possible
