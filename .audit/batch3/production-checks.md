# Batch 3 — Production Checks

## Production Beacon

**Network**: Ethereum Mainnet  
**VaultUpgradeableBeacon**: `0x0193BA8d74e8c7F51522a25F89C405691406eF20`  
**Older implementation (bounty page)**: `0x869855168858364368e62A5D1D092cc1dbD31f5a`

### To verify live configuration:

```bash
# Get current implementation from beacon
cast call 0x0193BA8d74e8c7F51522a25F89C405691406eF20 "implementation()" --rpc-url $ETH_RPC_URL

# Get VaultFactory from any vault
# Get VaultFactory storage to find deployed vaults
```

## Active Vault Configurations

Without on-chain access, we document the expected production configuration based on source code analysis and documented deployments.

### Expected Configuration Matrix

| Parameter                | Production Value              | Source                                           |
| ------------------------ | ----------------------------- | ------------------------------------------------ |
| `_offset`                | 6                             | Standard for USDC vaults; matches existing tests |
| `_minTotalSupply`        | Varies by vault               | Configurable during creation                     |
| `_depositFee`            | 0–35%                         | Configurable, max 35%                            |
| `_rewardFee`             | 0–35%                         | Configurable, max 35%                            |
| `_underlyingDecimals`    | 6 (USDC), 18 (ETH/wstETH/etc) | Asset-dependent                                  |
| `_externalAccessControl` | (one per deployment)          | Immutable in Vault impl                          |
| `vaultFactory`           | (one per deployment)          | Immutable in Vault impl                          |

### Connectors in Production

| Connector             | Expected Networks                           | Asset Type           |
| --------------------- | ------------------------------------------- | -------------------- |
| AaveV3Connector       | Ethereum, Polygon, Arbitrum, Base, Optimism | aTokens              |
| CompoundV3Connector   | Ethereum, Base                              | Comet base assets    |
| MetaMorphoConnector   | Ethereum                                    | ERC4626 vault shares |
| SDAIConnector         | Ethereum                                    | sDAI                 |
| SUSDSConnector        | Ethereum                                    | sUSDS                |
| AngleSavingsConnector | Ethereum                                    | agEUR/stEUR          |

## Production Verification Needed

For each candidate finding, production validation requires:

1. **Network**: Identify the network (Ethereum mainnet, Polygon, Arbitrum, etc.)
2. **Vault address**: Get from factory storage (`VaultFactory.getDeployedVaults()`)
3. **Implementation**: Via beacon (`VaultUpgradeableBeacon.implementation()`)
4. **Configuration**: Read VaultStorage for offset, fees, min supply
5. **Connector**: Current connector name and address from registry
6. **Asset address & decimals**: From Vault.asset() and token.decimals()

### Commands for Production Checks

```bash
# Using forge cast:
export ETH_RPC_URL="https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY"

# Get deployed vaults from factory
cast call $VAULT_FACTORY "getDeployedVaults()" --rpc-url $ETH_RPC_URL

# Read vault configuration (ERC7201 storage)
# VaultStorageLocation = 0x6bb5a2a0ae924c2ea94f037035a09f65614421e2a7d96c9bcbd59acdd32e6000
cast storage $VAULT_ADDR 0x6bb5a2a0ae924c2ea94f037035a09f65614421e2a7d96c9bcbd59acdd32e6000

# Get offset (packed in slot 5)
# Read slot 5 of VaultStorage
```

## Current Findings Needing Production Check

| Finding                      | Production Config Needed                     |
| ---------------------------- | -------------------------------------------- |
| First deposit fee capture    | Check if production vaults set rewardFee > 0 |
| Offset protection            | Verify offset ≥ 6 in production              |
| ForceWithdraw permissionless | Check which vaults have active blocklists    |
| Sanctions oracle dependency  | Check which networks use Chainalysis oracle  |
