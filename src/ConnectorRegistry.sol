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
