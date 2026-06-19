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
