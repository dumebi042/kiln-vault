# Detector Candidates

## CAND-001 - Compound V3 rewards can be pre-claimed by anyone, bricking later Claim-strategy distribution

Status: promoted to critic

Affected file: `src/connectors/CompoundV3Connector.sol`

Trace:

1. A scoped Compound vault accrues COMP rewards in Compound's `CometRewards`.
2. Any address calls `CometRewards.claim(comet, vault, true)`.
3. Compound transfers the owed COMP to the vault and marks the rewards claimed.
4. Kiln's claim manager later calls `Vault.claimAdditionalRewards(COMP, payload)`.
5. `CompoundV3Connector.claim()` snapshots the vault's COMP balance, calls `cometRewards.claim(_comet, address(this), true)`, receives no new COMP, computes `_received == 0`, and reverts `NothingToClaim()`.
6. In Claim strategy, the already-transferred COMP is not multisend-distributed to recipients.

Live scope:

- Deployed connector: `0xbeaa30DCB697CFFB64E319A3Fc4b0688Be5aE790`.
- Deployed `cometRewards`: `0x1B0e765F6224C21223AeA2af16c1C46E38885a40`.
- Deployed `compoundMarketRegistry`: `0x08f80358Ce68363Ec06304cE667F1727246C852D`.
- Deployed `comp`: `0xc00e94Cb662C3520282E6f5717214004A7f26888`.

Sampled live owed COMP on Ethereum scoped vaults:

- `0xB9E62Cb9b4cE8ec13c886FaE67369Da417EE2714`: `13.098686 COMP`.
- `0x804EE40b227B9003BB7bf2880cF502466544F208`: `0.42853 COMP`.
- `0x96D595D35a0203d6e218852190b3E981ADEeab0B`: `0.000108 COMP`.
- `0x754A34e2f4582925F5E384c371f78db01A869572`: `0.000057 COMP`.

PoC: `test/CompoundPreclaimPoC.t.sol`.

## CAND-002 - Aave reward asset / incentivized asset mismatch

Status: killed

`AaveV3Connector.claim()` passes `rewardsAsset` as the `assets[]` parameter to Aave `claimAllRewards()`. Aave expects incentivized assets such as aTokens/debt tokens, not an arbitrary reward token.

This is a real integration footgun for future/non-sampled reward configurations, but current sampled non-zero scoped Ethereum Aave rewards were aToken rewards where `rewardsAsset == aToken`, so the path works for the live value at risk observed in scope. No bounty-ready current impact was proven.
