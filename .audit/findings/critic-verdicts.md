# Critic Verdicts

## Summary

- Verified current-production bounty candidates: 0
- Conditional code-level candidates killed by deployment state: 1
- Other killed candidates: 2

## Killed After Production Review

### Compound V3 rewards can be pre-claimed by anyone, bricking later Claim-strategy distribution

Verdict: FALSE POSITIVE FOR CURRENT PRODUCTION SUBMISSION

The code-level trace is valid only when a Compound vault uses `AdditionalRewardsStrategy.Claim`.

Production check:

- All scoped active Compound vaults queried on Polygon, Base, Arbitrum, and Ethereum returned `additionalRewardsStrategy() == 2`.
- In `Vault.sol`, enum value `2` is `Reinvest`; enum value `1` is `Claim`.
- The exact impact in the candidate is Claim-strategy multisend distribution being skipped/reverted. That strategy is not active in current Compound production scope.

Residual note:

- Unprivileged Compound `claim(comet, vault, true)` is real and simulations succeeded on small owed Ethereum vaults.
- Current Reinvest strategy makes this operationally recoverable because pre-claimed COMP can still be swapped by the reinvest payload.

## Killed

### Aave reward asset / incentivized asset mismatch

Reason: insufficient current impact.

Aave expects `claimAllRewards(assets, to)` to receive incentivized assets. Kiln passes `rewardsAsset`. However, sampled non-zero scoped Ethereum Aave rewards were for the aToken itself, where passing `rewardsAsset` still works. No current bounty-grade impact was proven.

### Withdraw partial-share rounding candidate

Reason: duplicate / out of scope.

The earlier candidate around `_roundDownPartialShares()` is covered by Sigma Prime's DeFi Integrations report and is also a rounding-error issue, which the bounty excludes.
