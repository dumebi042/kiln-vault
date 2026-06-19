# Deployed Code and Duplicate Check

Date: 2026-06-19

## Bounty Scope Read

- The bounty doc lists the Ethereum Vault implementation at `0x869855168858364368e62A5D1D092cc1dbD31f5a`, the VaultUpgradeableBeacon at `0x15f7f910e5a8c86e609fd11c58f7342d86d3a25c`, and core contract implementations/proxies in scope.
- Active vaults across supported networks are in scope when not paused, and the mainnet Kiln core/connectors are provided as reference.
- Known issues listed in external audits are not reward-eligible.
- "Rounding errors" are explicitly out of scope.

## Deployed Code Alignment

Sourcify has a partial match for the Vault implementation:

- Address: `0x869855168858364368e62A5D1D092cc1dbD31f5a`
- Compiler: `0.8.22+commit.4fc1097e`
- Target: `src/Vault.sol:Vault`
- Metadata source hash for `src/Vault.sol`: `0xa689ee09c6244df0d20b4759d3dc0a4929cbc714a715df0c48efa12cbedd3d14`

On-chain checks:

- `VaultUpgradeableBeacon.implementation()` returns `0x0193BA8d74e8c7F51522a25F89C405691406eF20`, so the beacon has been upgraded away from the bounty-doc implementation address.
- The bounty-doc Vault implementation address still has deployed bytecode and `vaultFactory()` returns `0xe175F13eB9383bCC61822Ca17ecB02038b00030D`.
- The current beacon implementation also returns `vaultFactory() = 0xe175F13eB9383bCC61822Ca17ecB02038b00030D`.
- Runtime bytecode length is identical for the bounty-doc implementation and current beacon implementation (`48206` hex chars), but hashes differ at embedded immutable-address sites and metadata. The active implementation source body still matches local `src/Vault.sol`; active-deployment traces must use the active implementation immutables.
- Sourcify has a partial source match for the bounty-doc implementation, but not for the current beacon implementation address.

Local source notes:

- `src/` files are flattened and include dependencies.
- `extracted/` files are contract-body extracts plus trailing dependency fragments, so file hashes differ from Sourcify source files.
- The relevant Vault logic in local `src/Vault.sol`, local `extracted/Vault.sol`, and the Sourcify source all matches for `previewWithdraw`, `withdraw`, `_roundDownPartialShares`, `_setOffset`, and `VaultFactory.createVault`.

Fresh scanner pull on 2026-06-19:

- `cast source` returned non-empty source for every bounty-table core and connector address queried.
- Sourcify `files/any` returned full or partial source for 22 bounty-table addresses.
- Contract-body matching was performed against the local `src/*.sol` files, so flattened dependency/import differences do not count as matches by themselves.

Exact contract-body matches confirmed against scanner source for the core contracts:

| Contract | Local body | Deployed/source body status |
| --- | --- | --- |
| Vault | `extracted/Vault.sol` | MATCH |
| VaultFactory | `extracted/VaultFactory.sol` | MATCH |
| ExternalAccessControl | `extracted/ExternalAccessControl.sol` | MATCH |
| FeeDispatcher | `extracted/FeeDispatcher.sol` | MATCH |
| BlockList | `extracted/BlockList.sol` | MATCH |
| BlockListFactory | `extracted/BlockListFactory.sol` | MATCH |

Exact contract-body matches confirmed against scanner source for the mainnet registry and connector implementations:

| Contract / deployed label | Local body | Scanner status |
| --- | --- | --- |
| ConnectorRegistry | `src/ConnectorRegistry.sol` | Sourcify full MATCH; Etherscan MATCH |
| AaveV3Connector | `src/AaveV3Connector.sol` | Sourcify full MATCH; Etherscan MATCH |
| CompoundV3Connector | `src/CompoundV3Connector.sol` | Sourcify full MATCH; Etherscan MATCH |
| SDAIConnector | `src/SDAIConnector.sol` | Sourcify full MATCH; Etherscan MATCH |
| SUSDSConnector | `src/SUSDSConnector.sol` | Sourcify full MATCH; Etherscan MATCH |
| AngleSavingConnector STUSD | `src/AngleSavingConnector.sol` | Sourcify full MATCH; Etherscan MATCH |
| AngleSavingConnector STEUR | `src/AngleSavingConnector.sol` | Etherscan MATCH |
| MetamorphoConnector USDC / USDT / USDA / USDC Prime / USDT Prime | `src/MetamorphoConnector.sol` | Sourcify full MATCH; Etherscan MATCH |
| MetamorphoConnector LBTC Core / ETH | `src/MetamorphoConnector.sol` | Etherscan MATCH |

Current deployment note:

- `VaultUpgradeableBeacon.implementation()` currently returns `0x0193BA8d74e8c7F51522a25F89C405691406eF20`.
- `cast source` for the active implementation body matches local `src/Vault.sol` (`Vault` body hash `a44e1757b58eda37`).
- The active implementation and the bounty-table implementation have the same runtime length but differ at embedded immutable-address sites and metadata. The active implementation embeds the ExternalAccessControl proxy (`0x0C7cEef7C99a2F32b5b93F048E65d076b22ABA1E`) and the VaultFactory proxy (`0xe175F13eB9383bCC61822Ca17ecB02038b00030D`), so active-deployment traces should use the active implementation semantics.

Conclusion: the local repo is suitable for reviewing the deployed core, registry, and mainnet connector implementation logic listed above. Active Vault traces should use the active beacon implementation (`0x0193...`) rather than assuming the bounty-table implementation immutables.

## Duplicate / Eligibility Review

Candidate reviewed:

- `KRAIT-001`: `withdraw` can burn zero shares after rounding required shares down.

The candidate is not suitable for bounty submission:

- Sigma Prime's DeFi Integrations assessment documents the partial-share interaction in `Vault.sol`.
- The report says the resolution in PR#221 added `_roundDownPartialShares()`.
- It explicitly states that the change was applied to `previewDeposit()`, `previewWithdraw()`, and `withdraw()`.
- The bounty doc excludes "Rounding errors".
- Sampled live Ethereum vaults had offset 0; the zero-burn trace requires `_offset > 0`.

Final decision: **do not submit KRAIT-001**.
