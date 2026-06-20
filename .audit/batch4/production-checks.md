# Batch 4 — Production Checks

## Connector Production Analysis

### Aave V3

- **Mainnet Pool**: `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`
- **PoolAddressesProvider**: `0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e`
- **Withdrawal behavior**: `withdraw()` reverts on insufficient liquidity. Returns actual withdrawn amount. Return value is ignored by Vault (balance-delta used instead).
- **Short return risk**: None.

### Compound V3

- **USDC Comet (Mainnet)**: `0xc3d688B66703497DAA19211EEdff47f25384cdc3`
- **Withdrawal behavior**: `withdraw()` reverts if insufficient base asset available.
- **Short return risk**: None.

### MetaMorpho

- **Withdrawal behavior**: ERC4626 `withdraw()` guarantees exact output or reverts.
- **Short return risk**: None (but `maxWithdraw` may be stale — safe).

### sDAI / sUSDS

- **Withdrawal behavior**: Exact ERC4626 conversion. Returns exact DAI/USDS or reverts.
- **Short return risk**: None.

### Angle Savings

- **Withdrawal behavior**: Same as ERC4626.
- **Short return risk**: None.

## B4-002 Production Applicability Verdict

After analyzing all 6 connectors: **No production connector can succeed while returning less than requested.** All connectors either revert on failure or deliver the exact requested amount. The short-withdrawal vulnerability (B4-002) cannot be triggered by any in-scope connector without admin privilege (malicious connector registration).

## Active Vault Verification Commands

```bash
# Get implementation from beacon
cast call 0x0193BA8d74e8c7F51522a25F89C405691406eF20 "implementation()" --rpc-url $ETH_RPC_URL

# Read connector registry
# VaultStorage slot at 0x6bb5a2a0... contains _connectorRegistry and _connectorName
```
