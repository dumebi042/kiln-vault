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

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC4626.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @dev Interface of the ERC4626 "Tokenized Vault Standard", as defined in
 * https://eips.ethereum.org/EIPS/eip-4626[ERC-4626].
 */
