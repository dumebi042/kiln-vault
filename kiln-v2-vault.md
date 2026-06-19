# Kiln OmniVault Bounty

## [Instructions](https://cantina.xyz/bounties/c9a4b51b-2e80-4713-a06f-13524c530fa6?overviewTab=0&assetGroup=0)

Kiln OmniVault enables non-custodial platforms to propose DeFi yield products (like lending supply or rwa distributor) where users can deposit any amount of ERC20 on a vault while remaining the only one able to access their staked assets.

The goal of these EVM Smart Contracts is to enable:

* Users to deposit to supported protocols with a common 4626 interface  
* Enable Integrators, and any third parties enabled by the integrator to have a fee on the rewards generated or on the deposit, dispatched on-chain

This Bug Bounty is focused on Kiln OmniVault Smart Contracts only, all items regarding dApps or indexing / reporting stacks are out of scope but can be submitted at security@kiln.fi.

For more information about Kiln OmniVault, please visit [https://www.kiln.fi/omnivault](https://www.kiln.fi/omnivault)

## Smart Contracts in Scope

* Core Contracts

| Name | Address |
| ----- | ----- |
| Vault (Implementation) | [0x869855168858364368e62A5D1D092cc1dbD31f5a](https://etherscan.io/address/0x869855168858364368e62A5D1D092cc1dbD31f5a) |
| VaultUpgradeableBeacon | [0x15f7f910e5a8c86e609fd11c58f7342d86d3a25c](https://etherscan.io/address/0x15f7f910e5a8c86e609fd11c58f7342d86d3a25c) |
| ConnectorRegistry | [0xdE63817c82e93499357aE198518f90Ac1bE93A72](https://etherscan.io/address/0xdE63817c82e93499357aE198518f90Ac1bE93A72) |
| VaultFactory (TUP) | [0xe175F13eB9383bCC61822Ca17ecB02038b00030D](https://etherscan.io/address/0xe175F13eB9383bCC61822Ca17ecB02038b00030D) |
| VaultFactory (Implementation) | [0x4A1Ede66750e8e44a1569A4Af3F53fb31De3Dd32](https://etherscan.io/address/0x4A1Ede66750e8e44a1569A4Af3F53fb31De3Dd32) |
| ExternalAccessControl (TUP) | [0x0C7cEef7C99a2F32b5b93F048E65d076b22ABA1E](https://etherscan.io/address/0x0C7cEef7C99a2F32b5b93F048E65d076b22ABA1E) |
| ExternalAccessControl (Implementation) | [0x533DD3A719968Dba0cf454C2B2a692d196DF3605](https://etherscan.io/address/0x533DD3A719968Dba0cf454C2B2a692d196DF3605) |
| FeeDispatcher (TUP) | [0x034771103Dc1e9b1f2ebDA95896FC44B6D63eDc7](https://etherscan.io/address/0x034771103Dc1e9b1f2ebDA95896FC44B6D63eDc7) |
| FeeDispatcher (Implementation) | [0x637F9D0E032EFb98fe8Ae55C6D798FD54060Be04](https://etherscan.io/address/0x637F9D0E032EFb98fe8Ae55C6D798FD54060Be04) |
| BlockList (Implementation) | [0x7e7F84Da187117e06AbB03E1454E07Af42D0E4BE](https://etherscan.io/address/0x7e7F84Da187117e06AbB03E1454E07Af42D0E4BE) |
| BlockListFactory | [0x0d87F2834b4766CAf25aD5dBE193BEd70f5D9458](https://etherscan.io/address/0x0d87F2834b4766CAf25aD5dBE193BEd70f5D9458) |
| BlockListUpgradeableBeacon | [0xB58700939159Db7a47b64FF74cF98150AccBF904](https://etherscan.io/address/0xB58700939159Db7a47b64FF74cF98150AccBF904) |

*   
  Connectors

| Name | Contract | Address |
| ----- | ----- | ----- |
| AAVE\_V3 | AaveV3Connector | [0x08c28e1c82C09487DCB15a3e0839e8C888EeE3CD](https://etherscan.io/address/0x08c28e1c82C09487DCB15a3e0839e8C888EeE3CD) |
| COMPOUND\_V3 | CompoundV3Connector | [0xbeaa30DCB697CFFB64E319A3Fc4b0688Be5aE790](https://etherscan.io/address/0xbeaa30DCB697CFFB64E319A3Fc4b0688Be5aE790) |
| SDAI | SDAIConnector | [0x22Fc700401FABbB7de1872461E8733d74e02f88a](https://etherscan.io/address/0x22Fc700401FABbB7de1872461E8733d74e02f88a) |
| METAMORPHO\_STEAKHOUSE\_USDC | MetamorphoConnector | [0xDa5FfFCF097A95E0aE6e6eC9b966da5ba89844f2](https://etherscan.io/address/0xDa5FfFCF097A95E0aE6e6eC9b966da5ba89844f2) |
| METAMORPHO\_STEAKHOUSE\_USDT | MetamorphoConnector | [0xD64f05bC43a52134dbBC6eBe8c1A7C1C1e41D3F2](https://etherscan.io/address/0xD64f05bC43a52134dbBC6eBe8c1A7C1C1e41D3F2) |
| ANGLE\_STUSD | AngleSavingConnector | [0x3443Ea9BcC9E1E515e567a278bDae103e7324d1d](https://etherscan.io/address/0x3443Ea9BcC9E1E515e567a278bDae103e7324d1d) |
| METAMORPHO\_GAUNTLET\_USDA\_CORE | MetamorphoConnector | [0x7398542b18B9d0b532388BEFF137eE8C494Dcf40](https://etherscan.io/address/0x7398542b18B9d0b532388BEFF137eE8C494Dcf40) |
| METAMORPHO\_GAUNTLET\_USDC\_PRIME | MetamorphoConnector | [0x57755c439eC0F4A2a99a9437b7C26932E00E03B0](https://etherscan.io/address/0x57755c439eC0F4A2a99a9437b7C26932E00E03B0) |
| METAMORPHO\_GAUNTLET\_USDT\_PRIME | MetamorphoConnector | [0x508f624bD2B6954be47ddb78053D54EeF9631f16](https://etherscan.io/address/0x508f624bD2B6954be47ddb78053D54EeF9631f16) |
| SUSDS | SUSDSConnector | [0xe68c8E20C4E469800A13ABeBF0Dfd094CC2C4DE2](https://etherscan.io/address/0xe68c8E20C4E469800A13ABeBF0Dfd094CC2C4DE2) |
| METAMORPHO\_GAUNTLET\_LBTC\_CORE | MetamorphoConnector | [0xfF96f6D7A09e23DEbc4aE32915A4F49af0B3Eb88](https://etherscan.io/address/0xfF96f6D7A09e23DEbc4aE32915A4F49af0B3Eb88) |
| METAMORPHO\_STEAKHOUSE\_ETH | MetamorphoConnector | [0x1285BBcc1b35a641e1169AfD237d5A136ceDb257](https://etherscan.io/address/0x1285BBcc1b35a641e1169AfD237d5A136ceDb257) |
| ANGLE\_STEUR | AngleSavingConnector | [0xd48BDf1Ad3557b8e770e1730d3738dfd6e26fCfE](https://etherscan.io/address/0xd48BDf1Ad3557b8e770e1730d3738dfd6e26fCfE) |

*   
  Active vaults:  
  * An active vault is any vault listed below that is not paused. Even if not explicitly listed here, the Kiln core and connector contracts used by the active vaults listed below are also in scope. See the two tables above for mainnet Kiln core and connector contracts as a reference.

| label | address | defi\_connector\_name | network | defi\_asset |
| ----- | ----- | ----- | ----- | ----- |
| Trust Wallet AAVE v3 USDT | 0x696b456c1c79416CCE302D09e935b3cB80d0CDC5 | AAVE\_V3 | bnb | $USDT (Tether USD) |
| Trust Wallet Venus DAI | 0x290F5566a5269A52ad70D01aC860456b3B964f01 | VENUS | bnb | $DAI (Dai Token) |
| Trust Wallet Venus USDT | 0xB962E0B467E4EdA5b8df916c5756F9753d46914F | VENUS | bnb | $USDT (Tether USD) |
| Trust Wallet Venus USDC | 0xBF45a2e9bBa728037A714380899fd7C4ee587312 | VENUS | bnb | $USDC (USD Coin) |
| Cool Wallet AAVEv3 USDT | 0x4d1806C26A728f2e1b82b4549b9E074DBE5940B9 | AAVE\_V3 | bnb | $USDT (Tether USD) |
| Cool Wallet AAVEv3 USDC | 0x1F7Cf59d1ABd6F03dAf7CCA7817B634251B8723C | AAVE\_V3 | bnb | $USDC (USD Coin) |
| Bifrost Compound v3 USDT | 0xE194d6De7E9499116A9E7E923696A92d6944D2B2 | COMPOUND\_V3 | polygon | $USDT ((PoS) Tether USD) |
| Cool Wallet AAVEv3 USDT | 0x03441c89e7B751bb570f9Dc8C92702b127c52C51 | AAVE\_V3 | polygon | $USDT ((PoS) Tether USD) |
| BITNOVO AAVE v3 DAI | 0x66431b90985212D3B09E27ff9b83cb32F6dd79Dc | AAVE\_V3 | polygon | $DAI ((PoS) Dai Stablecoin) |
| BITNOVO AAVE v3 USDT | 0xebA6232DC52C2548e4b4aE1d9686e8e692436bA2 | AAVE\_V3 | polygon | $USDT ((PoS) Tether USD) |
| BITNOVO AAVE v3 USDC | 0x6f15CDA2D68B00311614294A2b9b17400636133C | AAVE\_V3 | polygon | $USDC (USD Coin) |
| Waltio Morpho Steakhouse USDC | 0xFa043C890C3C54a147E847E1C97a2C8a8115c1B3 | METAMORPHO\_STEAKHOUSE\_USDC | base | $USDC (USD Coin) |
| Waltio Morpho Steakhouse ETH | 0x4F7CA859a0d2dbbf774a1375CD12a34dAaff3D50 | METAMORPHO\_STEAKHOUSE\_ETH | base | $WETH (Wrapped Ether) |
| Bitpanda Angle EURA | 0xb8B455001a3A48c28D90eA29Efd9fcc74e95cFF7 | ANGLE\_STEUR | base | $EURA (EURA (previously agEUR)) |
| Bitpanda Morpho Steakhouse ETH | 0xddB8Ab45E253f697340a3540665733F46fD2a8fe | METAMORPHO\_STEAKHOUSE\_ETH | base | $WETH (Wrapped Ether) |
| Bitpanda Morpho Steakhouse USDC | 0x4b2A4368544E276780342750D6678dC30368EF35 | METAMORPHO\_STEAKHOUSE\_USDC | base | $USDC (USD Coin) |
| Bitpanda Morpho Gauntlet LBTC | 0x371Ed18a2fb09a0349BA284905A4F03C98cDd9D4 | METAMORPHO\_GAUNTLET\_LBTC\_CORE | base | $LBTC (Lombard Staked Bitcoin) |
| Bifrost Compound v3 USDC | 0xd92249507B3ECe9600a3b1DaDC1e4DAc3B80128F | COMPOUND\_V3 | base | $USDC (USD Coin) |
| Bifrost AAVE v3 USDC | 0x29Eceb50C5C1cc52FAb72Ff258B5a46324693BE7 | AAVE\_V3 | base | $USDC (USD Coin) |
| Trust Wallet Morpho Gauntlet USDC Core | 0x8168AEBc65b4181F6fAAe8094Ca133a272D03CA9 | METAMORPHO\_GAUNTLET\_USDC\_CORE | base | $USDC (USD Coin) |
| Trust Wallet Morpho Steakhouse USDC | 0xEeE56Dc1fb5eD6ebC596da2ea1d1ECd83409f4e4 | METAMORPHO\_STEAKHOUSE\_USDC | base | $USDC (USD Coin) |
| Trust Wallet Morpho Re7 USDC | 0x801ECB612d2f724dad01F22049752E9596dD3Eb1 | METAMORPHO\_RE7\_USDC | base | $USDC (USD Coin) |
| Waltio Fluid USDT | 0x2834704003616DAD55B5f22D3324E462E92Bad93 | FLUID | arbitrum | $USD₮0 (USD₮0) |
| Waltio Fluid USDC | 0x9Fc247b58D2d76c0231CAb96274595f59C9e4a89 | FLUID | arbitrum | $USDC (USD Coin) |
| Waltio Aave V3 WETH | 0xE9700FD4194722eb680C57ed3e07C8Bb1933Bb98 | AAVE\_V3 | arbitrum | $WETH (Wrapped Ether) |
| Waltio Aave V3 USDT | 0xeA8c59C737d32e0EE78dbAd35C27b142356Ea4a3 | AAVE\_V3 | arbitrum | $USD₮0 (USD₮0) |
| Waltio Aave V3 USDC | 0xe3657dFE299393eBdFC9D5059Ed85ef67eFEEcC1 | AAVE\_V3 | arbitrum | $USDC (USD Coin) |
| Bifrost Compound v3 USDT | 0xAd231a5aAc991089F1A4FEbFD95eE571A9826054 | COMPOUND\_V3 | arbitrum | $USD₮0 (USD₮0) |
| Rapidz Aave v3 USDC | 0xEdf257f1429a4E0efBa1019348112Ff1b6Be2231 | AAVE\_V3 | arbitrum | $USDC (USD Coin) |
| Trust Wallet AAVE v3 DAI | 0x96d6c438C704A2de8CDCE435803A10D329b72E68 | AAVE\_V3 | arbitrum | $DAI (Dai Stablecoin) |
| Trust Wallet AAVE v3 USDT | 0x15DCC1978f68c5E0D7A298A65fCc879E2D673D43 | AAVE\_V3 | arbitrum | $USD₮0 (USD₮0) |
| Trust Wallet AAVE v3 USDC | 0x90788f682463D1Ac00Bd2230b15A4bD0D32a3E46 | AAVE\_V3 | arbitrum | $USDC (USD Coin) |
| Bitnovo Aave v3 USDC | 0xA7c500EB3069bAD292D9Bd57574a89Cd883118df | AAVE\_V3 | arbitrum | $USDC (USD Coin) |
| Bitnovo Aave v3 USDT | 0xdB8C962e8A39d3E82d3EAA8F477bE90984C6Dfe8 | AAVE\_V3 | arbitrum | $USD₮0 (USD₮0) |
| Bitnovo Aave v3 DAI | 0xdB4b6723f5659B4e78AaB29Fb1eD49Ccc18Fc5e6 | AAVE\_V3 | arbitrum | $DAI (Dai Stablecoin) |
| Bitnovo Compound v3 USDC | 0x19A0F016Ac3989e754ab8216810beD8503bDA37e | COMPOUND\_V3 | arbitrum | $USDC (USD Coin) |
| Crypto.com Defi Wallet Compound USDC.e | 0xAB3aC228Cac84a8a1C855C3E08F869B65836c962 | COMPOUND\_V3 | arbitrum | $USDC (USD Coin (Arb1)) |
| Crypto.com Defi Wallet Compound USDC | 0x1C107c4233Ab3056254e717c7a67F9917079b615 | COMPOUND\_V3 | arbitrum | $USDC (USD Coin) |
| Crypto.com Defi Wallet AAVE DAI | 0x552dAc42901b7559D31247B77fA550fb65688432 | AAVE\_V3 | arbitrum | $DAI (Dai Stablecoin) |
| Crypto.com Defi Wallet AAVE USDC.e | 0x9b855bA95bbD19C73d931977feB5140D40bC03F6 | AAVE\_V3 | arbitrum | $USDC (USD Coin (Arb1)) |
| Crypto.com Defi Wallet AAVE USDT | 0xf8df2Eee600A4Df8cc494D8B1ff34B7980AbA3aD | AAVE\_V3 | arbitrum | $USD₮0 (USD₮0) |
| Crypto.com Defi Wallet AAVE USDC | 0x97901Cf9f064c40F538C5f7b53420A02Cb68c644 | AAVE\_V3 | arbitrum | $USDC (USD Coin) |
| Bifrost Compound v3 USDC | 0x1eB3061F96Ff927EA7CAeF216bB5872622052C1C | COMPOUND\_V3 | arbitrum | $USDC (USD Coin) |
| Bifrost AAVE v3 USDT | 0x8A44861320c68b87C58A35d7110fAc5615233728 | AAVE\_V3 | arbitrum | $USD₮0 (USD₮0) |
| Bifrost AAVE v3 USDC | 0xBD3D2a51824784F138A333055Fa91b590CD2B2CB | AAVE\_V3 | arbitrum | $USDC (USD Coin) |
| Bitnovo AAVE v3 DAI | 0xeEE5205D35747307c3650c82b86Acfd1Abc300b0 | AAVE\_V3 | optimism | $DAI (Dai Stablecoin) |
| Bitnovo AAVE v3 USDT | 0x0BA60A5bA2D59B3A52C1b27cCc1C7f28213b8C9b | AAVE\_V3 | optimism | $USDT (Tether USD) |
| Bitnovo AAVE v3 USDC | 0xAEcC73782E5d6a6e9F6c1a6533bc68D90891f9b9 | AAVE\_V3 | optimism | $USDC (USD Coin) |
| Dakota AAVE v3 USDC | 0xB9EbFF375D5EADE50Ed561F611754902f70e34CF | AAVE\_V3 | optimism | $USDC (USD Coin) |
| Waltio Fluid USDT | 0x8AF79Dd066d86fE6F3169c62e515D15174dc1A45 | FLUID | ethereum | $USDT (Tether USD) |
| Waltio Fluid USDC | 0x42A32606eb641BcB262b5b9F05222EdA3fC30F99 | FLUID | ethereum | $USDC (USD Coin) |
| Waltio Morpho Steakhouse ETH | 0xC9514F08f80d59eb0C418883092F295397b3e536 | METAMORPHO\_STEAKHOUSE\_ETH | ethereum | $WETH (Wrapped Ether) |
| Waltio Morpho Steakhouse USDC | 0xaAB9eC3c2F5F363c654a2910Dbe29aeA708C80b6 | METAMORPHO\_STEAKHOUSE\_USDC | ethereum | $USDC (USD Coin) |
| Waltio Aave V3 WETH | 0xafDb696b693F38996B4fa7B839f3E9CfdD758694 | AAVE\_V3 | ethereum | $WETH (Wrapped Ether) |
| Waltio Aave V3 USDT | 0x7F8ca9b130ED8027a8dc2949542593Dc1a1c95DC | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Waltio Aave V3 USDC | 0x8b1fE482062B9B5FF40c4473d47674A886022118 | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Yield Bearing Venus USDT | 0xCcDed4b9D47F7F248bfe3F49a9C70A5F1E6EA4c4 | VENUS | ethereum | $USDT (Tether USD) |
| Yield Bearing Venus USDC | 0xDa273908A3f837091774164E2821ba8Ee8238501 | VENUS | ethereum | $USDC (USD Coin) |
| Bifrost Sky Savings USDS | 0x9e7aa7686FE1a85896d2cDcB7AFc3D01237cD276 | SUSDS | ethereum | $USDS (USDS Stablecoin) |
| Bifrost Compound v3 USDT | 0x96D595D35a0203d6e218852190b3E981ADEeab0B | COMPOUND\_V3 | ethereum | $USDT (Tether USD) |
| Bifrost Compound v3 USDS | 0x91422083A9947De4f0423c6829888BE7B83f06F5 | COMPOUND\_V3 | ethereum | $USDS (USDS Stablecoin) |
| Bifrost Compound v3 USDC | 0x754A34e2f4582925F5E384c371f78db01A869572 | COMPOUND\_V3 | ethereum | $USDC (USD Coin) |
| Bifrost AAVE v3 USDT | 0x5B38308f3dB29EA653f83db5E715189abCb83fd9 | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Bifrost AAVE v3 USDS | 0xCB575B3de1224469B6fb4d7f03AcE1bED5C92E0b | AAVE\_V3 | ethereum | $USDS (USDS Stablecoin) |
| Bifrost AAVE v3 USDC | 0x56a5a7E7aD573ec8568727b87C881dffC30C84dA | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Bitpanda Angle EURA | 0xC4C8Ffe0AFfEE49Ef5EB13c2908Ad63B359846C1 | ANGLE\_STEUR | ethereum | $EURA (EURA (previously agEUR)) |
| Bitpanda Morpho Steakhouse ETH | 0xCeE637e5D129bDfac96bC72fA70ccF12D8D81856 | METAMORPHO\_STEAKHOUSE\_ETH | ethereum | $WETH (Wrapped Ether) |
| Bitpanda Morpho Steakhouse USDC | 0x31bcEa36c4943feB48650355dE1fB5f12DcF7674 | METAMORPHO\_STEAKHOUSE\_USDC | ethereum | $USDC (USD Coin) |
| Bitpanda Morpho Gauntlet LBTC | 0x49EC3dC668F579AC0027255D28662bb056A09b57 | METAMORPHO\_GAUNTLET\_LBTC\_CORE | ethereum | $LBTC (Lombard Staked Bitcoin) |
| Yield Bearing Sky USDS | 0x7DAEBa3F217614E409F85d3014D33923a6b03630 | SUSDS | ethereum | $USDS (USDS Stablecoin) |
| Yield Bearing Angle USDA | 0x4B20748c3Dd973f1456eccDE4FF84D54792dcD3e | ANGLE\_STUSD | ethereum | $USDA (USDA) |
| Yield Bearing Steakhouse Morpho USDT | 0x96B22EB7178d116797e57197e586b70FedAE8Fdd | METAMORPHO\_STEAKHOUSE\_USDT | ethereum | $USDT (Tether USD) |
| Yield Bearing Steakhouse Morpho USDC | 0x334F5d28a71432f8fc21C7B2B6F5dBbcD8B32A7b | METAMORPHO\_STEAKHOUSE\_USDC | ethereum | $USDC (USD Coin) |
| Yield Bearing Compound USDC | 0xB9E62Cb9b4cE8ec13c886FaE67369Da417EE2714 | COMPOUND\_V3 | ethereum | $USDC (USD Coin) |
| Yield Bearing Spark DAI | 0xbd08C57f7448a5794bf4faeE067EC71AA64ef26D | SDAI | ethereum | $DAI (Dai Stablecoin) |
| Yield Bearing AAVE USDS | 0xD88714E295da03a07BcB8aD4a4dbE87fa42d75f9 | AAVE\_V3 | ethereum | $USDS (USDS Stablecoin) |
| Yield Bearing AAVE DAI | 0x4Ef971774c77865FF8Ec35f274474CB0eD9c48FA | AAVE\_V3 | ethereum | $DAI (Dai Stablecoin) |
| Yield Bearing AAVE USDC | 0xD2011d314aCAA68E5401E7f5AeC3Be6d2C574DCf | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Yield Bearing AAVE USDT | 0x4D431856295413906075dD40266d83624E09C672 | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Trust Wallet AAVE v3 DAI | 0x6C310b55D6728423B3bddB9D07A6c21Bb6eFBDCb | AAVE\_V3 | ethereum | $DAI (Dai Stablecoin) |
| Trust Wallet AAVE v3 USDT | 0x2Df453aA9ac59Dc05030979CA67Af4BBff424333 | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Trust Wallet AAVE v3 USDC | 0xe7Bf38c635426caaCfa95966c4C6064e7637fE0A | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Trust Wallet Spark DAI | 0x2a7822d6764dFc7a945A4c38776624cB542b32f6 | SDAI | ethereum | $DAI (Dai Stablecoin) |
| Trust Wallet Compound v3 USDC | 0x804EE40b227B9003BB7bf2880cF502466544F208 | COMPOUND\_V3 | ethereum | $USDC (USD Coin) |
| Bitcoin.com MetaMorpho Steakhouse USDC | 0x50913b45F278c39c8A7925b3C31DD88B95fb1AA2 | METAMORPHO\_STEAKHOUSE\_USDC | ethereum | $USDC (USD Coin) |
| Bitcoin.com Spark DAI | 0xF4918Ef824a242602E0d3e5DB07fFd4DaC4ad3Ea | SDAI | ethereum | $DAI (Dai Stablecoin) |
| Dakota AAVE v3 USDT | 0xBd01d20e6897e4A148BafFCfa9ED7aA1ac05a4B0 | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Bitnovo Compound v3 USDC | 0x4bf3499072103e9A4afC2Ce4ea09afccF163CD87 | COMPOUND\_V3 | ethereum | $USDC (USD Coin) |
| Bitnovo Aave v3 USDC | 0x6504158a43208150E5dbc0602d3F3Ac694e0158e | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Bitnovo Aave v3 USDT | 0x815d9e5A6F9c9662b07570c801131e8942587132 | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Bitnovo Aave v3 DAI | 0xB59f4f16709Aa88e04B0addf15a3DF6Aa8B14524 | AAVE\_V3 | ethereum | $DAI (Dai Stablecoin) |
| Cool Wallet AAVEv3 DAI | 0xe2F86504C610EdbaE7A788b04785395fDe781577 | AAVE\_V3 | ethereum | $DAI (Dai Stablecoin) |
| Cool Wallet AAVEv3 USDT | 0x924e38bdFDa04990Fc78FEc258E8B83B3478B1Af | AAVE\_V3 | ethereum | $USDT (Tether USD) |
| Trust Wallet Morpho Steakhouse USDT | 0x75e4cE661A49B6bfb2d5b1a8231E32aB47F8b706 | METAMORPHO\_STEAKHOUSE\_USDT | ethereum | $USDT (Tether USD) |
| Cool Wallet AAVEv3 USDC | 0x2db0B0fa84C3c8B342183FD0B777C521ec054325 | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Dakota AAVE v3 USDC | 0x15BEFDB812690D02eCB4cDE372f42BF0A8c24d68 | AAVE\_V3 | ethereum | $USDC (USD Coin) |
| Trust Wallet Morpho Steakhouse USDC | 0x9c4E4c15D0532204186ef757b246253A65B4562D | METAMORPHO\_STEAKHOUSE\_USDC | ethereum | $USDC (USD Coin) |
| Trust Wallet Angle Staked USDA | 0x75eE9f7aA08d20788898103f28F640FFF0fB85fC | ANGLE\_STUSD | ethereum | $USDA (USDA) |
| Trust Wallet Morpho Gauntlet USDA Core | 0x67c18866E6F6bEE1e9B6d0BB9055a65Dba8E9348 | METAMORPHO\_GAUNTLET\_USDA\_CORE | ethereum | $USDA (USDA) |
| Trust Wallet Morpho Gauntlet USDT Prime | 0xd972f93d3F8A1B0ae072Cd21CcBb6344f3407275 | METAMORPHO\_GAUNTLET\_USDT\_PRIME | ethereum | $USDT (Tether USD) |
| Trust Wallet Morpho Gauntlet USDC Prime | 0xc81aB5DE4871a447f1003B90c7Ff8C961702EEb2 | METAMORPHO\_GAUNTLET\_USDC\_PRIME | ethereum | $USDC (USD Coin) |

Documentation for the assets provided in the table can be found at [https://docs.kiln.fi/v1/kiln-products/defi](https://docs.kiln.fi/v1/kiln-products/defi).

## Severity Definitions

### Smart Contracts severity levels

| Severity level | Impact: High | Impact: Medium | Impact: Low |
| ----- | ----- | ----- | ----- |
| Likelihood:high | Critical | High | Medium |
| Likelihood:medium | High | Medium | \- |
| Likelihood:low | Medium | \- | \- |

Critical: \- Complete loss of funds or permanent freezing of funds

High: \- Theft of unclaimed yield, or Permanent freezing of unclaimed yield \- Temporary freezing of funds \> 2 days (excluding potential delay due to an oracle).

Medium: \- Smart contracts inoperable due to lack of funds \- Griefing or unbounded gas consumption \- Theft of any commission/fees

A PoC is required for the following severity levels:

* Smart Contract:  
  * Critical  
  * High  
  * Medium

## Rewards

## Rewards for Smart Contract Bugs

| Severity | Reward Amount |
| ----- | ----- |
| Critical | $500,000 |
| High | $50,000 |
| Medium | $20,000 |

### Reward Levels

* Critical: Upto 500,000, Minimum payout 100,000 Rewards will be further capped at 10% of direct funds at risk based on the valid POC provided.  
* High: Upto 50,000, Minimum payout 20,000 Rewards will be further capped at 100% of direct funds at risk based on the valid POC provided. In case of a temporary freeze of funds, reward is proportional to the amount of funds locked and increases as the freeze duration increases up until the maximum cap of the High severity levels.  
* Medium: Upto 20,000, Minimum payout $5,000 Rewards will be further capped at 100% of direct funds at risk based on the valid POC provided.  
* The bug bounty will have a hard cap of $1,000,000. In the case of multiple bug findings are submitted that exceed this amount, the rewards will be distributed on a first come first served basis.

## Out of Scope

These impacts are out of scope for this bug bounty program. General:

* Consequences resulting from exploits the reporter has already carried out, which lead to damage.  
* Issues caused by attacks that require access to leaked keys or credentials.  
* Problems arising from attacks that need access to privileged roles (e.g., governance or strategist), except when the contracts are explicitly designed to prevent privileged access to functions that enable the attack.  
* Issues relying on attacks triggered by the depegging of an external stablecoin, unless the attacker causes the depegging due to a bug in the code.  
* References to secrets, access tokens, API keys, private keys, etc., that are not being used in production.

Smart Contracts:

* Issues arising from incorrect data provided by third-party oracles, with the exception of oracle manipulation or flash loan attacks.  
* Attacks that rely on basic economic or governance vulnerabilities, such as a 51% attack.  
* Problems related to insufficient liquidity.  
* Issues stemming from Sybil attacks.  
* Concerns involving risks of centralization.  
* Suggestions for best practices.

Roles:

* Admin, proxy admin, hatcher admin, treasury, oracles and other admin roles are trusted to behave properly and in the best interest of the users. They should not be considered as malicious. Submission citing malicious behaviour of these roles will be considered invalid.

### Known Issues

Known issues listed and acknowledged below are not eligible for any reward through the bug bounty program.

* [https://kilnfi.notion.site/EXTERNAL-AUDITS-479819dce90540d1a0800c0541d2352b](https://kilnfi.notion.site/EXTERNAL-AUDITS-479819dce90540d1a0800c0541d2352b)

### Specific Types of Issues

* Informational findings.  
* Design choices related to protocol.  
* Issues that are ultimately user errors and can easily be caught in the frontend. For example, transfers to address(0).  
* Rounding errors.  
* Relatively high gas consumption.  
* Extreme market turmoil vulnerability.

## Disclosure

Researchers who submit valid vulnerability reports agree to adhere to the following responsible disclosure process:

* Upon confirmation of a valid vulnerability, Kiln will work diligently to develop and implement a fix.  
* Once the fix is deployed to production, Kiln will notify the researcher and initiate a 1-month (30 calendar days) disclosure waiting period.  
* During this waiting period, the researcher must maintain strict confidentiality regarding the vulnerability and shall not disclose any information about it to third parties or the public.  
* After the 1-month period has elapsed following the production deployment of the fix, the researcher may publicly disclose the vulnerability, provided they have obtained written approval from Kiln regarding the content of the disclosure.  
* The researcher agrees to coordinate with Kiln on the timing and content of any public disclosure to ensure all parties are prepared and to minimize potential risks to users.  
* If the researcher discovers that the vulnerability has become publicly known before the end of the waiting period, they should immediately notify Kiln. Kiln reserves the right to request an extension of the waiting period in exceptional circumstances, which will be communicated to the researcher in writing.

## Eligibility

Security researchers who fall under any of the following are ineligible for a reward

* Any person included on the List of Specially Designated Nationals and Blocked Persons maintained by the US Treasury Department’s Office of Foreign Assets Control (OFAC) or on any list pursuant to European Union (EU) and/or United Kingdom (UK) regulations.

### KYC

The following information is required for payments:

* If the claim comes from an individual:  
  * The first names, surnames, date and place of birth of the person concerned  
    * A Valid ID  
  * If the claim comes from a business:  
    * Legal form, name, registration number and address of the registered office  
    * Valid certificate of incorporation  
    * List of shareholders/directors

## Prohibited Actions

* Live testing on public chains, including public mainnet deployments and public testnet deployments.  
  * We recommend testing on local forks, for example using foundry.  
* Public disclosure of bugs without the consent of the protocol team.  
* Any denial of service attacks that are executed against project assets  
* Automated testing of services that results in a denial of service  
* *Conflict of Interest*: any employee or contractor working with Project Entity cannot participate in the Bug Bounty.  
* Attempting phishing or other social engineering attacks against our employees and/or customers

## Other Terms

By submitting a report, you grant Kiln the rights necessary to investigate, mitigate, and disclose the vulnerability. Reward decisions and eligibility are at the sole discretion of Kiln. The terms, conditions, and scope of this Program may be revised at any time. All participants are responsible for reviewing the latest version before submitting a report.

