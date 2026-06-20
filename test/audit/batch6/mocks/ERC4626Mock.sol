// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/interfaces/IERC4626.sol";

/// @notice Minimal ERC4626 vault mock for connector testing.
/// Supports configurable exchange rate for yield simulation.
contract ERC4626Mock is IERC4626 {
    IERC20 public immutable asset_;
    string public name_;
    string public symbol_;
    uint8 public immutable decimals_;

    uint256 public exchangeRate = 1e18; // 1 share = 1 asset
    uint256 public totalSupply_;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public maxDepositCap = type(uint256).max;
    uint256 public maxWithdrawCap = type(uint256).max;

    constructor(
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        uint8 _dec
    ) {
        asset_ = _asset;
        name_ = _name;
        symbol_ = _symbol;
        decimals_ = _dec;
    }

    function asset() external view returns (address) {
        return address(asset_);
    }
    function name() external view returns (string memory) {
        return name_;
    }
    function symbol() external view returns (string memory) {
        return symbol_;
    }
    function decimals() external view returns (uint8) {
        return decimals_;
    }
    function totalSupply() external view returns (uint256) {
        return totalSupply_;
    }

    function setExchangeRate(uint256 rate) external {
        exchangeRate = rate;
    }
    function setMaxDepositCap(uint256 cap) external {
        maxDepositCap = cap;
    }
    function setMaxWithdrawCap(uint256 cap) external {
        maxWithdrawCap = cap;
    }

    function totalAssets() external view virtual returns (uint256) {
        return asset_.balanceOf(address(this));
    }

    function convertToShares(uint256 assets_) public view returns (uint256) {
        return (assets_ * 1e18) / exchangeRate;
    }

    function convertToAssets(uint256 shares_) public view returns (uint256) {
        return (shares_ * exchangeRate) / 1e18;
    }

    function previewDeposit(uint256 assets_) external view returns (uint256) {
        return convertToShares(assets_);
    }
    function previewMint(uint256 shares_) external view returns (uint256) {
        return convertToAssets(shares_);
    }
    function previewWithdraw(uint256 assets_) external view returns (uint256) {
        return convertToShares(assets_);
    }
    function previewRedeem(uint256 shares_) external view returns (uint256) {
        return convertToAssets(shares_);
    }

    function maxDeposit(address) external view returns (uint256) {
        return maxDepositCap;
    }
    function maxMint(address) external view returns (uint256) {
        return maxDepositCap;
    }
    function maxWithdraw(address) external view returns (uint256) {
        return maxWithdrawCap;
    }
    function maxRedeem(address owner) external view returns (uint256) {
        return balanceOf[owner];
    }

    function deposit(
        uint256 assets_,
        address receiver
    ) external returns (uint256) {
        require(assets_ <= maxDepositCap, "deposit cap");
        uint256 shares_ = convertToShares(assets_);
        asset_.transferFrom(msg.sender, address(this), assets_);
        _mint(receiver, shares_);
        emit Deposit(msg.sender, receiver, assets_, shares_);
        return shares_;
    }

    function mint(
        uint256 shares_,
        address receiver
    ) external returns (uint256) {
        uint256 assets_ = convertToAssets(shares_);
        require(assets_ <= maxDepositCap, "mint cap");
        asset_.transferFrom(msg.sender, address(this), assets_);
        _mint(receiver, shares_);
        emit Deposit(msg.sender, receiver, assets_, shares_);
        return assets_;
    }

    function withdraw(
        uint256 assets_,
        address receiver,
        address owner
    ) external returns (uint256) {
        require(assets_ <= maxWithdrawCap, "withdraw cap");
        uint256 shares_ = convertToShares(assets_);
        _burn(owner, shares_);
        asset_.transfer(receiver, assets_);
        emit Withdraw(msg.sender, receiver, owner, assets_, shares_);
        return shares_;
    }

    function redeem(
        uint256 shares_,
        address receiver,
        address owner
    ) external returns (uint256) {
        uint256 assets_ = convertToAssets(shares_);
        require(assets_ <= maxWithdrawCap, "redeem cap");
        _burn(owner, shares_);
        asset_.transfer(receiver, assets_);
        emit Withdraw(msg.sender, receiver, owner, assets_, shares_);
        return assets_;
    }

    function _mint(address to, uint256 shares_) internal {
        totalSupply_ += shares_;
        balanceOf[to] += shares_;
        emit Transfer(address(0), to, shares_);
    }

    function _burn(address from, uint256 shares_) internal {
        totalSupply_ -= shares_;
        balanceOf[from] -= shares_;
        emit Transfer(from, address(0), shares_);
    }

    // ERC20 passthrough
    function transfer(address to, uint256 value) external returns (bool) {
        _xfer(msg.sender, to, value);
        return true;
    }
    function approve(address sp, uint256 value) external returns (bool) {
        allowance[msg.sender][sp] = value;
        emit Approval(msg.sender, sp, value);
        return true;
    }
    function transferFrom(
        address f,
        address t,
        uint256 v
    ) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max)
            allowance[f][msg.sender] -= v;
        _xfer(f, t, v);
        return true;
    }
    function _xfer(address f, address t, uint256 v) internal {
        balanceOf[f] -= v;
        balanceOf[t] += v;
        emit Transfer(f, t, v);
    }
}

/// @notice Mock for Angle staking vault — ERC4626 with pause support (uint8).
contract AngleVaultMock is ERC4626Mock {
    uint8 public pausedFlag;

    constructor(
        IERC20 _asset,
        string memory name,
        string memory symbol,
        uint8 dec
    ) ERC4626Mock(_asset, name, symbol, dec) {}

    function paused() external view returns (uint8) {
        return pausedFlag;
    }
    function setPaused(uint8 flag) external {
        pausedFlag = flag;
    }

    // Override to satisfy Angle constructor requirement
    function totalAssets() external view override returns (uint256) {
        return asset_.balanceOf(address(this));
    }
}
