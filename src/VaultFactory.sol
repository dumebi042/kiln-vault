// SPDX-License-Identifier: BUSL-1.1
// SPDX-FileCopyrightText: 2024 Kiln <contact@kiln.fi>
//
// ██╗  ██╗██╗██╗     ███╗   ██╗
// ██║ ██╔╝██║██║     ████╗  ██║
// █████╔╝ ██║██║     ██╔██╗ ██║
// ██╔═██╗ ██║██║     ██║╚██╗██║
// ██║  ██╗██║███████╗██║ ╚████║
// ╚═╝  ╚═╝╚═╝╚══════╝╚═╝  ╚═══╝
//
pragma solidity 0.8.22;

import {Create2} from "@openzeppelin/utils/Create2.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IBeacon} from "@openzeppelin/proxy/beacon/IBeacon.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import {AddressNotContract, InvalidVaultIndex, NotDelegateCall, VaultMisconfigured} from "./libraries/Errors.sol";
import {IConnectorRegistry, BlockList, IFeeDispatcher, Vault} from "./Vault.sol";
import {VaultBeaconProxy} from "./proxy/VaultBeaconProxy.sol";
import {FeeDispatcher_1_0_0} from "./_archive/FeeDispatcher_1_0_0.sol";
import {FeeDispatcher} from "./FeeDispatcher.sol";

/// @title Kiln DeFi Integration Vault Factory.
/// @notice Factory to deploy new Vaults and initialize them.
/// @author MAXIMEBRUGEL @ Kiln.
/// @dev Using ERC-7201 standard.
contract VaultFactory is AccessControlDefaultAdminRulesUpgradeable {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the deployer role.
    bytes32 public constant DEPLOYER_ROLE = bytes32("DEPLOYER");

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation (regardless of the context).
    address public immutable _self = address(this);

    /* -------------------------------------------------------------------------- */
    /*                               STORAGE (proxy)                              */
    /* -------------------------------------------------------------------------- */

    /// @notice The storage layout of the contract.
    /// @param _deployedVault The list of deployed vaults.
    /// @param _vaultBeacon The beacon used to create new vaults.
    /// @param _connectorRegistry The connector registry used to create new vaults.
    /// @param _feeDispatcher The fee dispatcher used to create new vaults.
    struct VaultFactoryStorage {
        Vault[] _deployedVaults;
        address _vaultBeacon;
        IConnectorRegistry _connectorRegistry;
        address _feeDispatcher;
    }

    function _getVaultFactoryStorage() private pure returns (VaultFactoryStorage storage $) {
        assembly {
            $.slot := VaultFactoryStorageLocation
        }
    }

    /// @dev The storage slot of the VaultFactoryStorage struct in the proxy contract.
    ///      keccak256(abi.encode(uint256(keccak256("kiln.storage.vaultFactory")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultFactoryStorageLocation =
        0xb15b0e5184d023350edf2480f9c9912300640d68c5b0243b52371c071431c400;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when a new vault is created.
    /// @param vault The address of the new vault.
    /// @param name The name of the new vault.
    event VaultCreated(address indexed vault, string name);

    /// @dev Emitted when a vault is upgraded.
    /// @param vault The address of the vault.
    event VaultUpgraded(address indexed vault);

    /// @dev Emitted when a vault is removed.
    /// @param vault The address of the vault.
    event VaultRemoved(address indexed vault);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIER                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the call is not a delegate call.
    ///      Allow to check if the contract is called from a proxy.
    modifier onlyDelegateCall() {
        if (address(this) == _self) revert NotDelegateCall();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 PROXY LOGIC                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Parameters for the `initialize()` function.
    struct InitializationParams {
        address initialAdmin_;
        address initialDeployer_;
        uint48 initialDelay_;
        address vaultBeacon_;
        address connectorRegistry_;
        address feeDispatcher_;
    }

    /// @notice Initializes the contract in the proxy context.
    /// @param params The initialization parameters.
    function initialize(InitializationParams calldata params) public onlyDelegateCall initializer {
        __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialAdmin_);
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        if (params.vaultBeacon_.code.length == 0) revert AddressNotContract(params.vaultBeacon_);
        address vaultAddress = IBeacon(params.vaultBeacon_).implementation();
        if (Vault(vaultAddress).vaultFactory() != address(this)) {
            revert VaultMisconfigured();
        }
        $._vaultBeacon = params.vaultBeacon_;

        if (params.connectorRegistry_.code.length == 0) revert AddressNotContract(params.connectorRegistry_);
        $._connectorRegistry = IConnectorRegistry(params.connectorRegistry_);

        if (params.feeDispatcher_.code.length == 0) revert AddressNotContract(params.feeDispatcher_);
        $._feeDispatcher = params.feeDispatcher_;

        _grantRole(DEPLOYER_ROLE, params.initialDeployer_);
    }

    /* -------------------------------------------------------------------------- */
    /*                                FACTORY LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @notice The parameters to create a new vault.
    struct CreateVaultParams {
        IERC20 asset_;
        string name_;
        string symbol_;
        bool transferable_;
        bytes32 connectorName_;
        IFeeDispatcher.FeeRecipient[] recipients_;
        uint256 depositFee_;
        uint256 rewardFee_;
        address initialDefaultAdmin_;
        address initialFeeManager_;
        address initialFeeCollector_;
        address initialSanctionsManager_;
        address initialClaimManager_;
        address initialPauser_;
        address initialUnpauser_;
        uint48 initialDelay_;
        uint8 offset_;
        BlockList blockList_;
        uint256 minTotalSupply_;
        Vault.AdditionalRewardsStrategy additionalRewardsStrategy_;
    }

    /// @notice Creates a new vault.
    /// @param params The parameters to initialize the vault.
    /// @param salt The salt for the Vault deployment with CREATE2.
    /// @return The address of the new vault.
    function createVault(CreateVaultParams memory params, bytes32 salt)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address)
    {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        Vault.InitializationParams memory initializationParams = Vault.InitializationParams({
            asset_: params.asset_,
            name_: params.name_,
            symbol_: params.symbol_,
            transferable_: params.transferable_,
            connectorName_: params.connectorName_,
            connectorRegistry_: $._connectorRegistry,
            depositFee_: params.depositFee_,
            rewardFee_: params.rewardFee_,
            initialDefaultAdmin_: params.initialDefaultAdmin_,
            initialFeeManager_: params.initialFeeManager_,
            initialSanctionsManager_: params.initialSanctionsManager_,
            initialClaimManager_: params.initialClaimManager_,
            initialPauser_: params.initialPauser_,
            initialUnpauser_: params.initialUnpauser_,
            initialDelay_: params.initialDelay_,
            offset_: params.offset_,
            minTotalSupply_: params.minTotalSupply_
        });

        Vault.UpgradeParams memory upgradeParams = Vault.UpgradeParams({
            feeDispatcher_: $._feeDispatcher,
            recipients_: params.recipients_,
            additionalRewardsStrategy_: params.additionalRewardsStrategy_,
            blockList_: params.blockList_,
            pendingDepositFee_: 0,
            pendingRewardFee_: 0,
            connectorRegistry_: $._connectorRegistry,
            initialFeeCollector_: params.initialFeeCollector_
        });

        bytes memory _initCalldata = abi.encodeCall(Vault.initialize, (initializationParams, upgradeParams));

        address payable _newVault = payable(
            Create2.deploy(
                0,
                salt,
                abi.encodePacked(type(VaultBeaconProxy).creationCode, abi.encode($._vaultBeacon, _initCalldata))
            )
        );

        _getVaultFactoryStorage()._deployedVaults.push(Vault(_newVault));

        emit VaultCreated(_newVault, params.name_);
        return _newVault;
    }

    /// @notice Removes a vault from the factory.
    /// @dev The vault is only removed from the `_deployedVaults` array.
    /// @param index The index of the vault to remove.
    /// @param vault The address of the vault to remove.
    function removeVault(uint256 index, address vault) external onlyRole(DEPLOYER_ROLE) {
        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        if (vault != address($._deployedVaults[index])) revert InvalidVaultIndex(index, vault);
        $._deployedVaults[index] = $._deployedVaults[$._deployedVaults.length - 1];
        $._deployedVaults.pop();
        emit VaultRemoved(vault);
    }

    /* -------------------------------------------------------------------------- */
    /*                                  MIGRATION                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The parameters to create a new vault.
    struct UpgradeVaultParams {
        Vault.AdditionalRewardsStrategy additionalRewardsStrategy_;
        BlockList blockList_;
        address initialFeeCollector_;
    }

    /// @notice Upgrades a vault.
    /// @param vault The Vault address to upgrade.
    /// @param upgradeVaultParams The parameters to initialize the vault.
    function upgradeVault(Vault vault, UpgradeVaultParams memory upgradeVaultParams) external onlyRole(DEPLOYER_ROLE) {
        bytes memory _call = abi.encodeCall(VaultFactory.__getFeeDispatcherStorage, ());

        FeeDispatcher_1_0_0.FeeDispatcherStorage memory previousStorage =
            abi.decode(vault.delegateToFactory(_call), (FeeDispatcher_1_0_0.FeeDispatcherStorage));

        FeeDispatcher.FeeRecipient[] memory recipients =
            new FeeDispatcher.FeeRecipient[](previousStorage._feeRecipients.length);
        for (uint256 i = 0; i < previousStorage._feeRecipients.length; i++) {
            recipients[i] = IFeeDispatcher.FeeRecipient({
                recipient: previousStorage._feeRecipients[i].recipient,
                depositFeeSplit: previousStorage._feeRecipients[i].managementFeeSplit,
                rewardFeeSplit: previousStorage._feeRecipients[i].performanceFeeSplit
            });
        }

        VaultFactoryStorage storage $ = _getVaultFactoryStorage();
        Vault.UpgradeParams memory upgradeParams = Vault.UpgradeParams({
            feeDispatcher_: $._feeDispatcher,
            recipients_: recipients,
            additionalRewardsStrategy_: upgradeVaultParams.additionalRewardsStrategy_,
            blockList_: upgradeVaultParams.blockList_,
            pendingDepositFee_: previousStorage._pendingManagementFee,
            pendingRewardFee_: previousStorage._pendingPerformanceFee,
            connectorRegistry_: $._connectorRegistry,
            initialFeeCollector_: upgradeVaultParams.initialFeeCollector_
        });
        vault.upgrade(upgradeParams);

        _getVaultFactoryStorage()._deployedVaults.push(vault);
        emit VaultUpgraded(address(vault));
    }

    function __getFeeDispatcherStorage() external pure returns (FeeDispatcher_1_0_0.FeeDispatcherStorage memory) {
        bytes32 FeeDispatcherStorageLocation = 0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300;
        FeeDispatcher_1_0_0.FeeDispatcherStorage storage $;
        assembly {
            $.slot := FeeDispatcherStorageLocation
        }
        return $;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Get a deployed vault
    /// @param index The index of the vault
    function getDeployedVault(uint256 index) public view returns (Vault) {
        return _getVaultFactoryStorage()._deployedVaults[index];
    }

    /// @notice Get all deployed vault
    function getDeployedVaults() public view returns (Vault[] memory) {
        return _getVaultFactoryStorage()._deployedVaults;
    }
}
