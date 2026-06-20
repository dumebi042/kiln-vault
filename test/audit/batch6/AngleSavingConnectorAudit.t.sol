// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {ERC4626Mock, AngleVaultMock} from "./mocks/ERC4626Mock.sol";

contract AngleSavingConnectorAuditTest is Test {
    using SafeERC20 for IERC20;

    IERC20 asset;
    AngleVaultMock stakingVault;
    AngleConnectorUnderTest connector;

    function setUp() public {
        asset = IERC20(address(new Mock20("stEUR", "stEUR", 18)));
        stakingVault = new AngleVaultMock(asset, "Staked EUR", "stEUR", 18);
        // Fund vault so totalAssets > 0 (Angle constructor check)
        Mock20(address(asset)).mint(
            address(stakingVault),
            1_000_000 * 10 ** 18
        );
        connector = new AngleConnectorUnderTest(address(stakingVault));
    }

    function test_deposit() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        assertGt(
            stakingVault.balanceOf(address(connector)),
            0,
            "staking shares minted"
        );
    }

    function test_depositWithdraw() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        uint256 post = asset.balanceOf(address(this));

        assertEq(post - pre, amount, "full withdrawal");
    }

    function test_yieldAccrual() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        // Simulate yield via exchange rate
        stakingVault.setExchangeRate(1.035e18); // 3.5% yield

        uint256 totalAfter = connector.totalAssets(IERC20(address(asset)));
        assertApproxEqRel(
            totalAfter,
            (amount * 1035) / 1000,
            0.01e18,
            "yield reflected"
        );
    }

    function test_partialWithdraw() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), 75_000 * 10 ** 18);
        uint256 got = asset.balanceOf(address(this)) - pre;
        assertEq(got, 75_000 * 10 ** 18, "partial withdrawal");
    }

    function test_pauseBlocksDeposit() public {
        stakingVault.setPaused(1);

        assertEq(
            connector.maxDeposit(IERC20(address(asset))),
            0,
            "paused -> maxDeposit 0"
        );
        assertEq(
            connector.maxWithdraw(IERC20(address(asset))),
            0,
            "paused -> maxWithdraw 0"
        );
    }

    function test_maxFunctions() public {
        assertEq(
            connector.maxDeposit(IERC20(address(asset))),
            type(uint256).max,
            "maxDeposit default"
        );
        assertEq(
            connector.maxWithdraw(IERC20(address(asset))),
            type(uint256).max,
            "maxWithdraw default"
        );
    }
}

contract Mock20 is IERC20 {
    string public n;
    string public s;
    uint8 public immutable d;
    uint256 public ts;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    constructor(string memory _n, string memory _s, uint8 _d) {
        n = _n;
        s = _s;
        d = _d;
    }
    function name() external view returns (string memory) {
        return n;
    }
    function symbol() external view returns (string memory) {
        return s;
    }
    function decimals() external view returns (uint8) {
        return d;
    }
    function totalSupply() external view returns (uint256) {
        return ts;
    }
    function mint(address to, uint256 amt) external {
        ts += amt;
        balanceOf[to] += amt;
        emit Transfer(address(0), to, amt);
    }
    function transfer(address to, uint256 amt) external returns (bool) {
        _xfer(msg.sender, to, amt);
        return true;
    }
    function approve(address sp, uint256 amt) external returns (bool) {
        allowance[msg.sender][sp] = amt;
        emit Approval(msg.sender, sp, amt);
        return true;
    }
    function transferFrom(
        address f,
        address t,
        uint256 amt
    ) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max)
            allowance[f][msg.sender] -= amt;
        _xfer(f, t, amt);
        return true;
    }
    function _xfer(address f, address t, uint256 amt) internal {
        balanceOf[f] -= amt;
        balanceOf[t] += amt;
        emit Transfer(f, t, amt);
    }
}

/// @notice Minimal Angle connector replica with pause support.
contract AngleConnectorUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable stakingVault;
    constructor(address _s) {
        stakingVault = _s;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return
            AngleVaultMock(stakingVault).previewRedeem(
                AngleVaultMock(stakingVault).balanceOf(address(this))
            );
    }
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(stakingVault, amount);
        AngleVaultMock(stakingVault).deposit(amount, address(this));
    }
    function withdraw(IERC20 asset, uint256 amount) external {
        AngleVaultMock(stakingVault).withdraw(
            amount,
            address(this),
            address(this)
        );
        asset.safeTransfer(msg.sender, amount);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        if (AngleVaultMock(stakingVault).paused() == 1) return 0;
        return AngleVaultMock(stakingVault).maxDeposit(address(this));
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        if (AngleVaultMock(stakingVault).paused() == 1) return 0;
        return AngleVaultMock(stakingVault).maxWithdraw(address(this));
    }
}
