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
