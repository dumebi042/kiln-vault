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
