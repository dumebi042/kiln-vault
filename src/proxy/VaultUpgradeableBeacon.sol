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
