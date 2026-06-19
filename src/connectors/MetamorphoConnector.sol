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
