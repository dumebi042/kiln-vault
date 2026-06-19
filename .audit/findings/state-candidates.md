# State Candidates

## STATE-001 - Compound reward claimed state can diverge from Kiln distribution state

Status: promoted to critic

Coupled state:

- Compound: `rewardsClaimed[comet][vault]`.
- Vault token balance: COMP already held by the vault after a permissionless pre-claim.
- Kiln distribution state: no multisend has occurred because `CompoundV3Connector.claim()` only distributes `_received`, where `_received = balanceAfter - balanceBefore`.

Mutation mismatch:

- External Compound claim mutates Compound reward state and vault COMP balance.
- Later Kiln Claim strategy expects the Compound claim call itself to create a positive balance delta.
- If the delta is zero, the connector reverts before distributing the already-present COMP balance.

Impact:

- Claim-strategy reward distribution can be griefed by an unprivileged caller for live scoped Compound vaults with owed COMP.
- Manual operational recovery may be possible by changing strategy and reinvesting, so this is treated as Medium rather than High.

## STATE-002 - Vault core accounting

Status: clean

The Vault-accounting sub-agent found no bounty-grade issue in ERC4626 accounting, reward-fee accrual, deposit fees, `collectRewardFees`, connector liquidity caps, or `forceWithdraw`. The focused invariant suite passed.
