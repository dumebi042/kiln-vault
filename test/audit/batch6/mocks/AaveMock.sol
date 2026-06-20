// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// Aave pool mock with aToken rebasing
contract AavePoolMock {
    IERC20 public asset;
    mapping(address => uint256) public aTokenBalance; // vault -> aToken balance
    uint256 public liquidityIndex = 1e27; // scaled by 1e27 per Aave

    constructor(IERC20 _asset) {
        asset = _asset;
    }

    function setIndex(uint256 idx) external {
        liquidityIndex = idx;
    }

    function supply(
        address token,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external {
        require(token == address(asset), "wrong asset");
        asset.transferFrom(msg.sender, address(this), amount);
        // Mint aTokens (1:1 at index 1e27)
        uint256 aTokens = (amount * 1e27) / liquidityIndex;
        aTokenBalance[onBehalfOf] += aTokens;
    }

    function withdraw(
        address token,
        uint256 amount,
        address to
    ) external returns (uint256) {
        require(token == address(asset), "wrong asset");
        uint256 aTokensNeeded = (amount * 1e27) / liquidityIndex;
        uint256 available = aTokenBalance[msg.sender];
        if (amount == type(uint256).max) {
            uint256 actual = (available * liquidityIndex) / 1e27;
            aTokenBalance[msg.sender] = 0;
            asset.transfer(to, actual);
            return actual;
        }
        require(aTokensNeeded <= available, "insufficient");
        aTokenBalance[msg.sender] -= aTokensNeeded;
        asset.transfer(to, amount);
        return amount;
    }

    function scaledBalance(address user) external view returns (uint256) {
        return aTokenBalance[user];
    }
    function balanceOf(address user) external view returns (uint256) {
        return (aTokenBalance[user] * liquidityIndex) / 1e27;
    }
}

contract AaveRewardsMock {
    function claimAllRewards(address[] calldata, address to) external {
        // No-op mock — real rewards require forked test
    }
}
