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
