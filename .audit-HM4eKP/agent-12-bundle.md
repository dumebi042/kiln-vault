### src/BlockList.sol

```solidity
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

import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {ISanctionsList} from "./interfaces/ISanctionsList.sol";
import {NotDelegateCall, AddressNotContract, AddressNotBlocked} from "./libraries/Errors.sol";

/// @title Kiln DeFi Integration blocklist.
/// @notice Blocklist to prevent a set of users to interact with the vaults.
/// @author isma @ Kiln.
contract BlockList is AccessControlDefaultAdminRulesUpgradeable {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the operator.
    bytes32 public constant OPERATOR_ROLE = bytes32("OPERATOR");

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation (regardless of the context).
    address internal immutable _self = address(this);

    /* -------------------------------------------------------------------------- */
    /*                               STORAGE (proxy)                              */
    /* -------------------------------------------------------------------------- */

    /// @notice The storage layout of the contract.
    /// @param _underlyingSanctionsList The sanctions list contract from Chainalysis.
    /// @param _blockList The blocklist.
    /// @param _name The name of the blocklist.
    struct BlockListStorage {
        ISanctionsList _underlyingSanctionsList;
        mapping(address => bool) _blockList;
        string _name;
    }

    function _getBlockListStorage() private pure returns (BlockListStorage storage $) {
        assembly {
            $.slot := BlockListStorageLocation
        }
    }

    /// @dev The storage slot of the BlockListStorage struct in the proxy contract.
    ///      keccak256(abi.encode(uint256(keccak256("kiln.storage.blockList")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant BlockListStorageLocation =
        0x95688183686c3ec8efadb488883ac1d27f5a2b91d991ab031b02fd896646bd00;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the sanctions list is initialized.
    /// @param underlyingSanctionsList The underlying sanctions list.
    event UnderlyingSanctionListInitialized(ISanctionsList underlyingSanctionsList);

    /// @dev Emitted when the underlying sanctions list is updated.
    /// @param newUnderlyingSanctionsList The new underlying sanctions list.
    event UnderlyingSanctionsListUpdated(ISanctionsList newUnderlyingSanctionsList);

    /// @dev Emitted when the name is initialized.
    /// @param name The name of the blocklist.
    event NameInitialized(string name);

    /// @dev Emitted when addresses are added to the blocklist.
    /// @param addrs The addresses added.
    event AddedToBlockList(address addrs);

    /// @dev Emitted when addresses are removed from the blocklist.
    /// @param addrs The addresses removed.
    event RemovedFromBlockList(address addrs);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
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
        string name_;
        ISanctionsList underlyingSanctionsList_;
        address initialDefaultAdmin_;
        address initialOperator_;
        uint48 initialDelay_;
    }

    /// @notice Initializes the contract in the proxy context.
    /// @param params The initialization parameters.
    function initialize(InitializationParams calldata params) public onlyDelegateCall initializer {
        __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialDefaultAdmin_);
        __BlockList_init(params);
    }

    function __BlockList_init(InitializationParams memory params) internal {
        _setUnderlyingSanctionsList(params.underlyingSanctionsList_);
        _setName(params.name_);
        _grantRole(OPERATOR_ROLE, params.initialOperator_);
    }

    /* -------------------------------------------------------------------------- */
    /*                  (PUBLIC) MANAGEMENT OF INTERNAL BLOCKLIST                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Add addresses to the blocklist.
    /// @param addrs The addresses to add.
    function addToBlockList(address[] calldata addrs) public onlyRole(OPERATOR_ROLE) {
        BlockListStorage storage $ = _getBlockListStorage();
        for (uint256 i = 0; i < addrs.length; i++) {
            $._blockList[addrs[i]] = true;
            emit AddedToBlockList(addrs[i]);
        }
    }

    /// @notice Remove addresses from the blocklist.
    /// @param addrs The addresses to remove.
    function removeFromBlockList(address[] calldata addrs) public onlyRole(OPERATOR_ROLE) {
        BlockListStorage storage $ = _getBlockListStorage();
        uint256 length = addrs.length;
        for (uint256 i = 0; i < length; i++) {
            address addr = addrs[i];
            if ($._blockList[addr] != true) {
                revert AddressNotBlocked(addr);
            }
            $._blockList[addr] = false;
            emit RemovedFromBlockList(addr);
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                    (PUBLIC) SANCTIONS LIST LOGIC                           */
    /* -------------------------------------------------------------------------- */

    /// @notice Check if an address is blocked (internal + underlying lists).
    /// @param addr The address to check.
    /// @return True if the address is blocked, false otherwise.
    function isBlocked(address addr) public view returns (bool) {
        BlockListStorage storage $ = _getBlockListStorage();
        if (ISanctionsList($._underlyingSanctionsList).isSanctioned(addr)) {
            return true;
        }
        return $._blockList[addr];
    }

    /// @notice Check if an address is blocked by the internal list (sanctions list excluded).
    /// @param addr The address to check.
    /// @return True if the address is blocked by the internal list, false otherwise.
    function isBlockedByInternalList(address addr) public view returns (bool) {
        return _getBlockListStorage()._blockList[addr];
    }

    /// @notice Check if an address is sanctioned by the underlying list (internal blocklist excluded).
    /// @param addr The address to check.
    /// @return True if the address is sanctioned by underlying list, false otherwise.
    function isSanctionedByUnderlyingList(address addr) public view returns (bool) {
        return ISanctionsList(_getBlockListStorage()._underlyingSanctionsList).isSanctioned(addr);
    }

    /* -------------------------------------------------------------------------- */
    /*                              (PUBLIC) SETTERS                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Set the underlying sanctions list.
    /// @param newUnderlyingSanctionsList The new underlying sanctions list.
    function setUnderlyingSanctionsList(ISanctionsList newUnderlyingSanctionsList) external onlyRole(OPERATOR_ROLE) {
        _setUnderlyingSanctionsList(newUnderlyingSanctionsList);
    }

    /* -------------------------------------------------------------------------- */
    /*                             (INTERNAL) SETTERS                             */
    /* -------------------------------------------------------------------------- */

    /// @notice Internal logic to set the name.
    /// @param newName The new blocklist name.
    function _setName(string memory newName) internal {
        BlockListStorage storage $ = _getBlockListStorage();
        $._name = newName;
        emit NameInitialized(newName);
    }

    /// @notice Internal logic to set the underlying sanctions list.
    /// @param newUnderlyingSanctionsList The new underlying sanctions list.
    function _setUnderlyingSanctionsList(ISanctionsList newUnderlyingSanctionsList) internal {
        BlockListStorage storage $ = _getBlockListStorage();
        if (address(newUnderlyingSanctionsList).code.length == 0) {
            revert AddressNotContract(address(newUnderlyingSanctionsList));
        }
        $._underlyingSanctionsList = newUnderlyingSanctionsList;
        emit UnderlyingSanctionsListUpdated(newUnderlyingSanctionsList);
    }

    /* -------------------------------------------------------------------------- */
    /*                                    GETTERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns the name of the blocklist.
    /// @return The name of the blocklist.
    function name() public view returns (string memory) {
        return _getBlockListStorage()._name;
    }

    /// @notice Returns the underlying sanctions list.
    /// @return The underlying sanctions list.
    function underlyingSanctionsList() public view returns (ISanctionsList) {
        return _getBlockListStorage()._underlyingSanctionsList;
    }
}

```

### src/BlockListFactory.sol

```solidity
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

import {BlockList, ISanctionsList} from "./BlockList.sol";
import {AddressNotContract} from "./libraries/Errors.sol";
import {BlockListBeaconProxy} from "./proxy/BlockListBeaconProxy.sol";

/// @title Kiln DeFi Integration sanctions list Factory.
/// @notice Factory to deploy new santions list and initialize them.
/// @author isma @ Kiln.
contract BlockListFactory is AccessControlDefaultAdminRules {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the deployer role.
    bytes32 public constant DEPLOYER_ROLE = bytes32("DEPLOYER");

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The beacon used to create new blocklists.
    address public immutable blockListBeacon;

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice The list of deployed blocklists.
    BlockList[] public deployedBlockLists;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when a new blocklist is created.
    /// @param blockList The address of the new blocklist.
    /// @param name The name of the new blocklist.
    event BlockListCreated(address indexed blockList, string name);

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor(address _initialAdmin, address _initialDeployer, uint48 _initialDelay, address _blockListBeacon)
        AccessControlDefaultAdminRules(_initialDelay, _initialAdmin)
    {
        if (_blockListBeacon.code.length == 0) revert AddressNotContract(_blockListBeacon);
        blockListBeacon = _blockListBeacon;

        _grantRole(DEPLOYER_ROLE, _initialDeployer);
    }

    /* -------------------------------------------------------------------------- */
    /*                                FACTORY LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Parameters for the `initialize()` function.
    struct CreateBlockListParams {
        string name_;
        ISanctionsList underlyingSanctionsList_;
        address initialDefaultAdmin_;
        address initialOperator_;
        uint48 initialDelay_;
    }

    /// @notice Creates a new blocklist.
    /// @param params The parameters to initialize the blocklist.
    /// @param salt The salt for the blocklist deployment with CREATE2.
    /// @return The address of the new blocklist.
    function createBlockList(CreateBlockListParams calldata params, bytes32 salt)
        external
        onlyRole(DEPLOYER_ROLE)
        returns (address)
    {
        BlockList.InitializationParams memory initializationParams = BlockList.InitializationParams({
            name_: params.name_,
            underlyingSanctionsList_: params.underlyingSanctionsList_,
            initialDefaultAdmin_: params.initialDefaultAdmin_,
            initialOperator_: params.initialOperator_,
            initialDelay_: params.initialDelay_
        });
        bytes memory _initCalldata = abi.encodeCall(BlockList.initialize, initializationParams);

        address _newBlockList = Create2.deploy(
            0,
            salt,
            abi.encodePacked(type(BlockListBeaconProxy).creationCode, abi.encode(blockListBeacon, _initCalldata))
        );

        deployedBlockLists.push(BlockList(_newBlockList));
        emit BlockListCreated(_newBlockList, initializationParams.name_);
        return _newBlockList;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    function getDeployedBlockLists() public view returns (BlockList[] memory) {
        return deployedBlockLists;
    }
}

```

### src/ConnectorRegistry.sol

```solidity
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

import {AccessControlDefaultAdminRules} from "@openzeppelin/access/extensions/AccessControlDefaultAdminRules.sol";
import {SafeCast} from "@openzeppelin/utils/math/SafeCast.sol";

import {
    AddressNotContract,
    AmountZero,
    ConnectorAlreadyExists,
    ConnectorDoesNotExist,
    ConnectorFrozen,
    ConnectorNotPaused,
    ConnectorPaused,
    InvalidDuration
} from "./libraries/Errors.sol";
import {IConnectorRegistry} from "./interfaces/IConnectorRegistry.sol";

/// @title ConnectorRegistry
/// @notice A contract that allows to register connectors to interact with protocols.
/// @author maximebrugel @ Kiln
contract ConnectorRegistry is IConnectorRegistry, AccessControlDefaultAdminRules {
    using SafeCast for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the pauser role.
    bytes32 public constant PAUSER_ROLE = bytes32("PAUSER");

    /// @notice The role code for the unpauser role.
    bytes32 public constant UNPAUSER_ROLE = bytes32("UNPAUSER");

    /// @notice The role code for the freezer role.
    bytes32 public constant FREEZER_ROLE = bytes32("FREEZER");

    /// @notice The role code for the connector manager role.
    bytes32 public constant CONNECTOR_MANAGER_ROLE = bytes32("CONNECTOR_MANAGER");

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Information on a connector
    /// @param _address The address of the connector.
    /// @param pauseTimestamp The timestamp at which the connector will be unpaused.
    /// @param frozen The frozen status of the connector.
    ///        If the timestamp is 0 or below block.timestamp the connector is not paused.
    struct ConnectorInfo {
        address _address;
        uint88 pauseTimestamp;
        bool frozen;
    }

    /// @dev The mapping of the connector name to the connector in in one slot.
    mapping(bytes32 => ConnectorInfo) public connectorInfo;

    /* -------------------------------------------------------------------------- */
    /*                                  GETTERS                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Get the address of a connector.
    /// @param name The name of the connector.
    /// @return connector The address of the connector.
    function connectorAddress(bytes32 name) public view returns (address) {
        return connectorInfo[name]._address;
    }

    /// @notice Get the frozen status of a connector.
    /// @param name The name of the connector.
    /// @return frozen The frozen status of the connector.
    function frozen(bytes32 name) public view returns (bool) {
        return connectorInfo[name].frozen;
    }

    /// @notice Get the pause timestamp of a connector.
    /// @param name The name of the connector.
    /// @return pauseTimestamp The pause timestamp of the connector.
    function pauseTimestamp(bytes32 name) public view returns (uint256) {
        return connectorInfo[name].pauseTimestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when a connector is added.
    /// @param name The name of the connector.
    /// @param connector The address of the connector.
    event ConnectorAdded(bytes32 indexed name, address indexed connector);

    /// @dev Emitted when a connector is updated.
    /// @param name The name of the connector.
    /// @param connector The address of the connector.
    event ConnectorUpdated(bytes32 indexed name, address indexed connector);

    /// @dev Emitted when a connector is removed.
    /// @param name The name of the connector.
    event ConnectorRemoved(bytes32 indexed name);

    /// @dev Emitted when a connector is paused.
    /// @param name The name of the connector.
    /// @param timestamp The timestamp at which the connector will be unpaused.
    event Paused(bytes32 indexed name, uint256 timestamp);

    /// @dev Emitted when a connector is unpaused.
    /// @param name The name of the connector.
    event Unpaused(bytes32 indexed name);

    /// @dev Emitted when a connector is frozen.
    /// @param name The name of the connector.
    event Frozen(bytes32 indexed name);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the connector is paused.
    /// @param name The name of the connector.
    modifier whenNotPaused(bytes32 name) {
        if (paused(name)) revert ConnectorPaused(name);
        _;
    }

    /// @dev Throws if the connector is frozen.
    /// @param name The name of the connector.
    modifier whenNotFrozen(bytes32 name) {
        if (connectorInfo[name].frozen) revert ConnectorFrozen(name);
        _;
    }

    /// @dev Throws if the connector id does not exist.
    /// @param name The name of the connector.
    modifier exists(bytes32 name) {
        if (!connectorExists(name)) revert ConnectorDoesNotExist(name);
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor(
        address initialAdmin,
        address initialPauser,
        address initialUnpauser,
        address initialFreezer,
        address initialConnectorManager,
        uint48 initialDelay
    ) AccessControlDefaultAdminRules(initialDelay, initialAdmin) {
        _grantRole(PAUSER_ROLE, initialPauser);
        _grantRole(UNPAUSER_ROLE, initialUnpauser);
        _grantRole(FREEZER_ROLE, initialFreezer);
        _grantRole(CONNECTOR_MANAGER_ROLE, initialConnectorManager);
    }

    /* -------------------------------------------------------------------------- */
    /*                               REGISTRY LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IConnectorRegistry
    function get(bytes32 name) external view override exists(name) returns (address) {
        return connectorInfo[name]._address;
    }

    /// @inheritdoc IConnectorRegistry
    function getOrRevert(bytes32 name) external view override whenNotPaused(name) exists(name) returns (address) {
        return connectorInfo[name]._address;
    }

    /// @inheritdoc IConnectorRegistry
    function connectorExists(bytes32 name) public view override returns (bool) {
        return connectorInfo[name]._address != address(0);
    }

    /// @inheritdoc IConnectorRegistry
    function paused(bytes32 name) public view override exists(name) returns (bool) {
        return connectorInfo[name].pauseTimestamp > block.timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 OWNER LOGIC                                */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IConnectorRegistry
    function add(bytes32 name, address connector) external override onlyRole(CONNECTOR_MANAGER_ROLE) {
        if (connectorExists(name)) revert ConnectorAlreadyExists(name, connector);
        if (connector.code.length == 0) revert AddressNotContract(connector);

        connectorInfo[name]._address = connector;
        emit ConnectorAdded(name, connector);
    }

    /// @inheritdoc IConnectorRegistry
    function update(bytes32 name, address connector)
        external
        override
        exists(name)
        whenNotFrozen(name)
        onlyRole(CONNECTOR_MANAGER_ROLE)
    {
        if (connector.code.length == 0) revert AddressNotContract(connector);
        connectorInfo[name]._address = connector;
        emit ConnectorUpdated(name, connector);
    }

    /// @inheritdoc IConnectorRegistry
    function remove(bytes32 name)
        external
        override
        exists(name)
        whenNotFrozen(name)
        whenNotPaused(name)
        onlyRole(CONNECTOR_MANAGER_ROLE)
    {
        delete connectorInfo[name];
        emit ConnectorRemoved(name);
    }

    /// @inheritdoc IConnectorRegistry
    function pause(bytes32 name) external override exists(name) onlyRole(PAUSER_ROLE) {
        connectorInfo[name].pauseTimestamp = type(uint88).max;
        emit Paused(name, type(uint256).max);
    }

    /// @inheritdoc IConnectorRegistry
    function pauseFor(bytes32 name, uint256 duration) external override exists(name) onlyRole(PAUSER_ROLE) {
        if (duration == 0) revert AmountZero();

        uint256 _newPauseTimestamp = block.timestamp + duration;
        uint256 _currentPauseTimestamp = connectorInfo[name].pauseTimestamp;
        if (_newPauseTimestamp <= _currentPauseTimestamp) {
            revert InvalidDuration(_newPauseTimestamp, _currentPauseTimestamp);
        }

        connectorInfo[name].pauseTimestamp = _newPauseTimestamp.toUint88();
        emit Paused(name, _newPauseTimestamp);
    }

    /// @inheritdoc IConnectorRegistry
    function unPause(bytes32 name) external override exists(name) onlyRole(UNPAUSER_ROLE) {
        if (!paused(name)) revert ConnectorNotPaused(name);
        connectorInfo[name].pauseTimestamp = 0;
        emit Unpaused(name);
    }

    /// @inheritdoc IConnectorRegistry
    function freeze(bytes32 name) external override exists(name) whenNotFrozen(name) onlyRole(FREEZER_ROLE) {
        connectorInfo[name].frozen = true;
        emit Frozen(name);
    }
}

```

### src/Errors.sol

```solidity
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

/* --------------------------------- Common --------------------------------- */

/// @dev Error emitted when the address is zero.
error AddressZero();

/// @dev Error emitted when the address is not a contract.
/// @param addr The address that was attempted to be used as a contract.
error AddressNotContract(address addr);

/// @dev Error emitted when a given amount is zero.
error AmountZero();

/// @dev Error emitted when two array lengths do not match.
error ArrayMismatch();

/// @dev Error emitted when the array is empty.
error EmptyArray();

/// @dev Error emitted when the duration to pause for is invalid
///      (before the current pauseTimestamp).
/// @param timestamp The timestamp to pause for.
error InvalidDuration(uint256 timestamp, uint256 currentTimestamp);

/// @dev Error emitted when the claim function is not available on the connector or
///      no additional rewards to claim at the moment.
error NothingToClaim();

/* ----------------------- VaultUpgradeableBeacon.sol ----------------------- */

/// @dev The `implementation` of the beacon is invalid.
/// @param implementation The address of the implementation that was attempted to be set.
error BeaconInvalidImplementation(address implementation);

/// @dev Error emitted when an operation is attempted on a paused contract.
error isPaused();

/// @dev Error emitted when an operation is attempted on a not paused contract.
error isNotPaused();

/// @dev Error emitted when an operation is attempted on a frozen contract.
error isFrozen();

/* -------------------------------- Vault.sol ------------------------------- */

/// @dev Error emitted when the ERC4626 is not transferable.
error NotTransferable();

/// @dev Error emitted when the management fee over 100%.
error WrongManagementFee(uint256 managementFee);

/// @dev Error emitted when the performance fee over 100%.
error WrongPerformanceFee(uint256 performanceFee);

/// @dev Error emitted when the connector name is invalid (not existing on the registry).
error InvalidConnectorName(bytes32 name);

/// @dev Error emitted when no rewards could be collected.
error NothingToCollect();

/// @dev Error emitted when a call is not a delegate call.
error NotDelegateCall();

/// @dev Error emitted when the preview result is zero (shares or assets).
error PreviewZero();

/// @dev Error emitted when the given address is on the sanction list.
error AddressSanctioned(address addr);

/// @dev Error emitted when the total assets decreased.
error TotalAssetsDecreased(uint256 totalAssets, uint256 newTotalAssets);

/// @dev Error emitted when no additional rewards claimed (using the claim function).
error NoAdditionalRewardsClaimed();

/// @dev Error emitted when the deposit is paused.
error DepositPaused();

/// @dev Error emmited when the offset set is too high.
error OffsetTooHigh(uint8 offset);

/// @dev Error emitted when the remainder of transferred shares is not zero.
error RemainderNotZero(uint256 shares);

/// @dev Error emitted when the minimum totalSupply is not met after a deposit.
error MinimumTotalSupplyNotReached();

/* --------------------------- ConnectorRegistry.sol ------------------------- */

/// @dev Error emitted when the connector already exists.
/// @param name The name of the connector.
/// @param connector The address of the connector.
error ConnectorAlreadyExists(bytes32 name, address connector);

/// @dev Error emitted when the connector does not exist.
/// @param name The name of the connector.
error ConnectorDoesNotExist(bytes32 name);

/// @dev Error emitted when the connector is frozen.
/// @param name The name of the connector.
error ConnectorFrozen(bytes32 name);

/// @dev Error emitted when the connector is paused.
/// @param name The name of the connector.
error ConnectorPaused(bytes32 name);

/// @dev Error emitted when the connector is not paused.
/// @param name The name of the connector.
error ConnectorNotPaused(bytes32 name);

/* ---------------------------- FeeDispatcher.sol --------------------------- */

/// @dev Error emitted when a given fee recipient does not exist.
/// @param recipient The address of the given fee recipient.
error FeeRecipientDoesNotExist(address recipient);

/// @dev Error emitted when the total management fee split between the fee recipients is not 100%.
/// @param totalSplit The total management fee split.
error WrongManagementFeeSplit(uint256 totalSplit);

/// @dev Error emitted when the total performance fee split between the fee recipients is not 100%.
/// @param totalSplit The total performance fee split.
error WrongPerformanceFeeSplit(uint256 totalSplit);

/// @dev Error emitted when a fee recipient address is not unique (in the given array of fee recipients).
/// @param recipient The address of the fee recipient.
error FeeRecipientNotUnique(address recipient);

/* ---------------------------- VaultFactory.sol ---------------------------- */

/// @dev Error emitted when the deployer already exists.
/// @param deployer The address of the deployer.
error DeployerAlreadyExists(address deployer);

/// @dev Error emitted when the caller is not a deployer.
/// @param caller The address of the caller.
error NotDeployer(address caller);

/// @dev Error emitted when the deployer does not exist.
/// @param deployer The address of the deployer.
error InvalidDeployer(address deployer);

/* ----------------------------- *Connector.sol ----------------------------- */

/// @dev Error emitted when the given rewards asset is invalid.
/// @param asset The address of the invalid rewards asset.
error InvalidRewardsAsset(address asset);

/// @dev Error emitted when the given address is an invalid 4626.
/// @param addr The address of the invalid 4626.
error Invalid4626(address addr);

/* ------------------------ CompoundV2Connector.sol ------------------------- */

/// @dev Error emitted when the mint function fails.
error MintFailed();

/// @dev Error emitted when the redeem function fails.
error RedeemFailed();

/* ----------------------- MarketRegistry.sol ----------------------- */

/// @dev Error emitted when the market for a specific asset does not exist.
error InvalidAsset(address asset);

/// @dev Error emitted when an asset is already registered.
/// @param asset The address of the asset.
error AlreadyRegistered(address asset);

```

### src/ExternalAccessControl.sol

```solidity
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

import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";

import {NotDelegateCall} from "./libraries/Errors.sol";

/// @title External Access Control.
/// @notice A centralized access control contract for managing roles across multiple contracts.
/// @dev This contract externalizes role management, allowing multiple contracts to share a common access control system.
///      It is designed to be used with a proxy pattern and inherits from OpenZeppelin's AccessControlDefaultAdminRulesUpgradeable.
/// @author 0xpanoramix @ Kiln
contract ExternalAccessControl is AccessControlDefaultAdminRulesUpgradeable {
    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation (regardless of the context).
    address internal immutable _self = address(this);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
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

    /// @notice Initial custom role to be granted during the initialization.
    struct InitialRole {
        bytes32 role;
        address account;
    }

    /// @notice Parameters for the `initialize()` function.
    struct InitializationParams {
        address initialDefaultAdmin_;
        InitialRole initialRole_;
        uint48 initialDelay_;
    }

    /// @notice Initializes the contract in the proxy context.
    /// @param params The initialization parameters.
    function initialize(InitializationParams calldata params) public onlyDelegateCall initializer {
        __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialDefaultAdmin_);
        _grantRole(params.initialRole_.role, params.initialRole_.account);
    }
}

```

### src/FeeDispatcher.sol

```solidity
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

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    AddressZero,
    EmptyArray,
    FeeRecipientDoesNotExist,
    FeeRecipientNotUnique,
    NotDelegateCall,
    WrongDepositFeeSplit,
    WrongRewardFeeSplit
} from "./libraries/Errors.sol";
import {IFeeDispatcher} from "./interfaces/IFeeDispatcher.sol";
import {_MAX_PERCENT} from "./libraries/Constants.sol";

/// @title FeeDispatcher.
/// @notice Dispatches Vaults pending deposit and reward fees to the fee recipients.
/// @dev Using ERC-7201 standard.
/// @author maximebrugel @ Kiln.
contract FeeDispatcher is IFeeDispatcher, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation (regardless of the context).
    address internal immutable _self = address(this);

    /* -------------------------------------------------------------------------- */
    /*                               STORAGE (proxy)                              */
    /* -------------------------------------------------------------------------- */

    /// @notice The storage layout of the contract.
    /// @param _dispatches Mapping of all the dispatches with the vaults.
    struct FeeDispatcherStorage {
        mapping(address => IFeeDispatcher.Dispatch) _dispatches;
    }

    function _getFeeDispatcherStorage() private pure returns (FeeDispatcherStorage storage $) {
        assembly {
            $.slot := FeeDispatcherStorageLocation
        }
    }

    /// @dev The storage slot of the FeeDispatcherStorage struct in the proxy contract.
    ///      keccak256(abi.encode(uint256(keccak256("kiln.storage.feedispatcher")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FeeDispatcherStorageLocation =
        0xfdd5e928c3467d3da929a44639dde8d54e0576a04fec4ff333caa67a6f243300;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the pending deposit fee is dispatched to a recipient.
    /// @param vault The vault from which the deposit fee is dispatched.
    /// @param recipient The recipient of the deposit fee.
    /// @param depositFee The amount of the deposit fee dispatched.
    event DepositFeeDispatched(address indexed vault, address indexed recipient, uint256 depositFee);

    /// @dev Emitted when the pending reward fee is dispatched to a recipient.
    /// @param vault The vault from which the reward fee is dispatched.
    /// @param recipient The recipient of the reward fee.
    /// @param rewardFee The amount of the reward fee dispatched.
    event RewardFeeDispatched(address indexed vault, address indexed recipient, uint256 rewardFee);

    /// @dev Emitted when the fee recipients are set.
    /// @param vault The vault for which the fee recipients are set.
    /// @param feeRecipients The fee recipients (array of structs).
    event FeeRecipientsSet(address indexed vault, IFeeDispatcher.FeeRecipient[] feeRecipients);

    /// @dev Emitted reward fees are collected.
    /// @param vault The vault from which the reward fees are collected.
    /// @param rewardFeeAmount The amount of reward fees collected.
    event RewardFeesCollected(address indexed vault, uint256 rewardFeeAmount);

    /// @dev Emitted deposit fees are collected.
    /// @param vault The vault from which the deposit fees are collected.
    /// @param depositFeeAmount The amount of deposit fees collected.
    event DepositFeesCollected(address indexed vault, uint256 depositFeeAmount);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the call is not a delegate call.
    ///      Allow to check if the contract is called from a proxy.
    modifier onlyDelegateCall() {
        if (address(this) == _self) revert NotDelegateCall();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                              INITIALIZE LOGIC                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Initializes the contract in the proxy context.
    function initialize() public initializer onlyDelegateCall {
        _initialize();
    }

    /// @dev Internal logic to initialize the contract in the proxy context.
    function _initialize() internal {
        __ReentrancyGuard_init();
    }

    /* -------------------------------------------------------------------------- */
    /*                            FEE DISPATCHER LOGIC                            */
    /* -------------------------------------------------------------------------- */

    /// @dev Dispatch the pending deposit/reward fee to the fee recipients.
    /// @param asset The asset to dispatch the fees in.
    /// @param underlyingDecimals The number of decimals of the underlying asset.
    function dispatchFees(IERC20 asset, uint8 underlyingDecimals) external nonReentrant {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();

        uint256 _pendingDepositFee = $._dispatches[msg.sender]._pendingDepositFee;
        uint256 _pendingRewardFee = $._dispatches[msg.sender]._pendingRewardFee;
        uint256 _depositFeeTransferred;
        uint256 _rewardFeeTransferred;

        uint256 _recipientsLength = $._dispatches[msg.sender]._feeRecipients.length;
        IFeeDispatcher.FeeRecipient memory currentRecipient;
        for (uint256 i; i < _recipientsLength; i++) {
            currentRecipient = $._dispatches[msg.sender]._feeRecipients[i];

            if (_pendingDepositFee > 0) {
                // Compute the deposit fee amount for the current recipient (based on the deposit
                // fee split between all recipients).
                uint256 _depositFeeAmount =
                    _pendingDepositFee.mulDiv(currentRecipient.depositFeeSplit, _MAX_PERCENT * 10 ** underlyingDecimals);
                if (_depositFeeAmount > 0) {
                    asset.safeTransferFrom(msg.sender, currentRecipient.recipient, _depositFeeAmount);
                    _depositFeeTransferred += _depositFeeAmount;
                    emit DepositFeeDispatched(msg.sender, currentRecipient.recipient, _depositFeeAmount);
                }
            }

            if (_pendingRewardFee > 0) {
                // Compute the reward fee amount for the current recipient (based on the reward
                // fee split between all recipients).
                uint256 _rewardFeeAmount =
                    _pendingRewardFee.mulDiv(currentRecipient.rewardFeeSplit, _MAX_PERCENT * 10 ** underlyingDecimals);
                if (_rewardFeeAmount > 0) {
                    asset.safeTransferFrom(msg.sender, currentRecipient.recipient, _rewardFeeAmount);
                    _rewardFeeTransferred += _rewardFeeAmount;
                    emit RewardFeeDispatched(msg.sender, currentRecipient.recipient, _rewardFeeAmount);
                }
            }
        }
        $._dispatches[msg.sender]._pendingDepositFee = _pendingDepositFee - _depositFeeTransferred;
        $._dispatches[msg.sender]._pendingRewardFee = _pendingRewardFee - _rewardFeeTransferred;
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IFeeDispatcher
    function pendingDepositFee() public view returns (uint256) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._pendingDepositFee;
    }

    /// @inheritdoc IFeeDispatcher
    function pendingRewardFee() public view returns (uint256) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._pendingRewardFee;
    }

    /// @inheritdoc IFeeDispatcher
    function feeRecipients() public view returns (IFeeDispatcher.FeeRecipient[] memory) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._feeRecipients;
    }

    /// @inheritdoc IFeeDispatcher
    function feeRecipient(address recipient) public view returns (IFeeDispatcher.FeeRecipient memory) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        uint256 _recipientsLength = $._dispatches[msg.sender]._feeRecipients.length;
        for (uint256 i; i < _recipientsLength; i++) {
            if ($._dispatches[msg.sender]._feeRecipients[i].recipient == recipient) {
                return $._dispatches[msg.sender]._feeRecipients[i];
            }
        }
        revert FeeRecipientDoesNotExist(recipient);
    }

    /// @inheritdoc IFeeDispatcher
    function feeRecipientAt(uint256 index) public view returns (IFeeDispatcher.FeeRecipient memory) {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        return $._dispatches[msg.sender]._feeRecipients[index];
    }

    /* -------------------------------------------------------------------------- */
    /*                                   SETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IFeeDispatcher
    function incrementPendingDepositFee(uint256 amount) external {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        $._dispatches[msg.sender]._pendingDepositFee += amount;
        emit DepositFeesCollected(msg.sender, amount);
    }

    /// @inheritdoc IFeeDispatcher
    function incrementPendingRewardFee(uint256 amount) external {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();
        $._dispatches[msg.sender]._pendingRewardFee += amount;
        emit RewardFeesCollected(msg.sender, amount);
    }

    /// @dev Set the fee recipients.
    ///      The fee recipients must be unique and the total fee splits must be 100 * 10 ** underlyingDecimal (representing 100%).
    /// @param recipients The new fee recipients.
    /// @param underlyingDecimal The number of decimals of the underlying asset.
    function setFeeRecipients(IFeeDispatcher.FeeRecipient[] memory recipients, uint8 underlyingDecimal) external {
        FeeDispatcherStorage storage $ = _getFeeDispatcherStorage();

        if (recipients.length == 0) {
            revert EmptyArray();
        }

        delete $._dispatches[msg.sender]._feeRecipients;

        uint256 _totalDepositFeeSplit;
        uint256 _totalRewardFeeSplit;
        uint256 _recipientsLength = recipients.length;
        for (uint256 i; i < _recipientsLength; i++) {
            _totalDepositFeeSplit += recipients[i].depositFeeSplit;
            _totalRewardFeeSplit += recipients[i].rewardFeeSplit;

            if (recipients[i].recipient == address(0)) {
                revert AddressZero();
            }

            for (uint256 j = i + 1; j < _recipientsLength; j++) {
                if (recipients[i].recipient == recipients[j].recipient) {
                    revert FeeRecipientNotUnique(recipients[i].recipient);
                }
            }
            $._dispatches[msg.sender]._feeRecipients.push(recipients[i]);
        }
        if (_totalDepositFeeSplit != _MAX_PERCENT * 10 ** underlyingDecimal) {
            revert WrongDepositFeeSplit(_totalDepositFeeSplit);
        }
        if (_totalRewardFeeSplit != _MAX_PERCENT * 10 ** underlyingDecimal) {
            revert WrongRewardFeeSplit(_totalRewardFeeSplit);
        }
        emit FeeRecipientsSet(msg.sender, $._dispatches[msg.sender]._feeRecipients);
    }
}

```

### src/Vault.sol

```solidity
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

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {Address} from "@openzeppelin/utils/Address.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {IAccessControl} from "@openzeppelin/access/IAccessControl.sol";
import {
    ERC20Upgradeable,
    ERC4626Upgradeable
} from "@openzeppelin-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from
    "@openzeppelin-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {
    AmountZero,
    AddressNotContract,
    AddressBlocked,
    DepositPaused,
    InvalidConnectorName,
    MinimumTotalSupplyNotReached,
    NoAdditionalRewardsClaimed,
    NoAdditionalRewardsStrategy,
    NothingToCollect,
    NotTransferable,
    OffsetTooHigh,
    PreviewZero,
    RemainderNotZero,
    TotalAssetsDecreased,
    UnauthorizedSpender,
    WrongDepositFee,
    WrongRewardFee,
    AddressNotInternallySanctionedOnly,
    InsufficientLiquidity,
    NotConfiguredFactory
} from "./libraries/Errors.sol";
import {IConnector} from "./interfaces/IConnector.sol";
import {BlockList} from "./BlockList.sol";
import {IConnectorRegistry} from "./interfaces/IConnectorRegistry.sol";
import {IFeeDispatcher} from "./interfaces/IFeeDispatcher.sol";
import {_MAX_PERCENT} from "./libraries/Constants.sol";
import {ISelf} from "./interfaces/ISelf.sol";

/// @title Kiln DeFi Integration Vault.
/// @notice ERC-4626 Vault depositing assets into a protocol.
/// @author maximebrugel @ Kiln.
/// @dev Using ERC-7201 standard.
contract Vault is ERC4626Upgradeable, AccessControlDefaultAdminRulesUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address;
    using Math for uint256;

    /* -------------------------------------------------------------------------- */
    /*                                    ENUMS                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice The strategy to apply when additional rewards are collected.
    /// @param None No additional rewards are collected.
    /// @param Claim Additional rewards are claimed and transferred to the CLAIM_MANAGER.
    /// @param Reinvest Additional rewards are reinvested in the underlying protocol.
    enum AdditionalRewardsStrategy {
        None,
        Claim,
        Reinvest
    }

    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Represents the maximum fee that can be charged for reward and deposit fees.
    uint256 internal constant _MAX_FEE = 35;

    /// @dev Represents the maximum offset.
    uint8 internal constant _MAX_OFFSET = 23;

    /// @notice The role code for the fee manager.
    bytes32 public constant FEE_MANAGER_ROLE = bytes32("FEE_MANAGER");

    /// @notice The role code for fee collector.
    bytes32 public constant FEE_COLLECTOR_ROLE = bytes32("FEE_COLLECTOR");

    /// @notice The role code for the sanctions manager.
    bytes32 public constant SANCTIONS_MANAGER_ROLE = bytes32("SANCTIONS_MANAGER");

    /// @notice The role code for the claim manager.
    bytes32 public constant CLAIM_MANAGER_ROLE = bytes32("CLAIM_MANAGER");

    /// @notice The role code for the pauser role.
    bytes32 public constant PAUSER_ROLE = bytes32("PAUSER");

    /// @notice The role code for the unpauser role.
    bytes32 public constant UNPAUSER_ROLE = bytes32("UNPAUSER");

    /// @notice The role code for the spender role.
    /// @dev Only used in conjunction with ExternalAccessControl to verify if a user has this role.
    bytes32 public constant SPENDER_ROLE = bytes32("SPENDER");

    /* -------------------------------------------------------------------------- */
    /*                                  IMMUTABLE                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation (regardless of the context).
    address internal immutable _self = address(this);

    /// @dev The external access control proxy contract.
    IAccessControl internal immutable _externalAccessControl;

    /// @dev The factory address.
    address public immutable vaultFactory;

    /* -------------------------------------------------------------------------- */
    /*                               STORAGE (proxy)                              */
    /* -------------------------------------------------------------------------- */

    /// @notice The storage layout of the contract.
    /// @param _connectorRegistry The connector registry address.
    /// @param _connectorName The name of the connector used by the vault to interact with the proper protocol.
    /// @param _depositFee The deposit fee (between 0 and 100, scaled to the underlying asset decimals).
    /// @param _rewardFee The reward fee (between 0 and 100, scaled to the underlying asset decimals).
    /// @param _lastTotalAssets The last amount of the underlying asset that is “managed” by the vault.
    /// @param _minTotalSupply The minimum total supply of the vault shares.
    /// @param _transferable True if the vault shares are transferable, False if not.
    /// @param _offset The offset (inflation attack mitigation).
    /// @param _collectableRewardFeesShares The amount of reward fees shares that can be collected by the FeeManager.
    /// @param _blockList The blocklist contract.
    /// @param _depositPaused True if the deposits are paused, False if not.
    /// @param _additionalRewardsStrategy The strategy to apply when additional rewards are collected
    /// @param _feeDispatcher The fee dispatcher contract.
    struct VaultStorage {
        IConnectorRegistry _connectorRegistry;
        bytes32 _connectorName;
        uint256 _depositFee;
        uint256 _rewardFee;
        uint256 _lastTotalAssets;
        uint256 _minTotalSupply;
        bool _transferable;
        uint8 _offset;
        uint256 _collectableRewardFeesShares;
        BlockList _blockList;
        bool _depositPaused;
        AdditionalRewardsStrategy _additionalRewardsStrategy;
        IFeeDispatcher _feeDispatcher;
    }

    function _getVaultStorage() private pure returns (VaultStorage storage $) {
        assembly {
            $.slot := VaultStorageLocation
        }
    }

    /// @dev The storage slot of the VaultStorage struct in the proxy contract.
    ///      keccak256(abi.encode(uint256(keccak256("kiln.storage.vault")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VaultStorageLocation = 0x6bb5a2a0ae924c2ea94f037035a09f65614421e2a7d96c9bcbd59acdd32e6000;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the additional rewards strategy is updated.
    /// @param newAdditionalRewardsStrategy The new additional rewards strategy.
    event AdditionalRewardsStrategyUpdated(AdditionalRewardsStrategy newAdditionalRewardsStrategy);

    /// @dev Emitted when the deposit fee is updated.
    /// @param newDepositFee The new deposit fee.
    event DepositFeeUpdated(uint256 newDepositFee);

    /// @dev Emitted when the reward fee is updated.
    /// @param newRewardFee The new reward fee.
    event RewardFeeUpdated(uint256 newRewardFee);

    /// @dev Emitted when the connector registry is updated.
    /// @param newConnectorRegistry The new connector registry.
    event ConnectorRegistryUpdated(IConnectorRegistry newConnectorRegistry);

    /// @dev Emitted when the connector name is updated.
    /// @param newConnectorName The new connector name.
    event ConnectorNameUpdated(bytes32 newConnectorName);

    /// @dev Emitted when the transferable flag is updated.
    /// @param newTransferableFlag The new transferable flag.
    event TransferableUpdated(bool newTransferableFlag);

    /// @dev Emitted when the ERC4626 name is initialized.
    /// @param name The name of the ERC4626.
    event NameInitialized(string name);

    /// @dev Emitted when the ERC4626 symbol is initialized.
    /// @param symbol The symbol of the ERC4626.
    event SymbolInitialized(string symbol);

    /// @dev Emitted when an asset is initialized.
    /// @param asset The (ERC20) asset that is initialized.
    event AssetInitialized(IERC20 asset);

    /// @dev Emitted when the offset is initialized.
    /// @param offset The offset.
    event OffsetInitialized(uint8 offset);

    /// @dev Emitted when the fee dispatcher is initialized.
    /// @param feeDispatcher The fee dispatcher.
    event FeeDispatcherInitialized(address feeDispatcher);

    /// @dev Emitted when minimum supply state is updated.
    /// @param newMinTotalSupply The new minimum supply state.
    event MinTotalSupplyInitialized(uint256 newMinTotalSupply);

    /// @dev Emitted when the blocklist is updated.
    /// @param newBlockList The new blocklist.
    event BlockListUpdated(BlockList newBlockList);

    /// @dev Emitted when additional rewards are claimed to the underlying protocol.
    /// @param rewardsAsset The rewards asset claimed.
    /// @param amount The amount distributed to the vault.
    event RewardsClaimed(address indexed rewardsAsset, uint256 amount);

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the given address is sanctioned.
    ///      If the blocklist is not set, the check is skipped.
    /// @param addr The address to check.
    modifier notBlocked(address addr) {
        _notBlocked(addr);
        _;
    }

    /// @dev Throws if the deposit is paused.
    modifier whenDepositNotPaused() {
        _whenDepositNotPaused();
        _;
    }

    /// @dev Throws if the transferability involving a targeted address is not allowed.
    /// @param target The targeted address.
    modifier checkTransferability(address target) {
        _checkTransferability(target);
        _;
    }

    /// @dev Throws if the caller is not the fee manager.
    modifier onlyFactory() {
        _onlyFactory();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                             INTERNAL MODIFIERS                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Internal modifier logic to check if the given address is blocked.
    /// @param addr The address to check.
    function _notBlocked(address addr) internal view {
        BlockList _blockList = _getVaultStorage()._blockList;
        if (address(_blockList) != address(0) && _blockList.isBlocked(addr)) {
            revert AddressBlocked(addr);
        }
    }

    /// @dev Internal modifier logic to check if the deposit is paused.
    function _whenDepositNotPaused() internal view {
        if (_getVaultStorage()._depositPaused) revert DepositPaused();
    }

    /// @dev Internal logic to check if transferability involving a given address is allowed.
    ///      If the vault is not transferable, the sender or the targeted address must have the SPENDER_ROLE
    ///      (on the ExternalAccessControl).
    /// @param target The target address to check (spender, recipient,...).
    function _checkTransferability(address target) internal view {
        if (
            !_getVaultStorage()._transferable && target != _msgSender()
                && (
                    !_externalAccessControl.hasRole(SPENDER_ROLE, _msgSender())
                        && !_externalAccessControl.hasRole(SPENDER_ROLE, target)
                )
        ) {
            revert NotTransferable();
        }
    }

    /// @dev Internal modifier logic to check if the sender is the factory.
    function _onlyFactory() internal view {
        if (_msgSender() != vaultFactory) revert NotConfiguredFactory(_msgSender());
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Initializes the Vault contract (implementation).
    /// @param externalAccessControl_ The external access control proxy contract.
    constructor(address externalAccessControl_, address vaultFactory_) {
        _externalAccessControl = IAccessControl(externalAccessControl_);
        vaultFactory = vaultFactory_;
    }

    /* -------------------------------------------------------------------------- */
    /*                              INITIALIZE LOGIC                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Parameters for the `initialize()` function.
    struct InitializationParams {
        IERC20 asset_;
        string name_;
        string symbol_;
        bool transferable_;
        IConnectorRegistry connectorRegistry_;
        bytes32 connectorName_;
        uint256 depositFee_;
        uint256 rewardFee_;
        address initialDefaultAdmin_;
        address initialFeeManager_;
        address initialSanctionsManager_;
        address initialClaimManager_;
        address initialPauser_;
        address initialUnpauser_;
        uint48 initialDelay_;
        uint8 offset_;
        uint256 minTotalSupply_;
    }

    /// @notice Initializes the contract in the proxy context.
    /// @dev The initialization is split into two steps:
    ///      1. Initialize the Vault (what's required for a new deployment).
    ///      2. Upgrade the Vault (what's required for an existing Vault upgrade).
    /// @param initializationParams The initialization parameters (first step)
    /// @param upgradeParams The upgrade parameters (second step).
    function initialize(InitializationParams calldata initializationParams, UpgradeParams calldata upgradeParams)
        public
        onlyFactory
    {
        _initialize(initializationParams);
        _upgrade(upgradeParams);
    }

    /// @dev Internal logic to initialize the contract in the proxy context.
    /// @param params The initialization parameters.
    function _initialize(InitializationParams calldata params) internal initializer {
        __ERC4626_init(params.asset_);
        emit AssetInitialized(params.asset_);

        __ERC20_init(params.name_, params.symbol_);
        emit NameInitialized(params.name_);
        emit SymbolInitialized(params.symbol_);

        __ReentrancyGuard_init();
        __AccessControlDefaultAdminRules_init(params.initialDelay_, params.initialDefaultAdmin_);

        __Vault_init(params);
    }

    function __Vault_init(InitializationParams calldata params) internal onlyInitializing {
        _setOffset(params.offset_);
        _setRewardFee(params.rewardFee_);
        _setDepositFee(params.depositFee_);
        _setConnectorRegistry(params.connectorRegistry_);
        _setConnectorName(params.connectorName_);
        _setTransferable(params.transferable_);
        _setMinTotalSupply(params.minTotalSupply_);
        _grantRole(FEE_MANAGER_ROLE, params.initialFeeManager_);
        _grantRole(SANCTIONS_MANAGER_ROLE, params.initialSanctionsManager_);
        _grantRole(CLAIM_MANAGER_ROLE, params.initialClaimManager_);
        _grantRole(PAUSER_ROLE, params.initialPauser_);
        _grantRole(UNPAUSER_ROLE, params.initialUnpauser_);
    }

    /* -------------------------------------------------------------------------- */
    /*                                UPGRADE LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Parameters for the `upgrade()` function.
    struct UpgradeParams {
        IFeeDispatcher.FeeRecipient[] recipients_;
        address feeDispatcher_;
        AdditionalRewardsStrategy additionalRewardsStrategy_;
        BlockList blockList_;
        uint256 pendingDepositFee_;
        uint256 pendingRewardFee_;
        IConnectorRegistry connectorRegistry_;
        address initialFeeCollector_;
    }

    /// @notice Upgrades the contract in the proxy context.
    /// @param upgradeParams The upgrade parameters for the upgrade.
    function upgrade(UpgradeParams calldata upgradeParams) public onlyFactory {
        _upgrade(upgradeParams);
    }

    /// @dev Internal logic to upgrade the contract in the proxy context.
    /// @param params The upgrade parameters.
    function _upgrade(UpgradeParams calldata params) internal reinitializer(2) {
        __Vault_upgrade(params);
    }

    function __Vault_upgrade(UpgradeParams calldata params) internal onlyInitializing {
        _setBlockList(params.blockList_);
        _setAdditionalRewardsStrategy(params.additionalRewardsStrategy_);
        _setFeeDispatcher(params.feeDispatcher_);
        IFeeDispatcher(params.feeDispatcher_).incrementPendingDepositFee(params.pendingDepositFee_);
        IFeeDispatcher(params.feeDispatcher_).incrementPendingRewardFee(params.pendingRewardFee_);
        IFeeDispatcher(params.feeDispatcher_).setFeeRecipients(params.recipients_, _underlyingDecimals());
        _grantRole(FEE_COLLECTOR_ROLE, params.initialFeeCollector_);
        _setConnectorRegistry(params.connectorRegistry_);
        SafeERC20.forceApprove(IERC20(asset()), params.feeDispatcher_, type(uint256).max);
    }

    /// @notice Perform an arbitrary delegatecall to the factory.
    ///         Needed for migration purposes (e.g. to access an unused storage slot).
    /// @dev Only the factory can call this function, and will handle the callback.
    /// @param data The data to delegatecall.
    function delegateToFactory(bytes calldata data) external onlyFactory returns (bytes memory) {
        return ISelf(vaultFactory)._self().functionDelegateCall(data);
    }

    /* -------------------------------------------------------------------------- */
    /*                           ERC4626 (PUBLIC) LOGIC                           */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ERC4626Upgradeable
    function totalAssets() public view override returns (uint256) {
        return _getConnector().totalAssets(IERC20Metadata(asset()));
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxDeposit(address) public view override returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        if ($._connectorRegistry.paused($._connectorName) || $._depositPaused) {
            return 0;
        }
        return _maxDeposit();
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxMint(address) public view override returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        if ($._connectorRegistry.paused($._connectorName) || $._depositPaused) {
            return 0;
        }
        return _maxMint(totalAssets(), totalSupply());
    }

    /// @inheritdoc ERC4626Upgradeable
    function maxWithdraw(address owner) public view override returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        if ($._connectorRegistry.paused($._connectorName)) {
            return 0;
        }
        return _maxWithdraw(owner);
    }

    // @inheritdoc ERC4626Upgradeable
    function maxRedeem(address owner) public view override returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        if ($._connectorRegistry.paused($._connectorName)) {
            return 0;
        }
        return _maxRedeem(owner, totalAssets(), totalSupply());
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewDeposit(uint256 assets) public view override returns (uint256) {
        (uint256 _rewardFeeShares, uint256 _newTotalAssets) = _accruedRewardFeeShares();
        (uint256 _shares,) = _previewDeposit(assets, _newTotalAssets, totalSupply() + _rewardFeeShares);
        return _shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewMint(uint256 shares) public view override returns (uint256) {
        (uint256 _rewardFeeShares, uint256 _newTotalAssets) = _accruedRewardFeeShares();
        (uint256 _assets,) = _previewMint(shares, _newTotalAssets, totalSupply() + _rewardFeeShares);
        return _assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        (uint256 _rewardFeeShares, uint256 _newTotalAssets) = _accruedRewardFeeShares();

        return _roundDownPartialShares(
            assets.mulDiv(
                totalSupply() + _rewardFeeShares + 10 ** _decimalsOffset(), _newTotalAssets + 1, Math.Rounding.Ceil
            )
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        (uint256 _rewardFeeShares, uint256 _newTotalAssets) = _accruedRewardFeeShares();

        return shares.mulDiv(
            _newTotalAssets + 1, totalSupply() + _rewardFeeShares + 10 ** _decimalsOffset(), Math.Rounding.Floor
        );
    }

    /// @inheritdoc ERC4626Upgradeable
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        checkTransferability(receiver)
        notBlocked(_msgSender())
        whenDepositNotPaused
        returns (uint256)
    {
        if (assets == 0) revert AmountZero();

        uint256 _maxAssets = _maxDeposit();
        if (assets > _maxAssets) revert ERC4626ExceededMaxDeposit(receiver, assets, _maxAssets);

        uint256 _newTotalAssets = _accrueRewardFee();

        (uint256 _shares, uint256 _depositFeeAmount) = _previewDeposit(assets, _newTotalAssets, totalSupply());
        if (_shares == 0) revert PreviewZero();

        _deposit(_msgSender(), receiver, assets, _shares, _depositFeeAmount);

        return _shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function mint(uint256 shares, address receiver)
        public
        override
        nonReentrant
        checkTransferability(receiver)
        notBlocked(_msgSender())
        whenDepositNotPaused
        returns (uint256)
    {
        if (shares == 0) revert AmountZero();
        _checkPartialShares(shares);

        uint256 _newTotalAssets = _accrueRewardFee();
        uint256 _newTotalSupply = totalSupply();

        uint256 _maxShares = _maxMint(_newTotalAssets, _newTotalSupply);
        if (shares > _maxShares) revert ERC4626ExceededMaxMint(receiver, shares, _maxShares);

        (uint256 _assets, uint256 _depositFeeAmount) = _previewMint(shares, _newTotalAssets, _newTotalSupply);
        if (_assets == 0) revert PreviewZero();

        _deposit(_msgSender(), receiver, _assets, shares, _depositFeeAmount);

        return _assets;
    }

    /// @inheritdoc ERC4626Upgradeable
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        nonReentrant
        checkTransferability(receiver)
        checkTransferability(owner)
        notBlocked(_msgSender())
        notBlocked(owner)
        returns (uint256)
    {
        if (assets == 0) revert AmountZero();

        uint256 _maxAssets = _maxWithdraw(owner);
        if (assets > _maxAssets) revert ERC4626ExceededMaxWithdraw(owner, assets, _maxAssets);

        uint256 _shares = _convertToShares(assets, Math.Rounding.Ceil, _accrueRewardFee(), totalSupply());
        if (_shares == 0) revert PreviewZero();
        _shares = _roundDownPartialShares(_shares);
        _withdraw(_msgSender(), receiver, owner, assets, _shares);

        return _shares;
    }

    /// @inheritdoc ERC4626Upgradeable
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        nonReentrant
        checkTransferability(receiver)
        checkTransferability(owner)
        notBlocked(_msgSender())
        notBlocked(owner)
        returns (uint256)
    {
        if (shares == 0) revert AmountZero();
        _checkPartialShares(shares);

        uint256 _newTotalAssets = _accrueRewardFee();
        uint256 _newTotalSupply = totalSupply();

        {
            uint256 _maxShares = _maxRedeem(owner, _newTotalAssets, _newTotalSupply);
            if (shares > _maxShares) {
                revert ERC4626ExceededMaxRedeem(owner, shares, _maxShares);
            }
        }

        uint256 _assets = _convertToAssets(shares, Math.Rounding.Floor, _newTotalAssets, _newTotalSupply);
        if (_assets == 0) revert PreviewZero();
        _withdraw(_msgSender(), receiver, owner, _assets, shares);

        return _assets;
    }

    /* -------------------------------------------------------------------------- */
    /*                          ERC4626 (INTERNAL) LOGIC                          */
    /* -------------------------------------------------------------------------- */

    /// @dev Variant of ERC4626Upgradeable's _deposit but taking the deposit fee amount.
    ///      See ERC4626Upgradeable.
    /// @param caller The caller of the function.
    /// @param receiver The receiver of the minted shares.
    /// @param assets The amount of assets to deposit.
    /// @param shares The number of shares to mint.
    /// @param depositFeeAmount The amount of deposit fee in asset terms, calculated based on the deposit amount.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares, uint256 depositFeeAmount)
        internal
    {
        uint256 _balanceBefore = IERC20(asset()).balanceOf(address(this));
        SafeERC20.safeTransferFrom(IERC20(asset()), caller, address(this), assets);
        _mint(receiver, shares);

        VaultStorage storage $ = _getVaultStorage();

        if (totalSupply() < $._minTotalSupply) revert MinimumTotalSupplyNotReached();

        // Deposit to underlying protocol
        address _connector = $._connectorRegistry.getOrRevert($._connectorName);
        _connector.functionDelegateCall(
            abi.encodeCall(
                IConnector.deposit,
                (IERC20(asset()), IERC20(asset()).balanceOf(address(this)) - _balanceBefore - depositFeeAmount)
            )
        );

        $._lastTotalAssets = totalAssets();
        $._feeDispatcher.incrementPendingDepositFee(depositFeeAmount);

        emit Deposit(caller, receiver, assets, shares);
    }

    /// @dev Variant of ERC4626Upgradeable's _withdraw. See ERC4626Upgradeable.
    /// @param caller The caller of the function.
    /// @param receiver The receiver of the withdrawn assets.
    /// @param owner The owner of the shares to redeem.
    /// @param assets The amount of assets to withdraw from the underlying protocol.
    /// @param shares The number of shares to burn.
    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }
        _burn(owner, shares);

        // Withdraw from underlying protocol
        VaultStorage storage $ = _getVaultStorage();
        address _connector = $._connectorRegistry.getOrRevert($._connectorName);
        uint256 _balanceBefore = IERC20(asset()).balanceOf(address(this));
        _connector.functionDelegateCall(abi.encodeCall(IConnector.withdraw, (IERC20(asset()), assets)));

        SafeERC20.safeTransfer(IERC20(asset()), receiver, IERC20(asset()).balanceOf(address(this)) - _balanceBefore);

        $._lastTotalAssets = totalAssets();

        emit Withdraw(caller, receiver, owner, assets, shares);
    }

    /// @dev Internal function to retrieve the max depositable amount.
    ///      Calls the connector to get the max depositable amount for the asset (e.g. the supply cap).
    function _maxDeposit() internal view returns (uint256) {
        return _getConnector().maxDeposit(IERC20(asset()));
    }

    /// @dev Internal function to retrieve the max mintable amount.
    /// @param newTotalAssets The Vault's total assets.
    /// @param newTotalSupply The (shares) total supply.
    function _maxMint(uint256 newTotalAssets, uint256 newTotalSupply) internal view returns (uint256) {
        uint256 _maxDepositable = _maxDeposit();

        if (_maxDepositable == type(uint256).max) {
            return type(uint256).max;
        }

        return _convertToShares(_maxDepositable, Math.Rounding.Floor, newTotalAssets, newTotalSupply);
    }

    /// @dev Internal function to retrieve the max withdrawable amount for a given owner.
    /// @param owner The owner of the shares.
    function _maxWithdraw(address owner) internal view returns (uint256) {
        return Math.min(_getConnector().maxWithdraw(IERC20(asset())), previewRedeem(balanceOf(owner)));
    }

    /// @dev Internal function to retrieve the max redeemable amount for a given owner.
    /// @param owner The owner of the shares.
    /// @param newTotalAssets The Vault's total assets.
    /// @param newTotalSupply The (shares) total supply.
    function _maxRedeem(address owner, uint256 newTotalAssets, uint256 newTotalSupply)
        internal
        view
        returns (uint256)
    {
        uint256 _maxWithdrawable = _getConnector().maxWithdraw(IERC20(asset()));

        if (_maxWithdrawable == type(uint256).max) {
            return balanceOf(owner);
        }

        return Math.min(
            _convertToShares(_maxWithdrawable, Math.Rounding.Floor, newTotalAssets, newTotalSupply), balanceOf(owner)
        );
    }

    /// @dev Estimates the number of shares mintable from a given deposit and the associated deposit fee.
    /// @param assets The amount of assets to deposit.
    /// @param newTotalAssets The Vault's total assets
    /// @param supply The (shares) total supply.
    /// @return shares The number of shares that can be minted from the deposited assets, after deducting the deposit fee.
    /// @return depositFeeAmount The amount of deposit fee in asset terms, calculated based on the deposit amount.
    function _previewDeposit(uint256 assets, uint256 newTotalAssets, uint256 supply)
        internal
        view
        returns (uint256 shares, uint256 depositFeeAmount)
    {
        VaultStorage storage $ = _getVaultStorage();

        // Calculate the deposit fee amount.
        // This is a portion of the deposited assets, scaled by the deposit fee rate and adjusted for the asset's decimals.
        depositFeeAmount = assets.mulDiv($._depositFee, _MAX_PERCENT * 10 ** _underlyingDecimals());

        // Convert the net asset amount (after deducting the deposit fee) to shares.
        // The conversion uses floor rounding to determine the number of shares that can be minted.
        // If partial shares are emitted, they are rounded down to the nearest whole number.
        shares = _roundDownPartialShares(
            _convertToShares(assets - depositFeeAmount, Math.Rounding.Floor, newTotalAssets, supply)
        );
    }

    /// @dev Estimates the asset amount and deposit fee for minting a specified number of shares.
    /// @param shares The number of shares to be minted.
    /// @param newTotalAssets The Vault's total assets.
    /// @param supply The (shares) total supply.
    /// @return assets The total amount of assets required to mint the specified number of shares, including the deposit fee.
    /// @return depositFeeAmount The amount of deposit fee in asset terms deducted when minting the shares.
    function _previewMint(uint256 shares, uint256 newTotalAssets, uint256 supply)
        internal
        view
        returns (uint256 assets, uint256 depositFeeAmount)
    {
        VaultStorage storage $ = _getVaultStorage();
        uint256 _depositFee = $._depositFee;
        uint256 _decimals = _underlyingDecimals();

        // Convert the number of shares to assets with ceiling rounding.
        // This gives us a raw asset value equivalent to the shares before considering deposit fees.
        uint256 _rawAssetValue = _convertToAssets(shares, Math.Rounding.Ceil, newTotalAssets, supply);

        // To ensure accuracy in calculations, it's necessary to scale values up.
        uint256 _scaledRawAssetValue = _rawAssetValue * 10 ** _decimals;

        // The deposit fee is deducted from the maximum percent scale adjusted for decimals.
        uint256 _adjustedMaxPercent = (_MAX_PERCENT * 10 ** _decimals) - _depositFee;

        // Calculate the assets required to mint the shares, including the deposit fee.
        //
        //            _MAX_PERCENT * (_rawAssetValue * 10 ** decimals)
        // assets = -----------------------------------------------------
        //             (_MAX_PERCENT * 10 ** decimals) - _depositFee
        //
        // Note: _depositFee is already scaled to asset decimals.
        //
        assets = _scaledRawAssetValue.mulDiv(_MAX_PERCENT, _adjustedMaxPercent, Math.Rounding.Ceil);

        // Calculate the deposit fee amount from the assets required to mint the shares.
        depositFeeAmount = assets.mulDiv(_depositFee, _MAX_PERCENT * 10 ** _decimals, Math.Rounding.Floor);
    }

    /// @dev Variant of  _convertToShares from ERC4626Upgradeable but taking the totalAssets/totalSupply
    ///      parameters instead of calling `totalAssets()` and `totalSupply()`.
    function _convertToShares(uint256 assets, Math.Rounding rounding, uint256 total, uint256 supply)
        internal
        view
        returns (uint256)
    {
        return assets.mulDiv(supply + 10 ** _decimalsOffset(), total + 1, rounding);
    }

    /// @dev Variant of _convertToAssets from ERC4626Upgradeable but taking the totalAssets/totalSupply
    ///      parameters instead of calling `totalAssets()` and `totalSupply()`.
    function _convertToAssets(uint256 shares, Math.Rounding rounding, uint256 total, uint256 supply)
        internal
        view
        returns (uint256)
    {
        return shares.mulDiv(total + 1, supply + 10 ** _decimalsOffset(), rounding);
    }

    /// @inheritdoc ERC4626Upgradeable
    function _decimalsOffset() internal view override returns (uint8) {
        return _getVaultStorage()._offset;
    }

    /// @dev Internal function accrue the reward fee and mints the shares.
    /// @return newTotalAssets The vaults total assets after accruing the interest.
    function _accrueRewardFee() internal returns (uint256 newTotalAssets) {
        uint256 rewardFeeShares;
        (rewardFeeShares, newTotalAssets) = _accruedRewardFeeShares();

        if (rewardFeeShares != 0) {
            _mint(address(this), rewardFeeShares);
            _getVaultStorage()._collectableRewardFeesShares += rewardFeeShares;
        }
    }

    /// @dev Computes and returns the rewardFee shares to mint and the new vault's total assets.
    /// @return rewardFeeShares The number of shares to mint as reward fee.
    /// @return newTotalAssets The vaults total assets after accruing the interest.
    function _accruedRewardFeeShares() internal view returns (uint256 rewardFeeShares, uint256 newTotalAssets) {
        VaultStorage storage $ = _getVaultStorage();

        newTotalAssets = totalAssets();
        (, uint256 _reward) = newTotalAssets.trySub($._lastTotalAssets);

        if (_reward != 0 && $._rewardFee != 0) {
            uint256 _rewardFeeAmount =
                _reward.mulDiv($._rewardFee, _MAX_PERCENT * 10 ** _underlyingDecimals(), Math.Rounding.Floor);

            // Reward fee is subtracted from the total assets as it's already increased by total interest
            // (including reward fee).
            rewardFeeShares = _convertToShares(
                _rewardFeeAmount, Math.Rounding.Floor, newTotalAssets - _rewardFeeAmount, totalSupply()
            );
        }
    }

    /// @dev Internal function that throws an error if the remainder of the shares is not zero.
    /// @param shares The number of shares to mint/transfer.
    function _checkPartialShares(uint256 shares) internal view {
        uint8 _offset = _decimalsOffset();
        if (_offset > 0) {
            if (shares % 10 ** _offset > 0) revert RemainderNotZero(shares);
        }
    }

    /// @dev Internal function to round down the partial shares, in case of a non-zero offset.
    /// @param shares The number of shares to round down.
    /// @return The rounded down number of shares.
    function _roundDownPartialShares(uint256 shares) internal view returns (uint256) {
        uint8 _offset = _decimalsOffset();
        if (_offset > 0) {
            shares -= shares % 10 ** _offset;
        }
        return shares;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 ERC20 LOGIC                                */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc ERC20Upgradeable
    function transfer(address to, uint256 value)
        public
        override(ERC20Upgradeable, IERC20)
        checkTransferability(to)
        notBlocked(_msgSender())
        notBlocked(to)
        returns (bool)
    {
        _checkPartialShares(value);
        return super.transfer(to, value);
    }

    /// @inheritdoc ERC20Upgradeable
    function transferFrom(address from, address to, uint256 value)
        public
        override(ERC20Upgradeable, IERC20)
        checkTransferability(from)
        checkTransferability(to)
        notBlocked(_msgSender())
        notBlocked(from)
        notBlocked(to)
        returns (bool)
    {
        _checkPartialShares(value);
        return super.transferFrom(from, to, value);
    }

    /// @inheritdoc ERC20Upgradeable
    function approve(address spender, uint256 value)
        public
        override(ERC20Upgradeable, IERC20)
        checkTransferability(spender)
        notBlocked(_msgSender())
        notBlocked(spender)
        returns (bool)
    {
        return super.approve(spender, value);
    }

    /* -------------------------------------------------------------------------- */
    /*                            FEE MANAGEMENT LOGIC                            */
    /* -------------------------------------------------------------------------- */

    /// @notice Dispatches the collected fees to the fee recipients.
    function dispatchFees() external nonReentrant {
        VaultStorage storage $ = _getVaultStorage();
        $._feeDispatcher.dispatchFees(IERC20(asset()), _underlyingDecimals());
    }

    /// @notice Collects the reward fees.
    function collectRewardFees() external nonReentrant onlyRole(FEE_COLLECTOR_ROLE) {
        VaultStorage storage $ = _getVaultStorage();

        (uint256 _rewardFeeShares, uint256 _newTotalAssets) = _accruedRewardFeeShares();

        uint256 _collectable = _convertToAssets(
            $._collectableRewardFeesShares + _rewardFeeShares,
            Math.Rounding.Floor,
            _newTotalAssets,
            totalSupply() + _rewardFeeShares
        );
        if (_collectable == 0) revert NothingToCollect();

        uint256 _balanceBefore = IERC20(asset()).balanceOf(address(this));
        address _connector = $._connectorRegistry.getOrRevert($._connectorName);
        _connector.functionDelegateCall(abi.encodeCall(IConnector.withdraw, (IERC20(asset()), _collectable)));

        $._feeDispatcher.incrementPendingRewardFee(IERC20(asset()).balanceOf(address(this)) - _balanceBefore);

        _burn(address(this), $._collectableRewardFeesShares);
        $._collectableRewardFeesShares = 0;
        $._lastTotalAssets = totalAssets();
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CLAIM LOGIC                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Claims additional rewards to the underlying protocol.
    /// @dev Additional rewards are considered as yield, where the reward fee can be applied.
    /// @param rewardsAsset The rewards asset to claim.
    /// @param payload The payload to pass to the connector.
    function claimAdditionalRewards(address rewardsAsset, bytes calldata payload)
        external
        nonReentrant
        onlyRole(CLAIM_MANAGER_ROLE)
    {
        VaultStorage storage $ = _getVaultStorage();
        uint256 _totalAssetsBefore = totalAssets();
        address _connector = $._connectorRegistry.getOrRevert($._connectorName);

        if ($._additionalRewardsStrategy == AdditionalRewardsStrategy.Claim) {
            IERC20 _rewardAsset = IERC20(rewardsAsset);

            bytes memory _returnData = _connector.functionDelegateCall(
                abi.encodeCall(IConnector.claim, (IERC20(asset()), _rewardAsset, payload))
            );

            uint256 _totalAssetsAfter = totalAssets();

            if (_totalAssetsBefore > _totalAssetsAfter) {
                revert TotalAssetsDecreased(_totalAssetsBefore, _totalAssetsAfter);
            }

            uint256 _collected = abi.decode(_returnData, (uint256));
            if (_collected == 0) {
                revert NoAdditionalRewardsClaimed();
            }
            emit RewardsClaimed(rewardsAsset, _collected);
        } else if ($._additionalRewardsStrategy == AdditionalRewardsStrategy.Reinvest) {
            _connector.functionDelegateCall(
                abi.encodeCall(IConnector.reinvest, (IERC20(asset()), IERC20(rewardsAsset), payload))
            );

            uint256 _totalAssetsAfter = totalAssets();
            if (_totalAssetsBefore > _totalAssetsAfter) {
                revert TotalAssetsDecreased(_totalAssetsBefore, _totalAssetsAfter);
            } else if (_totalAssetsBefore == _totalAssetsAfter) {
                revert NoAdditionalRewardsClaimed();
            }
            emit RewardsClaimed(rewardsAsset, _totalAssetsAfter - _totalAssetsBefore);
        } else {
            revert NoAdditionalRewardsStrategy();
        }
    }

    /// @notice Update the additional rewards strategy.
    /// @param strategy The new additional rewards strategy.
    function setAdditionalRewardsStrategy(AdditionalRewardsStrategy strategy) external onlyRole(CLAIM_MANAGER_ROLE) {
        _setAdditionalRewardsStrategy(strategy);
    }

    /* -------------------------------------------------------------------------- */
    /*                            SANCTIONS LIST LOGIC                            */
    /* -------------------------------------------------------------------------- */

    /// @notice Sets the blocklist.
    /// @param newBlockList The new sanctions list.
    function setBlockList(BlockList newBlockList) external onlyRole(SANCTIONS_MANAGER_ROLE) {
        _setBlockList(newBlockList);
    }

    /// @notice Force withdraws a user from the vault.
    /// @dev The user must be blocked by the internal blocklist and not sanctioned (OFAC).
    /// @param blockedUser The user to force withdraw.
    function forceWithdraw(address blockedUser) public nonReentrant returns (uint256) {
        VaultStorage storage $ = _getVaultStorage();
        if (
            address(blockedUser) != address(0)
                && (
                    !$._blockList.isBlockedByInternalList(blockedUser)
                        || $._blockList.isSanctionedByUnderlyingList(blockedUser)
                )
        ) {
            revert AddressNotInternallySanctionedOnly(blockedUser);
        }
        uint256 _newTotalAssets = _accrueRewardFee();
        uint256 _newTotalSupply = totalSupply();

        uint256 _maxRedeemable = _maxRedeem(blockedUser, _newTotalAssets, _newTotalSupply);
        if (_maxRedeemable != balanceOf(blockedUser)) {
            revert InsufficientLiquidity();
        }

        uint256 _assets = _convertToAssets(_maxRedeemable, Math.Rounding.Floor, _newTotalAssets, _newTotalSupply);
        if (_assets == 0) revert PreviewZero();
        _withdraw(blockedUser, blockedUser, blockedUser, _assets, _maxRedeemable);

        return _assets;
    }

    /* -------------------------------------------------------------------------- */
    /*                             DEPOSIT PAUSE LOGIC                            */
    /* -------------------------------------------------------------------------- */

    /// @notice Pauses the deposit.
    function pauseDeposit() external onlyRole(PAUSER_ROLE) {
        _getVaultStorage()._depositPaused = true;
    }

    /// @notice Unpauses the deposit.
    function unpauseDeposit() external onlyRole(UNPAUSER_ROLE) {
        _getVaultStorage()._depositPaused = false;
    }

    /* -------------------------------------------------------------------------- */
    /*                              (PUBLIC) SETTERS                              */
    /* -------------------------------------------------------------------------- */

    /// @notice Sets the fee recipients.
    /// @param recipients The array of fee recipients.
    function setFeeRecipients(IFeeDispatcher.FeeRecipient[] calldata recipients) external onlyRole(FEE_MANAGER_ROLE) {
        _getVaultStorage()._feeDispatcher.setFeeRecipients(recipients, _underlyingDecimals());
    }

    /// @notice Sets the deposit fee.
    /// @param newDepositFee The new deposit fee.
    function setDepositFee(uint256 newDepositFee) external onlyRole(FEE_MANAGER_ROLE) {
        _setDepositFee(newDepositFee);
    }

    /// @notice Sets the reward fee.
    /// @dev This function also collects the last reward fees prior to updating the fee.
    /// @param newRewardFee The new reward fee.
    function setRewardFee(uint256 newRewardFee) external onlyRole(FEE_MANAGER_ROLE) {
        // Accrue the last reward fees prior to updating the fee amount.
        _getVaultStorage()._lastTotalAssets = _accrueRewardFee();
        _setRewardFee(newRewardFee);
    }

    /* -------------------------------------------------------------------------- */
    /*                             (INTERNAL) SETTERS                             */
    /* -------------------------------------------------------------------------- */

    /// @dev Internal logic to set the reward fee.
    /// @param newRewardFee The new reward fee.
    function _setRewardFee(uint256 newRewardFee) internal {
        if (newRewardFee > _MAX_FEE * 10 ** _underlyingDecimals()) {
            revert WrongRewardFee(newRewardFee);
        }
        _getVaultStorage()._rewardFee = newRewardFee;
        emit RewardFeeUpdated(newRewardFee);
    }

    /// @dev Internal logic to set the deposit fee.
    /// @param newDepositFee The new deposit fee.
    function _setDepositFee(uint256 newDepositFee) internal {
        if (newDepositFee > _MAX_FEE * 10 ** _underlyingDecimals()) {
            revert WrongDepositFee(newDepositFee);
        }
        _getVaultStorage()._depositFee = newDepositFee;
        emit DepositFeeUpdated(newDepositFee);
    }

    /// @notice Internal logic to set the connector registry.
    /// @param newConnectorRegistry The new connector registry.
    function _setConnectorRegistry(IConnectorRegistry newConnectorRegistry) internal {
        if (address(newConnectorRegistry).code.length == 0) revert AddressNotContract(address(newConnectorRegistry));
        _getVaultStorage()._connectorRegistry = newConnectorRegistry;
        emit ConnectorRegistryUpdated(newConnectorRegistry);
    }

    /// @notice Internal logic to set the connector name.
    /// @param newConnectorName The new connector name.
    function _setConnectorName(bytes32 newConnectorName) internal {
        VaultStorage storage $ = _getVaultStorage();
        if (!$._connectorRegistry.connectorExists(newConnectorName)) revert InvalidConnectorName(newConnectorName);
        $._connectorName = newConnectorName;
        emit ConnectorNameUpdated(newConnectorName);
    }

    /// @notice Internal logic to set the transferable flag.
    /// @param newTransferableFlag The new transferable flag.
    function _setTransferable(bool newTransferableFlag) internal {
        _getVaultStorage()._transferable = newTransferableFlag;
        emit TransferableUpdated(newTransferableFlag);
    }

    /// @notice Internal logic to set the offset.
    /// @param offset The new offset.
    function _setOffset(uint8 offset) internal {
        if (offset > _MAX_OFFSET) revert OffsetTooHigh(offset);
        _getVaultStorage()._offset = offset;
        emit OffsetInitialized(offset);
    }

    /// @notice Internal logic to set the blocklist.
    /// @dev Possible to set the blocklist to address(0) to disable it.
    /// @param newBlockList The new blocklist.
    function _setBlockList(BlockList newBlockList) internal {
        _getVaultStorage()._blockList = newBlockList;
        emit BlockListUpdated(newBlockList);
    }

    /// @notice Internal logic to set the minimum supply state.
    /// @dev This is used to prevent a griefing attack.
    /// @param newMinTotalSupply The new minimum total supply required after a deposit.
    function _setMinTotalSupply(uint256 newMinTotalSupply) internal {
        _getVaultStorage()._minTotalSupply = newMinTotalSupply;
        emit MinTotalSupplyInitialized(newMinTotalSupply);
    }

    /// @notice Internal logic to set the additional rewards strategy.
    /// @param newAdditionalRewardsStrategy The new additional rewards strategy.
    function _setAdditionalRewardsStrategy(AdditionalRewardsStrategy newAdditionalRewardsStrategy) internal {
        _getVaultStorage()._additionalRewardsStrategy = newAdditionalRewardsStrategy;
        emit AdditionalRewardsStrategyUpdated(newAdditionalRewardsStrategy);
    }

    /// @notice Internal logic to set the fee dispatcher.
    /// @param newFeeDispatcher The new fee dispatcher.
    function _setFeeDispatcher(address newFeeDispatcher) internal {
        if (address(newFeeDispatcher).code.length == 0) revert AddressNotContract(address(newFeeDispatcher));
        _getVaultStorage()._feeDispatcher = IFeeDispatcher(newFeeDispatcher);
        emit FeeDispatcherInitialized(newFeeDispatcher);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Returns if the ERC4626 share is transferable.
    /// @return transferable True if the ERC4626 share is transferable, False if not.
    function transferable() external view returns (bool) {
        return _getVaultStorage()._transferable;
    }

    /// @notice Returns the connector registry.
    /// @return connectorRegistry The connector registry.
    function connectorRegistry() external view returns (IConnectorRegistry) {
        return _getVaultStorage()._connectorRegistry;
    }

    /// @notice Returns the connector name.
    /// @return connectorName The connector name.
    function connectorName() external view returns (bytes32) {
        return _getVaultStorage()._connectorName;
    }

    /// @notice Returns the deposit fee.
    /// @return depositFee The deposit fee.
    function depositFee() external view returns (uint256) {
        return _getVaultStorage()._depositFee;
    }

    /// @notice Returns the reward fee.
    /// @return rewardFee The reward fee.
    function rewardFee() external view returns (uint256) {
        return _getVaultStorage()._rewardFee;
    }

    /// @notice Returns the additional rewards strategy.
    /// @return additionalRewardsStrategy The additional rewards strategy.
    function additionalRewardsStrategy() external view returns (AdditionalRewardsStrategy) {
        return _getVaultStorage()._additionalRewardsStrategy;
    }

    /// @notice Returns the collectable reward fees (when calling `collectRewardFees`).
    /// @return collectableRewardFees The amount of reward fees that can be collected by the FeeManager.
    function collectableRewardFees() external view returns (uint256) {
        (uint256 _accruedShares, uint256 _newTotalAssets) = _accruedRewardFeeShares();
        uint256 _totalShares = _accruedShares + _getVaultStorage()._collectableRewardFeesShares;

        return _convertToAssets(_totalShares, Math.Rounding.Floor, _newTotalAssets, totalSupply() + _accruedShares);
    }

    /// @notice Returns the blocklist.
    /// @return The blocklist.
    function blockList() external view returns (BlockList) {
        return _getVaultStorage()._blockList;
    }

    /// @notice Returns the pending deposit fee.
    /// @return The amount of pending deposit fee.
    function pendingDepositFee() public view returns (uint256) {
        return _getVaultStorage()._feeDispatcher.pendingDepositFee();
    }

    /// @notice Returns the pending reward fee.
    /// @return The amount of pending reward fee.
    function pendingRewardFee() public view returns (uint256) {
        return _getVaultStorage()._feeDispatcher.pendingRewardFee();
    }

    /// @notice Returns the list of fee recipients.
    /// @return An array of fee recipients.
    function feeRecipients() public view returns (IFeeDispatcher.FeeRecipient[] memory) {
        return _getVaultStorage()._feeDispatcher.feeRecipients();
    }

    /// @notice Returns the fee recipient details for a given address.
    /// @param recipient The address of the fee recipient.
    /// @return The fee recipient details.
    function feeRecipient(address recipient) public view returns (IFeeDispatcher.FeeRecipient memory) {
        return _getVaultStorage()._feeDispatcher.feeRecipient(recipient);
    }

    /// @notice Returns the fee recipient details at a given index.
    /// @param index The index of the fee recipient.
    /// @return The fee recipient details.
    function feeRecipientAt(uint256 index) public view returns (IFeeDispatcher.FeeRecipient memory) {
        return _getVaultStorage()._feeDispatcher.feeRecipientAt(index);
    }

    /// @dev Get the connector address.
    function _getConnector() internal view returns (IConnector) {
        VaultStorage storage $ = _getVaultStorage();
        return IConnector($._connectorRegistry.get($._connectorName));
    }

    /* -------------------------------------------------------------------------- */
    /*                               INTERNAL UTILS                               */
    /* -------------------------------------------------------------------------- */

    /// @dev Get the underlying asset decimals (without the offset).
    /// @return The underlying asset decimals.
    function _underlyingDecimals() internal view returns (uint8) {
        return IERC20Metadata(asset()).decimals();
    }
}

```

### src/VaultFactory.sol

```solidity
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

```

### src/connectors/AaveV3Connector.sol

```solidity
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

import {Address} from "@openzeppelin/utils/Address.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, NothingToClaim, NothingToReinvest} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";
import {MultisendLib} from "../libraries/MultisendLib.sol";

/// @dev Partial IPool interface.
interface Aave {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @dev Partial IPoolAddressesProvider interface.
interface IPoolAddressesProvider {
    function getPoolDataProvider() external view returns (address);
}

/// @dev Partial IRewardsController interface.
interface IRewardsController {
    function claimAllRewards(address[] calldata assets, address to) external;
}

/// @dev Partial IPoolDataProvider interface.
interface IPoolDataProvider {
    function getReserveTokensAddresses(address asset) external view returns (address, address, address);
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
    function getReserveData(address asset)
        external
        view
        returns (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        );
    function getReserveCaps(address asset) external view returns (uint256 borrowCap, uint256 supplyCap);
    function getPaused(address asset) external view returns (bool);
}

/// @title Aave V3 Connector.
/// @author maximebrugel @ Kiln.
contract AaveV3Connector is IConnector {
    using Address for address;
    using SafeERC20 for IERC20;
    using MultisendLib for address;

    /// @notice Aave V3 lending pool address.
    Aave public immutable aave;

    /// @notice Aave V3 rewards controller contract.
    IRewardsController public immutable rewardsController;

    /// @notice Swap Target (aggregator or DEX)
    /// @dev If set to address(0), no swap will be performed
    address public immutable swapTarget;

    /// @notice Aave V3 pool addresses provider address.
    IPoolAddressesProvider public immutable poolAddressesProvider;

    constructor(address _aave, address _poolAddressesProvider, address _swapTarget, address _rewardController) {
        if (_aave.code.length == 0) revert AddressNotContract(_aave);
        if (_poolAddressesProvider.code.length == 0) revert AddressNotContract(_poolAddressesProvider);
        if (_swapTarget.code.length == 0) revert AddressNotContract(_swapTarget);
        if (_rewardController.code.length == 0) revert AddressNotContract(_rewardController);
        aave = Aave(_aave);
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        swapTarget = _swapTarget;
        rewardsController = IRewardsController(_rewardController);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20 asset) external view returns (uint256) {
        IPoolDataProvider _poolDataProvider = IPoolDataProvider(poolAddressesProvider.getPoolDataProvider());
        (address _aToken,,) = _poolDataProvider.getReserveTokensAddresses(address(asset));
        return IERC20(_aToken).balanceOf(msg.sender);
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(address(aave), amount);
        aave.supply(address(asset), amount, address(this), 0);
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20 asset, uint256 amount) external {
        aave.withdraw(address(asset), amount, address(this));
    }

    /// @inheritdoc IConnector
    function claim(IERC20, IERC20 rewardsAsset, bytes calldata payload) external override returns (uint256) {
        address[] memory _rewardsAssetsParam = new address[](1);
        _rewardsAssetsParam[0] = address(rewardsAsset);

        uint256 _balanceBefore = rewardsAsset.balanceOf(address(this));
        rewardsController.claimAllRewards(_rewardsAssetsParam, address(this));

        uint256 _received = rewardsAsset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        (address[] memory recipients, uint256[] memory splits) = abi.decode(payload, (address[], uint256[]));
        address(rewardsAsset).multisend(recipients, splits, _received);

        return _received;
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override {
        address[] memory _rewardsAssetsParam = new address[](1);
        _rewardsAssetsParam[0] = address(rewardsAsset);

        uint256 _balanceBefore = asset.balanceOf(address(this));
        rewardsController.claimAllRewards(_rewardsAssetsParam, address(this));

        // Approve the swap target
        rewardsAsset.forceApprove(address(swapTarget), type(uint256).max);

        // Swap the rewardsAsset to the underlying asset
        swapTarget.functionCall(payload);

        uint256 _received = asset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        asset.forceApprove(address(aave), _received);
        aave.supply(address(asset), _received, address(this), 0);
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20 asset) external view override returns (uint256) {
        IPoolDataProvider _poolDataProvider = IPoolDataProvider(poolAddressesProvider.getPoolDataProvider());
        (,,,,,,,, bool _isActive, bool _isFrozen) = _poolDataProvider.getReserveConfigurationData(address(asset));
        bool _isPaused = _poolDataProvider.getPaused(address(asset));
        if (!_isActive || _isFrozen || _isPaused) {
            return 0;
        }

        (, uint256 _rawSupplyCap) = _poolDataProvider.getReserveCaps(address(asset));

        // If not capped
        if (_rawSupplyCap == 0) {
            return type(uint256).max;
        }

        // We need to scale the supply cap to the asset decimals
        uint256 _supplyCap = _rawSupplyCap * 10 ** IERC20Metadata(address(asset)).decimals();

        (, uint256 _accruedToTreasuryScaled, uint256 _totalAToken,,,,,,,,,) =
            _poolDataProvider.getReserveData(address(asset));

        // If supply cap already reached
        if (_totalAToken + _accruedToTreasuryScaled >= _supplyCap) {
            return 0;
        }

        return _supplyCap - (_totalAToken + _accruedToTreasuryScaled);
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20 asset) external view override returns (uint256) {
        IPoolDataProvider _poolDataProvider = IPoolDataProvider(poolAddressesProvider.getPoolDataProvider());
        (,,,,,,,, bool _isActive,) = _poolDataProvider.getReserveConfigurationData(address(asset));
        bool _isPaused = _poolDataProvider.getPaused(address(asset));
        if (!_isActive || _isPaused) {
            return 0;
        }

        (address _aToken,,) = _poolDataProvider.getReserveTokensAddresses(address(asset));
        return asset.balanceOf(address(_aToken));
    }
}

```

### src/connectors/AngleSavingConnector.sol

```solidity
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

import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, Invalid4626, NothingToClaim, NothingToReinvest} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";

interface IPausableERC4626 is IERC4626 {
    function paused() external view returns (uint8);
}

/// @title Angle Saving Connector (stUSD & stEUR).
/// @author maximebrugel @ Kiln.
contract AngleSavingConnector is IConnector {
    using SafeERC20 for IERC20;

    /// @notice stUSD or stEUR ERC4626 vault address.
    IPausableERC4626 public immutable stakingVault;

    constructor(address _stakingVault) {
        if (_stakingVault.code.length == 0) revert AddressNotContract(_stakingVault);
        if (IPausableERC4626(_stakingVault).totalAssets() == 0) revert Invalid4626(_stakingVault);

        stakingVault = IPausableERC4626(_stakingVault);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20) external view returns (uint256) {
        return stakingVault.previewRedeem(stakingVault.balanceOf(msg.sender));
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(address(stakingVault), amount);
        stakingVault.deposit(amount, address(this));
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20, uint256 amount) external {
        stakingVault.withdraw(amount, address(this), address(this));
    }

    /// @inheritdoc IConnector
    function claim(IERC20, IERC20, bytes calldata) external pure override returns (uint256) {
        revert NothingToClaim();
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20, IERC20, bytes calldata) external pure override {
        revert NothingToReinvest();
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20) external view override returns (uint256) {
        if (stakingVault.paused() == 1) return 0;
        return stakingVault.maxDeposit(msg.sender);
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20) external view override returns (uint256) {
        if (stakingVault.paused() == 1) return 0;
        return stakingVault.maxWithdraw(msg.sender);
    }
}

```

### src/connectors/CompoundV3Connector.sol

```solidity
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

import {Address} from "@openzeppelin/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, InvalidRewardsAsset, NothingToClaim} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";
import {MarketRegistry} from "./utils/MarketRegistry.sol";
import {MultisendLib} from "../libraries/MultisendLib.sol";

/// @dev Compound interface.
interface IComet {
    function balanceOf(address account) external view returns (uint256);
    function supply(IERC20 asset, uint256 amount) external;
    function withdraw(IERC20 asset, uint256 amount) external;
    function isSupplyPaused() external view returns (bool);
    function isWithdrawPaused() external view returns (bool);
}

/// @title Compound v3 Rewards interface.
/// @notice Hold and claim token rewards
interface ICometRewards {
    function claim(address comet, address src, bool shouldAccrue) external;
}

/// @title Compound V3 Connector.
/// @author maximebrugel @ Kiln.
contract CompoundV3Connector is IConnector {
    using Address for address;
    using SafeERC20 for IERC20;
    using MultisendLib for address;

    /// @notice Compound Market Registry address.
    MarketRegistry public immutable compoundMarketRegistry;

    /// @notice Compound V3 comet rewards contract.
    ICometRewards public immutable cometRewards;

    /// @notice Swap Target (aggregator or DEX)
    /// @dev If set to address(0), no swap will be performed
    address public immutable swapTarget;

    /// @notice COMP ERC20 address.
    IERC20 public immutable comp;

    constructor(address _compoundMarketRegistry, address _cometRewards, address _swapTarget, address _comp) {
        if (_cometRewards.code.length == 0) revert AddressNotContract(_cometRewards);
        if (_swapTarget.code.length == 0) revert AddressNotContract(_swapTarget);
        if (_comp.code.length == 0) revert AddressNotContract(_comp);
        if (_compoundMarketRegistry.code.length == 0) revert AddressNotContract(_compoundMarketRegistry);
        cometRewards = ICometRewards(_cometRewards);
        swapTarget = _swapTarget;
        comp = IERC20(_comp);
        compoundMarketRegistry = MarketRegistry(_compoundMarketRegistry);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20 asset) external view returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        return _comet.balanceOf(msg.sender);
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        asset.forceApprove(address(_comet), amount);
        _comet.supply(asset, amount);
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20 asset, uint256 amount) external {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        _comet.withdraw(asset, amount);
    }

    /// @inheritdoc IConnector
    function claim(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override returns (uint256) {
        if (rewardsAsset != comp) revert InvalidRewardsAsset(address(rewardsAsset));

        address _comet = compoundMarketRegistry.getMarket(address(asset));

        // Claim COMP
        uint256 _balanceBefore = rewardsAsset.balanceOf(address(this));
        cometRewards.claim(_comet, address(this), true);
        uint256 _received = rewardsAsset.balanceOf(address(this)) - _balanceBefore;

        if (_received == 0) revert NothingToClaim();

        (address[] memory recipients, uint256[] memory splits) = abi.decode(payload, (address[], uint256[]));
        address(rewardsAsset).multisend(recipients, splits, _received);

        return _received;
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override {
        if (rewardsAsset != comp) revert InvalidRewardsAsset(address(rewardsAsset));

        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        uint256 _balanceBefore = asset.balanceOf(address(this));

        // Claim COMP
        cometRewards.claim(address(_comet), address(this), true);

        // Approve the swap target
        rewardsAsset.forceApprove(address(swapTarget), type(uint256).max);

        // Swap the COMP to the underlying asset
        swapTarget.functionCall(payload);

        uint256 _received = asset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        asset.forceApprove(address(_comet), _received);
        _comet.supply(asset, _received);
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20 asset) external view override returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        if (_comet.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20 asset) external view override returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        if (_comet.isWithdrawPaused()) return 0;
        return asset.balanceOf(address(_comet));
    }
}

```

### src/connectors/MetamorphoConnector.sol

```solidity
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

import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, NothingToClaim, NothingToReinvest} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";

/// @title Metamorpho Connector.
/// @author maximebrugel @ Kiln.
contract MetamorphoConnector is IConnector {
    using SafeERC20 for IERC20;

    /// @notice Metamorpho ERC4626 vault address.
    IERC4626 public immutable metamorpho;

    constructor(address _metamorpho) {
        if (_metamorpho.code.length == 0) revert AddressNotContract(_metamorpho);
        metamorpho = IERC4626(_metamorpho);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20) external view returns (uint256) {
        return metamorpho.previewRedeem(metamorpho.balanceOf(msg.sender));
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(address(metamorpho), amount);
        metamorpho.deposit(amount, address(this));
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20, uint256 amount) external {
        metamorpho.withdraw(amount, address(this), address(this));
    }

    /// @inheritdoc IConnector
    function claim(IERC20, IERC20, bytes calldata) external pure override returns (uint256) {
        revert NothingToClaim();
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20, IERC20, bytes calldata) external pure override {
        revert NothingToReinvest();
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20) external view override returns (uint256) {
        return metamorpho.maxDeposit(msg.sender);
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20) external view override returns (uint256) {
        return metamorpho.maxWithdraw(msg.sender);
    }
}

```

### src/connectors/SDAIConnector.sol

```solidity
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

import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, NothingToClaim, NothingToReinvest} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";

/// @title Spark SavingsDAI Connector.
/// @author maximebrugel @ Kiln.
contract SDAIConnector is IConnector {
    using SafeERC20 for IERC20;

    /// @notice sDAI ERC4626 vault address.
    IERC4626 public immutable sDAI;

    constructor(address _sDAI) {
        if (_sDAI.code.length == 0) revert AddressNotContract(_sDAI);
        sDAI = IERC4626(_sDAI);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20) external view returns (uint256) {
        return sDAI.previewRedeem(sDAI.balanceOf(msg.sender));
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(address(sDAI), amount);
        sDAI.deposit(amount, address(this));
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20, uint256 amount) external {
        sDAI.withdraw(amount, address(this), address(this));
    }

    /// @inheritdoc IConnector
    function claim(IERC20, IERC20, bytes calldata) external pure override returns (uint256) {
        revert NothingToClaim();
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20, IERC20, bytes calldata) external pure override {
        revert NothingToReinvest();
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20) external view override returns (uint256) {
        return sDAI.maxDeposit(msg.sender);
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20) external view override returns (uint256) {
        return sDAI.maxWithdraw(msg.sender);
    }
}

```

### src/connectors/SUSDSConnector.sol

```solidity
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

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, NothingToClaim, NothingToReinvest} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";

/// @title Sky Savings Rate Connector.
/// @author maximebrugel @ Kiln.
contract SUSDSConnector is IConnector {
    using SafeERC20 for IERC20;

    /// @notice sUSDS ERC4626 vault address.
    IERC4626 public immutable sUSDS;

    constructor(address _sUSDS) {
        if (_sUSDS.code.length == 0) revert AddressNotContract(_sUSDS);
        sUSDS = IERC4626(_sUSDS);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20) external view returns (uint256) {
        return sUSDS.previewRedeem(sUSDS.balanceOf(msg.sender));
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(address(sUSDS), amount);
        sUSDS.deposit(amount, address(this));
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20, uint256 amount) external {
        sUSDS.withdraw(amount, address(this), address(this));
    }

    /// @inheritdoc IConnector
    function claim(IERC20, IERC20, bytes calldata) external pure override returns (uint256) {
        revert NothingToClaim();
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20, IERC20, bytes calldata) external pure override {
        revert NothingToReinvest();
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20) external view override returns (uint256) {
        return sUSDS.maxDeposit(msg.sender);
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20) external view override returns (uint256) {
        return sUSDS.maxWithdraw(msg.sender);
    }
}

```

### src/connectors/utils/MarketRegistry.sol

```solidity
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

import {
    AddressNotContract, AlreadyRegistered, ArrayMismatch, EmptyArray, InvalidAsset
} from "../../libraries/Errors.sol";

/// @title Market Registry.
/// @author maximebrugel @ Kiln.
/// @notice List of all markets (cToken, vToken, Comet,...) with their associated underlying asset.
contract MarketRegistry {
    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Mapping of underlying asset to the market address.
    mapping(address => address) internal _markets;

    /// @notice Name of the registry.
    /// @dev Since we are deploying multiple registries (Compound V2, V3, Venus,...), we are exposing a name.
    string public name;

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    constructor(string memory _name, address[] memory _underlyingAssets, address[] memory _marketsAddresses) {
        if (_underlyingAssets.length == 0) revert EmptyArray();
        if (_underlyingAssets.length != _marketsAddresses.length) revert ArrayMismatch();
        for (uint256 i = 0; i < _underlyingAssets.length; i++) {
            address _underlyingAsset = _underlyingAssets[i];
            address _marketAddress = _marketsAddresses[i];

            if (_underlyingAsset.code.length == 0) revert AddressNotContract(_underlyingAsset);
            if (_marketAddress.code.length == 0) revert AddressNotContract(_marketAddress);
            if (_markets[_underlyingAsset] != address(0)) revert AlreadyRegistered(_underlyingAsset);
            _markets[_underlyingAsset] = _marketAddress;
        }
        name = _name;
    }

    /* -------------------------------------------------------------------------- */
    /*                                    VIEWS                                   */
    /* -------------------------------------------------------------------------- */

    /// @notice Get the market address for a given asset.
    /// @param asset The underlying asset address.
    function getMarket(address asset) external view returns (address) {
        address _market = _markets[asset];
        if (_market.code.length == 0) revert InvalidAsset(asset);
        return _market;
    }
}

```

### src/libraries/Constants.sol

```solidity
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

/// @dev Represents the maximum percentage value in calculations.
///      This constant is used as a scaling factor for percentage-based computations.
uint256 constant _MAX_PERCENT = 100;

```

### src/libraries/Errors.sol

```solidity
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

/* --------------------------------- Common --------------------------------- */

/// @dev Error emitted when the address is zero.
error AddressZero();

/// @dev Error emitted when the address is not a contract.
/// @param addr The address that was attempted to be used as a contract.
error AddressNotContract(address addr);

/// @dev Error emitted when a given amount is zero.
error AmountZero();

/// @dev Error emitted when two array lengths do not match.
error ArrayMismatch();

/// @dev Error emitted when the array is empty.
error EmptyArray();

/// @dev Error emitted when the duration to pause for is invalid
///      (before the current pauseTimestamp).
/// @param timestamp The timestamp to pause for.
error InvalidDuration(uint256 timestamp, uint256 currentTimestamp);

/// @dev Error emitted when the claim function is not available on the connector or
///      no additional rewards to claim at the moment.
error NothingToClaim();

/// @dev Error emitted when the reinvest function is not available on the connector or
///      no additional rewards to compound at the moment.
error NothingToReinvest();

/* ----------------------- VaultUpgradeableBeacon.sol ----------------------- */

/// @dev The `implementation` of the beacon is invalid.
/// @param implementation The address of the implementation that was attempted to be set.
error BeaconInvalidImplementation(address implementation);

/// @dev Error emitted when an operation is attempted on a paused contract.
error isPaused();

/// @dev Error emitted when an operation is attempted on a not paused contract.
error isNotPaused();

/// @dev Error emitted when an operation is attempted on a frozen contract.
error isFrozen();

/* -------------------------------- Vault.sol ------------------------------- */

/// @dev Error emitted when the ERC4626 is not transferable.
error NotTransferable();

/// @dev Error emitted when the deposit fee over 100%.
error WrongDepositFee(uint256 depositFee);

/// @dev Error emitted when the reward fee over 100%.
error WrongRewardFee(uint256 rewardFee);

/// @dev Error emitted when the connector name is invalid (not existing on the registry).
error InvalidConnectorName(bytes32 name);

/// @dev Error emitted when no rewards could be collected.
error NothingToCollect();

/// @dev Error emitted when a call is not a delegate call.
error NotDelegateCall();

/// @dev Error emitted when the preview result is zero (shares or assets).
error PreviewZero();

/// @dev Error emitted when the given address is on the blocklist.
error AddressBlocked(address addr);

/// @dev Error emitted when the total assets decreased.
error TotalAssetsDecreased(uint256 totalAssets, uint256 newTotalAssets);

/// @dev Error emitted when no additional rewards claimed (using the claim function).
error NoAdditionalRewardsClaimed();

/// @dev Error emitted when the deposit is paused.
error DepositPaused();

/// @dev Error emitted when the offset set is too high.
error OffsetTooHigh(uint8 offset);

/// @dev Error emitted when the remainder of transferred shares is not zero.
error RemainderNotZero(uint256 shares);

/// @dev Error emitted when the minimum totalSupply is not met after a deposit.
error MinimumTotalSupplyNotReached();

/// @dev Error emitted when the caller does not have the spender role.
error UnauthorizedSpender();

/// @dev Error emitted when no additional rewards strategy is set.
error NoAdditionalRewardsStrategy();

/// @dev Error emitted when the given address is not only in the internal sanction list.
/// @param addr The address was checked.
error AddressNotInternallySanctionedOnly(address addr);

/// @dev Error emitted when trying to forceWithdraw a user, but there is not enough liquidity.
error InsufficientLiquidity();

/// @dev Error emitted when the vault is not configured for the factory.
error VaultMisconfigured();

/// @dev Error emitted when a confirured factory reserved interaction is attempted by another.
/// @param addr The address attempting to interact.
error NotConfiguredFactory(address addr);

/* --------------------------- ConnectorRegistry.sol ------------------------- */

/// @dev Error emitted when the connector already exists.
/// @param name The name of the connector.
/// @param connector The address of the connector.
error ConnectorAlreadyExists(bytes32 name, address connector);

/// @dev Error emitted when the connector does not exist.
/// @param name The name of the connector.
error ConnectorDoesNotExist(bytes32 name);

/// @dev Error emitted when the connector is frozen.
/// @param name The name of the connector.
error ConnectorFrozen(bytes32 name);

/// @dev Error emitted when the connector is paused.
/// @param name The name of the connector.
error ConnectorPaused(bytes32 name);

/// @dev Error emitted when the connector is not paused.
/// @param name The name of the connector.
error ConnectorNotPaused(bytes32 name);

/* ---------------------------- FeeDispatcher.sol --------------------------- */

/// @dev Error emitted when a given fee recipient does not exist.
/// @param recipient The address of the given fee recipient.
error FeeRecipientDoesNotExist(address recipient);

/// @dev Error emitted when the total deposit fee split between the fee recipients is not 100%.
/// @param totalSplit The total deposit fee split.
error WrongDepositFeeSplit(uint256 totalSplit);

/// @dev Error emitted when the total reward fee split between the fee recipients is not 100%.
/// @param totalSplit The total reward fee split.
error WrongRewardFeeSplit(uint256 totalSplit);

/// @dev Error emitted when a fee recipient address is not unique (in the given array of fee recipients).
/// @param recipient The address of the fee recipient.
error FeeRecipientNotUnique(address recipient);

/* ---------------------------- VaultFactory.sol ---------------------------- */

/// @dev Error emitted when the deployer already exists.
/// @param deployer The address of the deployer.
error DeployerAlreadyExists(address deployer);

/// @dev Error emitted when the caller is not a deployer.
/// @param caller The address of the caller.
error NotDeployer(address caller);

/// @dev Error emitted when the deployer does not exist.
/// @param deployer The address of the deployer.
error InvalidDeployer(address deployer);

/// @dev Error emitted when the index is not matching the Vault address.
/// @param index The index of the Vault.
/// @param vault The address of the Vault.
error InvalidVaultIndex(uint256 index, address vault);

/* ------------------------------ Connector.sol ----------------------------- */

/// @dev Error emitted when the given rewards asset is invalid.
/// @param asset The address of the invalid rewards asset.
error InvalidRewardsAsset(address asset);

/// @dev Error emitted when the given address is an invalid 4626.
/// @param addr The address of the invalid 4626.
error Invalid4626(address addr);

/* --------------------------- VenusConnector.sol --------------------------- */

/// @dev Error emitted when the mint function fails.
error MintFailed();

/// @dev Error emitted when the redeem function fails.
error RedeemFailed();

/* --------------------------- MarketRegistry.sol --------------------------- */

/// @dev Error emitted when the market for a specific asset does not exist.
error InvalidAsset(address asset);

/// @dev Error emitted when an asset is already registered.
/// @param asset The address of the asset.
error AlreadyRegistered(address asset);

/* ----------------------- blockList.sol ----------------------- */

/// @dev Error emitted when the address removed is not blocked.
/// @param addr The address that was attempted to be removed.
error AddressNotBlocked(address addr);

/* ------------------------------ Multisend.sol ----------------------------- */

/// @dev Error emitted when the total split between the recipients is not 100%.
error WrongSplit(uint256 totalSplit);

/* ----------------------------- PauserProxy.sol ---------------------------- */

/// @dev Error emitted when an uint256 value overflows a uint88.
error Uint88Overflow(uint256 value);

/// @dev Error emitted when the caller is not the pauser.
error PauserUnauthorizedAccount(address account);

```

### src/libraries/MultisendLib.sol

```solidity
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

import {Math} from "@openzeppelin/utils/math/Math.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";

import {AddressZero, AmountZero, ArrayMismatch, WrongSplit} from "./Errors.sol";
import {_MAX_PERCENT} from "./Constants.sol";

/// @title Multisend library
/// @notice Send token to multiple recipients based on a split.
library MultisendLib {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /// @notice Send a token to multiple recipients.
    /// @param token The token to send.
    /// @param recipients The array of recipients to send to.
    /// @param splits The split of the token to send to each recipient (%).
    /// @param total The total amount of the token to send.
    function multisend(address token, address[] memory recipients, uint256[] memory splits, uint256 total) internal {
        if (recipients.length != splits.length) revert ArrayMismatch();
        if (total == 0) revert AmountZero();

        uint256 _scaledMaxPercent = _MAX_PERCENT * 10 ** IERC20Metadata(token).decimals();
        uint256 _totalSplit = 0;

        // Check total split
        for (uint256 i; i < splits.length; i++) {
            _totalSplit += splits[i];
        }
        if (_totalSplit != _scaledMaxPercent) revert WrongSplit(_totalSplit);

        // Send tokens
        for (uint256 i; i < recipients.length; i++) {
            address _recipient = recipients[i]; // tmp
            uint256 _split = splits[i]; // tmp
            if (_recipient == address(0)) revert AddressZero();
            if (_split == 0) revert AmountZero();
            IERC20(token).safeTransfer(_recipient, total.mulDiv(_split, _scaledMaxPercent));
        }
    }
}

```

### src/proxy/BlockListBeaconProxy.sol

```solidity
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

import {BeaconProxy} from "@openzeppelin/proxy/beacon/BeaconProxy.sol";

/// @title BlockList Beacon Proxy
/// @author isma @ Kiln
contract BlockListBeaconProxy is BeaconProxy {
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {}
}

```

### src/proxy/BlockListUpgradeableBeacon.sol

```solidity
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

import {IBeacon} from "@openzeppelin/proxy/beacon/IBeacon.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/access/extensions/AccessControlDefaultAdminRules.sol";

import {AmountZero, BeaconInvalidImplementation, InvalidDuration, isFrozen} from "../libraries/Errors.sol";

/// @title BLocklist Upgradeable Beacon.
/// @author isma @ Kiln.
contract BlockListUpgradeableBeacon is IBeacon, AccessControlDefaultAdminRules {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the freezer role.
    bytes32 public constant FREEZER_ROLE = bytes32("FREEZER");

    /// @notice The role code for the implementation manager role.
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE = bytes32("IMPLEMENTATION_MANAGER");

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation contract.
    address private _implementation;

    /// @notice True if the implementation is frozen, and false otherwise.
    bool public frozen;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the implementation returned by the beacon is changed.
    /// @param implementation The address of the new implementation.
    event Upgraded(address indexed implementation);

    /// @dev Emitted when the implementation is frozen.
    event Frozen();

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the contract is frozen.
    modifier whenNotFrozen() {
        if (frozen) revert isFrozen();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /// @dev Sets the address of the initial implementation, and the initial owner who can upgrade the beacon.
    constructor(
        address implementation_,
        address initialAdmin,
        address initialImplementationManager,
        address initialFreezer,
        uint48 initialDelay
    ) AccessControlDefaultAdminRules(initialDelay, initialAdmin) {
        _setImplementation(implementation_);
        _grantRole(IMPLEMENTATION_MANAGER_ROLE, initialImplementationManager);
        _grantRole(FREEZER_ROLE, initialFreezer);
    }

    /* -------------------------------------------------------------------------- */
    /*                          UPGRADEABLE BEACON LOGIC                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IBeacon
    function implementation() external view override returns (address) {
        return _implementation;
    }

    /// @notice Upgrades the beacon to a new implementation.
    /// @param newImplementation The address of the new implementation.
    /// @dev msg.sender must have the role `IMPLEMENTATION_MANAGER_ROLE`.
    ///      `newImplementation` must be a contract.
    function upgradeTo(address newImplementation) external whenNotFrozen onlyRole(IMPLEMENTATION_MANAGER_ROLE) {
        _setImplementation(newImplementation);
    }

    /* -------------------------------------------------------------------------- */
    /*                                FREEZER LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Freezes the contract.
    function freeze() external onlyRole(FREEZER_ROLE) whenNotFrozen {
        frozen = true;
        emit Frozen();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  INTERNAL                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev Sets the implementation contract address for this beacon.
    ///      `newImplementation` must be a contract.
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) revert BeaconInvalidImplementation(newImplementation);
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }
}

```

### src/proxy/VaultBeaconProxy.sol

```solidity
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

import {BeaconProxy} from "@openzeppelin/proxy/beacon/BeaconProxy.sol";

/// @title Vault Beacon Proxy
/// @author maximebrugel @ Kiln
contract VaultBeaconProxy is BeaconProxy {
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {}
}

```

### src/proxy/VaultUpgradeableBeacon.sol

```solidity
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

import {IBeacon} from "@openzeppelin/proxy/beacon/IBeacon.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/access/extensions/AccessControlDefaultAdminRules.sol";

import {
    AmountZero, BeaconInvalidImplementation, InvalidDuration, isFrozen, isNotPaused, isPaused
} from "../Errors.sol";

/// @title Vault Upgradeable Beacon.
contract VaultUpgradeableBeacon is IBeacon, AccessControlDefaultAdminRules {
    /* -------------------------------------------------------------------------- */
    /*                                  CONSTANTS                                 */
    /* -------------------------------------------------------------------------- */

    /// @notice The role code for the pauser role.
    bytes32 public constant PAUSER_ROLE = bytes32("PAUSER");

    /// @notice The role code for the unpauser role.
    bytes32 public constant UNPAUSER_ROLE = bytes32("UNPAUSER");

    /// @notice The role code for the freezer role.
    bytes32 public constant FREEZER_ROLE = bytes32("FREEZER");

    /// @notice The role code for the implementation manager role.
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE = bytes32("IMPLEMENTATION_MANAGER");

    /* -------------------------------------------------------------------------- */
    /*                                   STORAGE                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev The address of the implementation contract.
    address private _implementation;

    /// @notice The timestamp until which the implementation is paused.
    uint88 public pauseTimestamp;

    /// @notice True if the implementation is frozen, and false otherwise.
    bool public frozen;

    /* -------------------------------------------------------------------------- */
    /*                                   EVENTS                                   */
    /* -------------------------------------------------------------------------- */

    /// @dev Emitted when the implementation returned by the beacon is changed.
    /// @param implementation The address of the new implementation.
    event Upgraded(address indexed implementation);

    /// @dev Emitted when the implementation is paused.
    /// @param timestamp The timestamp until which the implementation is paused.
    event Paused(uint256 timestamp);

    /// @dev Emitted when the implementation is unpaused.
    event Unpaused();

    /// @dev Emitted when the implementation is frozen.
    event Frozen();

    /* -------------------------------------------------------------------------- */
    /*                                  MODIFIERS                                 */
    /* -------------------------------------------------------------------------- */

    /// @dev Throws if the contract is paused.
    modifier whenNotPaused() {
        if (paused()) revert isPaused();
        _;
    }

    /// @dev Throws if the contract is not paused.
    modifier whenPaused() {
        if (!paused()) revert isNotPaused();
        _;
    }

    /// @dev Throws if the contract is frozen.
    modifier whenNotFrozen() {
        if (frozen) revert isFrozen();
        _;
    }

    /* -------------------------------------------------------------------------- */
    /*                                 CONSTRUCTOR                                */
    /* -------------------------------------------------------------------------- */

    /// @dev Sets the address of the initial implementation, and the initial owner who can upgrade the beacon.
    constructor(
        address implementation_,
        address initialAdmin,
        address initialImplementationManager,
        address initialPauser,
        address initialUnpauser,
        address initialFreezer,
        uint48 initialDelay
    ) AccessControlDefaultAdminRules(initialDelay, initialAdmin) {
        _setImplementation(implementation_);
        _grantRole(IMPLEMENTATION_MANAGER_ROLE, initialImplementationManager);
        _grantRole(PAUSER_ROLE, initialPauser);
        _grantRole(UNPAUSER_ROLE, initialUnpauser);
        _grantRole(FREEZER_ROLE, initialFreezer);
    }

    /* -------------------------------------------------------------------------- */
    /*                          UPGRADEABLE BEACON LOGIC                          */
    /* -------------------------------------------------------------------------- */

    /// @inheritdoc IBeacon
    function implementation() external view override whenNotPaused returns (address) {
        return _implementation;
    }

    /// @notice Upgrades the beacon to a new implementation.
    /// @param newImplementation The address of the new implementation.
    /// @dev msg.sender must have the role `IMPLEMENTATION_MANAGER_ROLE`.
    ///      `newImplementation` must be a contract.
    function upgradeTo(address newImplementation) external whenNotFrozen onlyRole(IMPLEMENTATION_MANAGER_ROLE) {
        _setImplementation(newImplementation);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   GETTERS                                  */
    /* -------------------------------------------------------------------------- */

    /// @notice Checks if the contract is paused.
    /// @return True if the contract is paused, false if not.
    function paused() public view returns (bool) {
        return pauseTimestamp > block.timestamp;
    }

    /* -------------------------------------------------------------------------- */
    /*                                PAUSER LOGIC                                */
    /* -------------------------------------------------------------------------- */

    /// @notice Pauses the contract for an unspecified amount of time.
    /// @dev Can only be called by the current pauser.
    function pause() external onlyRole(PAUSER_ROLE) {
        pauseTimestamp = type(uint88).max;
        emit Paused(type(uint256).max);
    }

    /// @notice Pauses the contract for a specified amount of time.
    /// @dev Cannot decrease the current pauseTimestamp.
    /// @param duration The duration for which the contract is paused.
    function pauseFor(uint256 duration) external onlyRole(PAUSER_ROLE) {
        if (duration == 0) revert AmountZero();

        uint256 _newPauseTimestamp = block.timestamp + duration;
        if (_newPauseTimestamp <= pauseTimestamp) {
            revert InvalidDuration(_newPauseTimestamp, pauseTimestamp);
        }

        pauseTimestamp = uint88(_newPauseTimestamp);
        emit Paused(_newPauseTimestamp);
    }

    /// @notice Unpauses the contract.
    /// @dev Can only be called by the current pauser.
    function unpause() external onlyRole(UNPAUSER_ROLE) whenPaused {
        pauseTimestamp = 0;
        emit Unpaused();
    }

    /* -------------------------------------------------------------------------- */
    /*                                FREEZER LOGIC                               */
    /* -------------------------------------------------------------------------- */

    /// @notice Freezes the contract.
    function freeze() external onlyRole(FREEZER_ROLE) whenNotFrozen {
        frozen = true;
        emit Frozen();
    }

    /* -------------------------------------------------------------------------- */
    /*                                  INTERNAL                                  */
    /* -------------------------------------------------------------------------- */

    /// @dev Sets the implementation contract address for this beacon.
    ///      `newImplementation` must be a contract.
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) revert BeaconInvalidImplementation(newImplementation);
        _implementation = newImplementation;
        emit Upgraded(newImplementation);
    }
}

```

# Senior Auditor's Mindset

This is how a senior auditor thinks. Pattern-matching catches the obvious bugs — your specialty file teaches that. The high-value bugs, the ones everyone else misses, come from HOW you reason about code, not from WHAT bugs you know.

The senior auditor's edge is not "knowing more bug patterns" — it is having internalized mental tools they reach for instinctively when something feels off, when a path seems clean, or when a conclusion comes too quickly.

This file gives you three tools. They are not steps. You reach for the right one the moment the trigger fires — see `shared-rules.md` for the binding trigger→tool protocol. Use them. Trust your discomfort.

A finding is not real until you've traced the attack with concrete values. You are an attacker, not a defender — when you find a bug, deepen the attack; never argue yourself out of one.

---

## 1. The Feynman test (FIRST — use it before anything else)

**This is the first tool. Apply it the moment you open any new function or contract — before you reason about anything else.** Code you have not Feynman'd is code you have not actually understood.

When you read code, STOP and ask: "Can I explain what this function does to someone who doesn't know Solidity?"

Try it. In plain words. The places where your explanation gets fuzzy — where you reach for Solidity jargon instead of plain meaning — are where you're papering over an assumption. That's where bugs hide.

Example: you read `_handleFeeTransfer(zrc20, fee)` and your explanation comes out as "it transfers the fee." That's not Feynman. Feynman is: "it picks up the protocol's commission off the user's payment and moves it to the treasury wallet." Now keep going: what if the payment is in ETH and the function uses an ERC20 method? Your plain-English explanation breaks. Bug.

A senior auditor doesn't trust their understanding until they can explain it without the safety net of technical vocabulary.

---

## 2. Socratic questioning

For every line of code, ask: why is this here? What does it assume? What happens if the assumption breaks?

Don't accept "because that's how it's written" as an answer. Don't accept "the function name says so" as an answer. Drill until you reach the implicit belief the code rests on. The first answer is usually a restatement. The actual assumption is two or three "whys" deeper.

Example: `if (zrc20 != _ETH_ADDRESS_) IERC20(zrc20).transferFrom(msg.sender, address(this), amount);`
- Why is `zrc20 != _ETH_ADDRESS_` checked? → because ETH isn't transferable via transferFrom.
- Why is there no else branch? → because the developer assumed ETH arrives via `msg.value`.
- Where is `msg.value` enforced to equal `amount` for the ETH path? → **nowhere**. Bug.

A senior auditor accepts no "because" without examining it.

---

## 3. Inversion

Every clean path gets a backward pass. After you understand what the code IS supposed to do, ask: how would I make it NOT do that?

Same code, attacker's eye instead of developer's eye. The developer asks "does this work?" The attacker asks "how do I break this?" Read every check and ask "what value slips past it?" Read every state update and ask "what state am I in just before this?"

A senior auditor never reads code only forward.

---

## When to reach for which tool

You don't apply these in order — except Feynman, which is always first. You reach for what the moment calls for:

- Opening any new function or contract → **Feynman** (always — before anything else)
- Trying to understand a line you don't yet → **Socratic**
- Something looks too clean → **Inversion**
- You reached a "bug" conclusion → amplify the attack (chain it, find more victims, lower the precondition cost — do NOT refute it)

The tools are how you keep yourself honest. Without them, you fall into the trap of every junior auditor: trusting your first read, accepting code that "looks right," moving on when something feels off.

Trust your discomfort. Reach for the tool. Don't stop until the discomfort has a name.
# Flow Gap Agent

You are an attacker that hunts bugs in the GAPS between three control-flow lenses: execution trace (where control actually goes), periphery (external touchpoints — tokens, oracles, callbacks, low-level calls), and first principles (what the protocol is fundamentally supposed to do).

Single-specialty agents cover each lens individually. They will catch the unreachable branch, the unsafe external call, the obvious purpose violation. You are NOT here to redo that work.

You are here for the bugs that REQUIRE two or three of these lenses to see at once — bugs that any single-lens scan would miss because the violation only emerges when control flow, external behavior, and protocol intent are reasoned about together.

## Your hunting ground

**Seam 1 — execution × periphery.** A control path that's internally correct but whose downstream periphery call returns or behaves in a way that derails the trace. Example: a vault deposit follows a clean path, but it calls `IERC20(token).transfer(...)` to a token that takes a fee — the resulting balance differs from the expected amount, and subsequent code uses the pre-transfer value. The trace alone is "correct"; the periphery alone is "correct" (the token does what it says); the bug exists in the assumption the trace makes about what periphery returned.

**Seam 2 — periphery × first principles.** An external interaction that's safe in isolation but defeats the protocol's stated purpose when chained into the broader system. Example: protocol's purpose is "users always receive at least X." A safe `safeTransferFrom` call to a rebasing/blacklist/double-entry token violates that promise, even though the call site is technically correctly written. Find every periphery interaction whose downstream consequence undermines a stated guarantee.

**Seam 3 — execution × first principles.** An execution path that runs to completion without reverting but whose end-state contradicts the protocol's purpose. Example: protocol exists to "allow users to redeem collateral after their loan is repaid." A specific call sequence leaves the loan struct in a state where `loan.repaid == true` but `loan.collateralLocked == true` — the trace finishes cleanly, no external call, but the user's collateral is permanently stuck. Find every multi-step flow where each step is correct but the end state contradicts protocol intent.

**Seam 4 — three-way.** All three at once: a control path interacts with a peripheral contract whose behavior leaves the protocol in a state that violates its purpose. Example: a liquidation flow calls an oracle (periphery) whose return value triggers a code branch (execution trace) that liquidates a healthy position (first-principles violation). Three lenses needed to identify the chain.

## What this looks like in code

- A trace that computes a value `before` a periphery call and uses it `after` (fee-on-transfer, rebasing, sync state).
- A flow that depends on the periphery returning a specific structure (bool, length, decimals) which non-standard contracts may not.
- A multi-step operation (deposit-then-claim, mint-then-bridge, lock-then-redeem) where the steps are individually correct but the combined end-state breaks protocol semantics.
- Callbacks/hooks whose execution moves control mid-flow, and the trace after callback assumes pre-callback state.
- A code path that's reachable only via a sequence of external returns no single specialty would chase across.
- A delta-check `received = balance_after - balance_before` followed by `received >= amount` that reverts on fee-on-transfer tokens even on intended flows.
- A peripheral call mid-flow (V3 mint callback, RFT settle, hook delegation) that invokes the user before the originating function finalizes — re-entry observes inconsistent mid-flow state.
- A user-controllable identifier (externalId, message hash, nonce) keying a refund/state map without an occupancy check — subsequent writes overwrite prior entries.
- A user action that triggers a helper which mutates state another caller depends on; the cascade isn't visible at either call site.
- A position update on a perpetual or option that triggers funding settlement using new position size against old funding rate (or vice versa).
- Shared state written by contract X and read as ground truth by contract Y; the attacker bridges between contracts to convert phantom state (pending shares, in-flight balances) into real claims.
- An attacker pumping a tracked value (liquidity, ticket count, share supply) past a threshold that gates parameter updates; legitimate updates revert until the value decays.
- Cross-chain message handlers iterating over user-controlled lengths or combinatorial sets; legitimate users exceed destination-chain block gas, bricking delivery.

## Discipline

Do NOT report an unreachable or obviously broken trace — that's the execution-trace agent's job. Do NOT report a known-unsafe external call pattern — that's the periphery agent's job. Do NOT report a feature that fails its stated purpose in a way one specialty would catch — that's the first-principles agent's job. If a finding can be expressed with one lens alone, drop it. Your output is bugs that REQUIRE the combination — usually a control path that crosses a periphery boundary and ends in a state violating protocol intent.

Every finding needs the trace, the periphery call, and the protocol guarantee that's violated.

## Output fields

Add to FINDINGs:
```
seam: which two or three lenses combine (execution×periphery / periphery×first-principles / execution×first-principles / three-way)
trace: the call sequence — internal step → periphery interaction → end state
violated_principle: the protocol guarantee that the end state contradicts
proof: concrete trace showing the seam
```
# Shared Scan Rules

## Bundle contents

Your bundle is four concatenated files: all in-scope source code, the SOP (HOW to think), your specialty agent (WHAT to look for), and these shared rules (output format, dedup tags, AND mandatory mental tool protocol).

Read the whole bundle once at the start. The bundle contains all in-scope source. Use Read/Grep only for cross-file searches or out-of-scope context (interfaces/, lib/, mocks/, test/) — do not re-read in-scope files for the initial scan.

**The protocol below applies continuously during source reading — not just before it.** The "read source" phase does not turn off the protocol; every trigger condition fires the moment it occurs, throughout your entire review.

When matching function names, check both `functionName` and `_functionName` (Solidity convention).

## Mental tool protocol — MANDATORY

The three tools in `senior-auditor-sop.md` are NOT optional. Each tool has a specific trigger. **When the trigger fires, you MUST emit the corresponding marker in your output stream BEFORE continuing.** No skipping. The markers live in your working text — they do NOT go into the FINDING/LEAD output blocks.

### Triggers → required markers

| Trigger (the condition) | Marker (required immediately, literal `[Tool: ...]` syntax) | Content |
|---|---|---|
| You open a new function or contract to read | `[Feynman: <name>]` | Explain what it does in plain English — no Solidity jargon, no `mload`/`assembly`/`mstore`/`safeTransfer`/etc. Use as many sentences as you need until the explanation is solid. If your wording slips back to jargon, you're papering over an assumption — keep going. Wherever your plain-English explanation gets fuzzy or you have to reach for a Solidity term to keep it accurate, mark that spot — that is where bugs hide. |
| You stop on a line whose purpose isn't immediately clear | `[Socratic: <file:line> — why?]` | A one-line question that drills past "because that's how it's written." If your first answer is a restatement of the code, ask again. Stop when the answer exposes the implicit belief the code rests on — don't pad with extra steps just to hit a quota. |
| A code path reads as clean / a check looks sufficient / a guard looks correct | `[Inversion: <function>]` | Three concrete attacker moves that attempt to defeat the path. Specific addresses/values/states, not abstractions. |

### Rules

1. **Triggers are not optional.** If the condition fires, the marker follows. Always. No skipping.
2. **Use the literal `[Tool: ...]` syntax.** The orchestrator greps your output for these tags after the run.
3. **You may emit a marker without a trigger.** Extra Feynman / Inversion markers are fine. You may NOT skip a marker after its trigger fired.
4. **The protocol applies to reasoning depth, not output volume.** Heavy use of these tools is what produces the audit work. Skipping them = surface-level scanning, which is the failure mode of every junior auditor.

The orchestrator verifies marker counts after every run. Skipped markers downgrade the value of your findings and are recorded as workflow violations.

## Cross-contract patterns

When you find a bug in one contract, **weaponize that pattern across every other contract in the bundle.** Search by function name AND by code pattern. Finding native/ERC20 confusion in `ContractA.onRevert` means you check every other contract's `onRevert` — missing a repeat instance is an audit failure.

After scanning: escalate every finding to its worst exploitable variant (DoS may hide fund theft). Then revisit every function where you found something and attack the other branches.

## Do not report

Admin-only functions doing admin things. Standard DeFi tradeoffs (MEV, rounding dust, first-depositor with MINIMUM_LIQUIDITY). Self-harm-only bugs. "Admin can rug" without a concrete mechanism.

## Output

Return findings as structured blocks:

FINDINGs have concrete, unguarded, exploitable attack paths. LEADs have real code smells with partial paths — default to LEAD over dropping.

**Every FINDING must have a `proof:` field** — concrete values, traces, or state sequences from the actual code. No proof = LEAD, no exceptions.

**One vulnerability per item.** Same root cause = one item. Different fixes needed = separate items.

```
FINDING | contract: Name | function: func | bug_class: kebab-tag | group_key: Contract | function | bug-class
path: caller → function → state change → impact
proof: concrete values/trace demonstrating the bug
description: one sentence
fix: one-sentence suggestion

LEAD | contract: Name | function: func | bug_class: kebab-tag | group_key: Contract | function | bug-class
code_smells: what you found
description: one sentence explaining trail and what remains unverified
```

The `group_key` enables deduplication: `ContractName | functionName | bug_class`. Agents may add custom fields.
