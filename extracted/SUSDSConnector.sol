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

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.20;

import {IERC20} from "../IERC20.sol";
import {IERC20Permit} from "../extensions/IERC20Permit.sol";
import {Address} from "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
