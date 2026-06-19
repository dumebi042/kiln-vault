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
