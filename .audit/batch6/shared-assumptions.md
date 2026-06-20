# Shared Connector Assumptions

1. Connectors execute via `functionDelegateCall` — `address(this)` = vault proxy, `msg.sender` = original caller
2. Connectors must use only immutable variables (no storage) to avoid vault storage corruption
3. All 6 connectors follow this pattern correctly
4. Receipt tokens (aTokens, Comet balance, MetaMorpho shares) are held by vault proxy
5. Positions are tied to vault address, not connector address
6. `forceApprove` is used for all approvals (handles USDT-style tokens correctly)
7. Withdrawal return values are ignored — Vault uses balance-delta instead
8. Reward claim/reinvest functions are optional (revert if unsupported)
