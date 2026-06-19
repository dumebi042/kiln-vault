contract CompoundV3Connector is IConnector {
    using Address for address;
    using SafeERC20 for IERC20;
    using MultisendLib for address;

    /// @notice Compound Market Registry address.
    MarketRegistry public immutable compoundMarketRegistry;

    /// @notice Compound V3 comet rewards contract.
    ICometRewards public immutable cometRewards;

    /// @notice Swap Target (aggregator or DEX)
    /// @dev If set to address(0), no swap will be performed
    address public immutable swapTarget;

    /// @notice COMP ERC20 address.
    IERC20 public immutable comp;

    constructor(address _compoundMarketRegistry, address _cometRewards, address _swapTarget, address _comp) {
        if (_cometRewards.code.length == 0) revert AddressNotContract(_cometRewards);
        if (_swapTarget.code.length == 0) revert AddressNotContract(_swapTarget);
        if (_comp.code.length == 0) revert AddressNotContract(_comp);
        if (_compoundMarketRegistry.code.length == 0) revert AddressNotContract(_compoundMarketRegistry);
        cometRewards = ICometRewards(_cometRewards);
        swapTarget = _swapTarget;
        comp = IERC20(_comp);
        compoundMarketRegistry = MarketRegistry(_compoundMarketRegistry);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20 asset) external view returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        return _comet.balanceOf(msg.sender);
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        asset.forceApprove(address(_comet), amount);
        _comet.supply(asset, amount);
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20 asset, uint256 amount) external {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        _comet.withdraw(asset, amount);
    }

    /// @inheritdoc IConnector
    function claim(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override returns (uint256) {
        if (rewardsAsset != comp) revert InvalidRewardsAsset(address(rewardsAsset));

        address _comet = compoundMarketRegistry.getMarket(address(asset));

        // Claim COMP
        uint256 _balanceBefore = rewardsAsset.balanceOf(address(this));
        cometRewards.claim(_comet, address(this), true);
        uint256 _received = rewardsAsset.balanceOf(address(this)) - _balanceBefore;

        if (_received == 0) revert NothingToClaim();

        (address[] memory recipients, uint256[] memory splits) = abi.decode(payload, (address[], uint256[]));
        address(rewardsAsset).multisend(recipients, splits, _received);

        return _received;
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override {
        if (rewardsAsset != comp) revert InvalidRewardsAsset(address(rewardsAsset));

        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        uint256 _balanceBefore = asset.balanceOf(address(this));

        // Claim COMP
        cometRewards.claim(address(_comet), address(this), true);

        // Approve the swap target
        rewardsAsset.forceApprove(address(swapTarget), type(uint256).max);

        // Swap the COMP to the underlying asset
        swapTarget.functionCall(payload);

        uint256 _received = asset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        asset.forceApprove(address(_comet), _received);
        _comet.supply(asset, _received);
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20 asset) external view override returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        if (_comet.isSupplyPaused()) return 0;
        return type(uint256).max;
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20 asset) external view override returns (uint256) {
        IComet _comet = IComet(compoundMarketRegistry.getMarket(address(asset)));
        if (_comet.isWithdrawPaused()) return 0;
        return asset.balanceOf(address(_comet));
    }
}

// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/Math.sol)

pragma solidity ^0.8.20;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
