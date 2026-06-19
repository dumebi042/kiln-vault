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

import {Address} from "@openzeppelin/utils/Address.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AddressNotContract, NothingToClaim, NothingToReinvest} from "../libraries/Errors.sol";
import {IConnector, IERC20} from "../interfaces/IConnector.sol";
import {MultisendLib} from "../libraries/MultisendLib.sol";

/// @dev Partial IPool interface.
interface Aave {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}

/// @dev Partial IPoolAddressesProvider interface.
interface IPoolAddressesProvider {
    function getPoolDataProvider() external view returns (address);
}

/// @dev Partial IRewardsController interface.
interface IRewardsController {
    function claimAllRewards(address[] calldata assets, address to) external;
}

/// @dev Partial IPoolDataProvider interface.
interface IPoolDataProvider {
    function getReserveTokensAddresses(address asset) external view returns (address, address, address);
    function getReserveConfigurationData(address asset)
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
    function getReserveData(address asset)
        external
        view
        returns (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 liquidityRate,
            uint256 variableBorrowRate,
            uint256 stableBorrowRate,
            uint256 averageStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint40 lastUpdateTimestamp
        );
    function getReserveCaps(address asset) external view returns (uint256 borrowCap, uint256 supplyCap);
    function getPaused(address asset) external view returns (bool);
}

/// @title Aave V3 Connector.
/// @author maximebrugel @ Kiln.
contract AaveV3Connector is IConnector {
    using Address for address;
    using SafeERC20 for IERC20;
    using MultisendLib for address;

    /// @notice Aave V3 lending pool address.
    Aave public immutable aave;

    /// @notice Aave V3 rewards controller contract.
    IRewardsController public immutable rewardsController;

    /// @notice Swap Target (aggregator or DEX)
    /// @dev If set to address(0), no swap will be performed
    address public immutable swapTarget;

    /// @notice Aave V3 pool addresses provider address.
    IPoolAddressesProvider public immutable poolAddressesProvider;

    constructor(address _aave, address _poolAddressesProvider, address _swapTarget, address _rewardController) {
        if (_aave.code.length == 0) revert AddressNotContract(_aave);
        if (_poolAddressesProvider.code.length == 0) revert AddressNotContract(_poolAddressesProvider);
        if (_swapTarget.code.length == 0) revert AddressNotContract(_swapTarget);
        if (_rewardController.code.length == 0) revert AddressNotContract(_rewardController);
        aave = Aave(_aave);
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        swapTarget = _swapTarget;
        rewardsController = IRewardsController(_rewardController);
    }

    /// @inheritdoc IConnector
    function totalAssets(IERC20 asset) external view returns (uint256) {
        IPoolDataProvider _poolDataProvider = IPoolDataProvider(poolAddressesProvider.getPoolDataProvider());
        (address _aToken,,) = _poolDataProvider.getReserveTokensAddresses(address(asset));
        return IERC20(_aToken).balanceOf(msg.sender);
    }

    /// @inheritdoc IConnector
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(address(aave), amount);
        aave.supply(address(asset), amount, address(this), 0);
    }

    /// @inheritdoc IConnector
    function withdraw(IERC20 asset, uint256 amount) external {
        aave.withdraw(address(asset), amount, address(this));
    }

    /// @inheritdoc IConnector
    function claim(IERC20, IERC20 rewardsAsset, bytes calldata payload) external override returns (uint256) {
        address[] memory _rewardsAssetsParam = new address[](1);
        _rewardsAssetsParam[0] = address(rewardsAsset);

        uint256 _balanceBefore = rewardsAsset.balanceOf(address(this));
        rewardsController.claimAllRewards(_rewardsAssetsParam, address(this));

        uint256 _received = rewardsAsset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        (address[] memory recipients, uint256[] memory splits) = abi.decode(payload, (address[], uint256[]));
        address(rewardsAsset).multisend(recipients, splits, _received);

        return _received;
    }

    /// @inheritdoc IConnector
    function reinvest(IERC20 asset, IERC20 rewardsAsset, bytes calldata payload) external override {
        address[] memory _rewardsAssetsParam = new address[](1);
        _rewardsAssetsParam[0] = address(rewardsAsset);

        uint256 _balanceBefore = asset.balanceOf(address(this));
        rewardsController.claimAllRewards(_rewardsAssetsParam, address(this));

        // Approve the swap target
        rewardsAsset.forceApprove(address(swapTarget), type(uint256).max);

        // Swap the rewardsAsset to the underlying asset
        swapTarget.functionCall(payload);

        uint256 _received = asset.balanceOf(address(this)) - _balanceBefore;
        if (_received == 0) revert NothingToClaim();

        asset.forceApprove(address(aave), _received);
        aave.supply(address(asset), _received, address(this), 0);
    }

    /// @inheritdoc IConnector
    function maxDeposit(IERC20 asset) external view override returns (uint256) {
        IPoolDataProvider _poolDataProvider = IPoolDataProvider(poolAddressesProvider.getPoolDataProvider());
        (,,,,,,,, bool _isActive, bool _isFrozen) = _poolDataProvider.getReserveConfigurationData(address(asset));
        bool _isPaused = _poolDataProvider.getPaused(address(asset));
        if (!_isActive || _isFrozen || _isPaused) {
            return 0;
        }

        (, uint256 _rawSupplyCap) = _poolDataProvider.getReserveCaps(address(asset));

        // If not capped
        if (_rawSupplyCap == 0) {
            return type(uint256).max;
        }

        // We need to scale the supply cap to the asset decimals
        uint256 _supplyCap = _rawSupplyCap * 10 ** IERC20Metadata(address(asset)).decimals();

        (, uint256 _accruedToTreasuryScaled, uint256 _totalAToken,,,,,,,,,) =
            _poolDataProvider.getReserveData(address(asset));

        // If supply cap already reached
        if (_totalAToken + _accruedToTreasuryScaled >= _supplyCap) {
            return 0;
        }

        return _supplyCap - (_totalAToken + _accruedToTreasuryScaled);
    }

    /// @inheritdoc IConnector
    function maxWithdraw(IERC20 asset) external view override returns (uint256) {
        IPoolDataProvider _poolDataProvider = IPoolDataProvider(poolAddressesProvider.getPoolDataProvider());
        (,,,,,,,, bool _isActive,) = _poolDataProvider.getReserveConfigurationData(address(asset));
        bool _isPaused = _poolDataProvider.getPaused(address(asset));
        if (!_isActive || _isPaused) {
            return 0;
        }

        (address _aToken,,) = _poolDataProvider.getReserveTokensAddresses(address(asset));
        return asset.balanceOf(address(_aToken));
    }
}
