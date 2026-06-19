# AST Facts (Compiler-Verified)

MODE: regex-fallback

> Extraction mode: regex-fallback
> Project root: /Volumes/Dumebi-SSD/Bounty/kiln-vault
> Scope directory: /Volumes/Dumebi-SSD/Bounty/kiln-vault/src
> Extraction timestamp: 2026-06-19T18:07:19Z

## Inheritance Tree
| Contract | File | Inherits From |
|----------|------|---------------|
| BlockList | src/BlockList.sol | AccessControlDefaultAdminRulesUpgradeable |
| BlockListFactory | src/BlockListFactory.sol | AccessControlDefaultAdminRules |
| ConnectorRegistry | src/ConnectorRegistry.sol | IConnectorRegistry,AccessControlDefaultAdminRules |
| ExternalAccessControl | src/ExternalAccessControl.sol | AccessControlDefaultAdminRulesUpgradeable |
| FeeDispatcher | src/FeeDispatcher.sol | IFeeDispatcher,ReentrancyGuardUpgradeable |
| Vault | src/Vault.sol | ERC4626Upgradeable,AccessControlDefaultAdminRulesUpgradeable,ReentrancyGuardUpgradeable |
| VaultFactory | src/VaultFactory.sol | AccessControlDefaultAdminRulesUpgradeable |
| FeeDispatcher_1_0_0 | src/_archive/FeeDispatcher_1_0_0.sol | Initializable,IFeeDispatcher_1_0_0 |
| AaveV3Connector | src/connectors/AaveV3Connector.sol | IConnector |
| AngleSavingConnector | src/connectors/AngleSavingConnector.sol | IConnector |
| CompoundV3Connector | src/connectors/CompoundV3Connector.sol | IConnector |
| MetamorphoConnector | src/connectors/MetamorphoConnector.sol | IConnector |
| SDAIConnector | src/connectors/SDAIConnector.sol | IConnector |
| SUSDSConnector | src/connectors/SUSDSConnector.sol | IConnector |
| BlockListBeaconProxy | src/proxy/BlockListBeaconProxy.sol | BeaconProxy |
| BlockListUpgradeableBeacon | src/proxy/BlockListUpgradeableBeacon.sol | IBeacon,AccessControlDefaultAdminRules |
| VaultBeaconProxy | src/proxy/VaultBeaconProxy.sol | BeaconProxy |
| VaultUpgradeableBeacon | src/proxy/VaultUpgradeableBeacon.sol | IBeacon,AccessControlDefaultAdminRules |

## Function Registry
### BlockList (src/BlockList.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| _getBlockListStorage | private | pure |  |
| initialize | public | nonpayable | onlyDelegateCall,initializer |
| __BlockList_init | internal | nonpayable |  |
| addToBlockList | public | nonpayable |  |
| removeFromBlockList | public | nonpayable |  |
| isBlocked | public | view |  |
| isBlockedByInternalList | public | view |  |
| isSanctionedByUnderlyingList | public | view |  |
| setUnderlyingSanctionsList | external | nonpayable |  |
| _setName | internal | nonpayable |  |
| _setUnderlyingSanctionsList | internal | nonpayable |  |
| name | public | view |  |
| underlyingSanctionsList | public | view |  |

### BlockListFactory (src/BlockListFactory.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| createBlockList | internal | nonpayable |  |
| getDeployedBlockLists | public | view |  |

### ConnectorRegistry (src/ConnectorRegistry.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| connectorAddress | public | view |  |
| frozen | public | view |  |
| pauseTimestamp | public | view |  |
| get | external | view |  |
| getOrRevert | external | view |  |
| connectorExists | public | view |  |
| paused | public | view |  |
| add | external | nonpayable |  |
| update | internal | nonpayable |  |
| remove | internal | nonpayable |  |
| pause | external | nonpayable |  |
| pauseFor | external | nonpayable |  |
| unPause | external | nonpayable |  |
| freeze | external | nonpayable |  |

### ExternalAccessControl (src/ExternalAccessControl.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| initialize | public | nonpayable | onlyDelegateCall,initializer |

### FeeDispatcher (src/FeeDispatcher.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| _getFeeDispatcherStorage | private | pure |  |
| initialize | public | nonpayable | initializer,onlyDelegateCall |
| _initialize | internal | nonpayable |  |
| dispatchFees | external | nonpayable | nonReentrant |
| pendingDepositFee | public | view |  |
| pendingRewardFee | public | view |  |
| feeRecipients | public | view |  |
| feeRecipient | public | view |  |
| feeRecipientAt | public | view |  |
| incrementPendingDepositFee | external | nonpayable |  |
| incrementPendingRewardFee | external | nonpayable |  |
| setFeeRecipients | external | nonpayable |  |

### Vault (src/Vault.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| _getVaultStorage | private | pure |  |
| _notBlocked | internal | view |  |
| _whenDepositNotPaused | internal | view |  |
| _checkTransferability | internal | view |  |
| _onlyFactory | internal | view |  |
| initialize | internal | nonpayable |  |
| _initialize | internal | nonpayable | initializer |
| __Vault_init | internal | nonpayable | onlyInitializing |
| upgrade | public | nonpayable | onlyFactory |
| _upgrade | internal | nonpayable |  |
| __Vault_upgrade | internal | nonpayable | onlyInitializing |
| delegateToFactory | external | nonpayable |  |
| totalAssets | public | view |  |
| maxDeposit | public | view |  |
| maxMint | public | view |  |
| maxWithdraw | public | view |  |
| maxRedeem | public | view |  |
| previewDeposit | public | view |  |
| previewMint | public | view |  |
| previewWithdraw | public | view |  |
| previewRedeem | public | view |  |
| deposit | internal | nonpayable |  |
| mint | internal | nonpayable |  |
| withdraw | internal | nonpayable |  |
| redeem | internal | nonpayable |  |
| _deposit | internal | nonpayable |  |
| _withdraw | internal | nonpayable |  |
| _maxDeposit | internal | view |  |
| _maxMint | internal | view |  |
| _maxWithdraw | internal | view |  |
| _maxRedeem | internal | nonpayable |  |
| _previewDeposit | internal | nonpayable |  |
| _previewMint | internal | nonpayable |  |
| _convertToShares | internal | nonpayable |  |
| _convertToAssets | internal | nonpayable |  |
| _decimalsOffset | internal | view |  |
| _accrueRewardFee | internal | nonpayable |  |
| _accruedRewardFeeShares | internal | view |  |
| _checkPartialShares | internal | view |  |
| _roundDownPartialShares | internal | view |  |
| transfer | internal | nonpayable |  |
| transferFrom | internal | nonpayable |  |
| approve | internal | nonpayable |  |
| dispatchFees | external | nonpayable | nonReentrant |
| collectRewardFees | external | nonpayable |  |
| claimAdditionalRewards | internal | nonpayable |  |
| setAdditionalRewardsStrategy | external | nonpayable |  |
| setBlockList | external | nonpayable |  |
| forceWithdraw | public | nonpayable |  |
| pauseDeposit | external | nonpayable |  |
| unpauseDeposit | external | nonpayable |  |
| setFeeRecipients | external | nonpayable |  |
| setDepositFee | external | nonpayable |  |
| setRewardFee | external | nonpayable |  |
| _setRewardFee | internal | nonpayable |  |
| _setDepositFee | internal | nonpayable |  |
| _setConnectorRegistry | internal | nonpayable |  |
| _setConnectorName | internal | nonpayable |  |
| _setTransferable | internal | nonpayable |  |
| _setOffset | internal | nonpayable |  |
| _setBlockList | internal | nonpayable |  |
| _setMinTotalSupply | internal | nonpayable |  |
| _setAdditionalRewardsStrategy | internal | nonpayable |  |
| _setFeeDispatcher | internal | nonpayable |  |
| transferable | external | view |  |
| connectorRegistry | external | view |  |
| connectorName | external | view |  |
| depositFee | external | view |  |
| rewardFee | external | view |  |
| additionalRewardsStrategy | external | view |  |
| collectableRewardFees | external | view |  |
| blockList | external | view |  |
| pendingDepositFee | public | view |  |
| pendingRewardFee | public | view |  |
| feeRecipients | public | view |  |
| feeRecipient | public | view |  |
| feeRecipientAt | public | view |  |
| _getConnector | internal | view |  |
| _underlyingDecimals | internal | view |  |

### VaultFactory (src/VaultFactory.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| _getVaultFactoryStorage | private | pure |  |
| initialize | public | nonpayable | onlyDelegateCall,initializer |
| createVault | internal | nonpayable |  |
| removeVault | external | nonpayable |  |
| upgradeVault | external | nonpayable |  |
| __getFeeDispatcherStorage | external | pure |  |
| getDeployedVault | public | view |  |
| getDeployedVaults | public | view |  |

### AaveV3Connector (src/connectors/AaveV3Connector.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| supply | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| getPoolDataProvider | external | view |  |
| claimAllRewards | external | nonpayable |  |
| getReserveTokensAddresses | external | view |  |
| getReserveConfigurationData | internal | nonpayable |  |
| getReserveData | internal | nonpayable |  |
| getReserveCaps | external | view |  |
| getPaused | external | view |  |
| totalAssets | external | view |  |
| deposit | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| claim | external | nonpayable |  |
| reinvest | external | nonpayable |  |
| maxDeposit | external | view |  |
| maxWithdraw | external | view |  |

### AngleSavingConnector (src/connectors/AngleSavingConnector.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| paused | external | view |  |
| totalAssets | external | view |  |
| deposit | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| claim | external | pure |  |
| reinvest | external | pure |  |
| maxDeposit | external | view |  |
| maxWithdraw | external | view |  |

### CompoundV3Connector (src/connectors/CompoundV3Connector.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| balanceOf | external | view |  |
| supply | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| isSupplyPaused | external | view |  |
| isWithdrawPaused | external | view |  |
| claim | external | nonpayable |  |
| totalAssets | external | view |  |
| deposit | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| claim | external | nonpayable |  |
| reinvest | external | nonpayable |  |
| maxDeposit | external | view |  |
| maxWithdraw | external | view |  |

### MetamorphoConnector (src/connectors/MetamorphoConnector.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| totalAssets | external | view |  |
| deposit | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| claim | external | pure |  |
| reinvest | external | pure |  |
| maxDeposit | external | view |  |
| maxWithdraw | external | view |  |

### SDAIConnector (src/connectors/SDAIConnector.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| totalAssets | external | view |  |
| deposit | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| claim | external | pure |  |
| reinvest | external | pure |  |
| maxDeposit | external | view |  |
| maxWithdraw | external | view |  |

### SUSDSConnector (src/connectors/SUSDSConnector.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| totalAssets | external | view |  |
| deposit | external | nonpayable |  |
| withdraw | external | nonpayable |  |
| claim | external | pure |  |
| reinvest | external | pure |  |
| maxDeposit | external | view |  |
| maxWithdraw | external | view |  |

### MarketRegistry (src/connectors/utils/MarketRegistry.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| getMarket | external | view |  |

### BlockListUpgradeableBeacon (src/proxy/BlockListUpgradeableBeacon.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| implementation | external | view |  |
| upgradeTo | external | nonpayable |  |
| freeze | external | nonpayable | whenNotFrozen |
| _setImplementation | private | nonpayable |  |

### VaultUpgradeableBeacon (src/proxy/VaultUpgradeableBeacon.sol)
| Function | Visibility | Mutability | Modifiers |
|----------|-----------|------------|-----------|
| implementation | external | view |  |
| upgradeTo | external | nonpayable |  |
| paused | public | view |  |
| pause | external | nonpayable |  |
| pauseFor | external | nonpayable |  |
| unpause | external | nonpayable | whenPaused |
| freeze | external | nonpayable | whenNotFrozen |
| _setImplementation | private | nonpayable |  |

## Call Graph (External Calls)
| Source File | Line | Call Pattern |
|-----------|------|-------------|
| src/FeeDispatcher.sol | 148 | `asset.safeTransferFrom(msg.sender, currentRecipient.recipient, _depositFeeAmount);` |
| src/FeeDispatcher.sol | 160 | `asset.safeTransferFrom(msg.sender, currentRecipient.recipient, _rewardFeeAmount);` |
| src/Vault.sol | 628 | `SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);` |
| src/Vault.sol | 671 | `SafeERC20.safeTransfer(IERC20(asset()), receiver, IERC20(asset()).balanceOf(address(this)) - _balanceBefore);` |
| src/Vault.sol | 879 | `return super.transfer(to, value);` |
| src/_archive/FeeDispatcher_1_0_0.sol | 140 | `asset.safeTransfer(currentRecipient.recipient, _managementFeeAmount);` |
| src/_archive/FeeDispatcher_1_0_0.sol | 153 | `asset.safeTransfer(currentRecipient.recipient, _performanceFeeAmount);` |
| src/libraries/MultisendLib.sol | 51 | `IERC20(token).safeTransfer(_recipient, total.mulDiv(_split, _scaledMaxPercent));` |
| src/test-helpers/SimpleProxy.sol | 8 | `(bool ok, ) = _impl.delegatecall(_data);` |

## Modifier Definitions
| Contract | Modifier |
|----------|----------|
| BlockList | onlyDelegateCall |
| ConnectorRegistry | whenNotPaused |
| ConnectorRegistry | whenNotFrozen |
| ConnectorRegistry | exists |
| ExternalAccessControl | onlyDelegateCall |
| FeeDispatcher | onlyDelegateCall |
| Vault | notBlocked |
| Vault | whenDepositNotPaused |
| Vault | checkTransferability |
| Vault | onlyFactory |
| Vault | logic |
| Vault | logic |
| Vault | logic |
| VaultFactory | onlyDelegateCall |
| BlockListUpgradeableBeacon | whenNotFrozen |
| VaultUpgradeableBeacon | whenNotPaused |
| VaultUpgradeableBeacon | whenPaused |
| VaultUpgradeableBeacon | whenNotFrozen |

## Risk Score Inputs (Exact Counts)
| File | LOC | External Calls | State Writers | Payable Fns | Assembly Blocks | Unchecked Blocks |
|------|-----|---------------|---------------|-------------|----------------|-----------------|
| src/BlockList.sol | 230 | 0 | 9 | 0 | 1 | 0 |
| src/BlockListFactory.sol | 117 | 0 | 1 | 0 | 0 | 0 |
| src/ConnectorRegistry.sol | 262 | 0 | 12 | 0 | 0 | 0 |
| src/Errors.sol | 179 | 0 | 0 | 0 | 0 | 0 |
| src/ExternalAccessControl.sol | 65 | 0 | 1 | 0 | 0 | 0 |
| src/FeeDispatcher.sol | 267 | 2 | 10 | 0 | 1 | 0 |
| src/Vault.sol | 1269 | 3 | 34 | 0 | 1 | 0 |
| src/VaultFactory.sol | 302 | 0 | 6 | 0 | 2 | 0 |
| src/_archive/Errors_1_0_0.sol | 179 | 0 | 0 | 0 | 0 | 0 |
| src/_archive/FeeDispatcher_1_0_0.sol | 262 | 2 | 5 | 0 | 1 | 0 |
| src/_archive/IFeeDispatcher_1_0_0.sol | 50 | 0 | 6 | 0 | 0 | 0 |
| src/connectors/AaveV3Connector.sol | 205 | 0 | 14 | 0 | 0 | 0 |
| src/connectors/AngleSavingConnector.sol | 75 | 0 | 8 | 0 | 0 | 0 |
| src/connectors/CompoundV3Connector.sol | 141 | 0 | 13 | 0 | 0 | 0 |
| src/connectors/MetamorphoConnector.sol | 67 | 0 | 7 | 0 | 0 | 0 |
| src/connectors/SDAIConnector.sol | 67 | 0 | 7 | 0 | 0 | 0 |
| src/connectors/SUSDSConnector.sol | 67 | 0 | 7 | 0 | 0 | 0 |
| src/connectors/utils/MarketRegistry.sol | 62 | 0 | 1 | 0 | 0 | 0 |
| src/interfaces/IConnector.sol | 51 | 0 | 7 | 0 | 0 | 0 |
| src/interfaces/IConnectorRegistry.sol | 69 | 0 | 11 | 0 | 0 | 0 |
| src/interfaces/IFeeDispatcher.sol | 76 | 0 | 9 | 0 | 0 | 0 |
| src/interfaces/ISanctionsList.sol | 28 | 0 | 3 | 0 | 0 | 0 |
| src/interfaces/ISelf.sol | 15 | 0 | 1 | 0 | 0 | 0 |
| src/libraries/Constants.sol | 15 | 0 | 0 | 0 | 0 | 0 |
| src/libraries/Errors.sol | 227 | 0 | 0 | 0 | 0 | 0 |
| src/libraries/MultisendLib.sol | 54 | 1 | 0 | 0 | 0 | 0 |
| src/proxy/BlockListBeaconProxy.sol | 19 | 0 | 0 | 0 | 0 | 0 |
| src/proxy/BlockListUpgradeableBeacon.sol | 117 | 0 | 3 | 0 | 0 | 0 |
| src/proxy/VaultBeaconProxy.sol | 19 | 0 | 0 | 0 | 0 | 0 |
| src/proxy/VaultUpgradeableBeacon.sol | 193 | 0 | 7 | 0 | 0 | 0 |
| src/test-helpers/SimpleProxy.sol | 24 | 1 | 0 | 0 | 1 | 0 |
