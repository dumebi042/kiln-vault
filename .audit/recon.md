# Krait Recon - Kiln OmniVault

Date: 2026-06-19

## Source And Scope

- Bounty scope read from `kiln-v2-vault.md`.
- Production Solidity scope: `src/Vault.sol`, factories, beacons/proxies, blocklist/access control, `FeeDispatcher`, `ConnectorRegistry`, and scoped connectors.
- Repo source is reconstructed from scanner-verified deployed sources; flattened scanner exports are archived under `.audit/backups/src-flattened-20260619-164835`.
- `foundry.toml` uses Solidity `0.8.22` and remaps OpenZeppelin imports to scanner-provided `verified/lib`.

## Bounty Constraints Applied

- Privileged roles are trusted and privileged-role attacks are out of scope.
- Known external audit issues are not eligible.
- Rounding errors, design choices, and high gas observations are out of scope.
- Critical/High/Medium require PoC.

## Commands

- `bash /Users/dumebi/.codex/skills/krait/recon/ast-extract.sh . .audit/ast-facts.md`
- `slither . --json .audit/slither-results.json` produced scanner signal only.
- `forge test --match-path test/CompoundPreclaimPoC.t.sol -vv`
- `forge test --match-path test/invariant/VaultInvariant.t.sol -q`

## Architecture Notes

- Vaults delegatecall connector code, so connector `address(this)` resolves to the vault in production.
- `claimAdditionalRewards()` is `CLAIM_MANAGER_ROLE` gated, but reward protocols may expose permissionless claim functions that can mutate reward state before the claim manager acts.
- Compound V3 rewards are tracked by `(comet, src)` and `claim(comet, src, shouldAccrue)` pays rewards directly to `src` without checking caller permission.
- Aave V3 `claimAllRewards(assets, to)` expects incentivized assets such as aTokens/debt tokens. Current sampled scoped Ethereum Aave rewards with non-zero balances were aToken rewards, so Kiln's current parameter path works for those live balances.
