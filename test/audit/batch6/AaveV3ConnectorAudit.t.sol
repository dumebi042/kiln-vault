// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {AavePoolMock, AaveRewardsMock} from "./mocks/AaveMock.sol";

contract AaveConnectorTest is Test {
    using SafeERC20 for IERC20;

    IERC20 asset;
    AavePoolMock pool;
    AaveRewardsMock rewards;

    // Minimal AaveV3Connector replica using mocks
    AaveV3ConnectorUnderTest connector;

    function setUp() public {
        asset = IERC20(address(new MockERC20("USDC", "USDC", 6)));
        pool = new AavePoolMock(asset);
        rewards = new AaveRewardsMock();
        // Deploy connector with mock addresses
        connector = new AaveV3ConnectorUnderTest(
            address(pool),
            address(0x1234),
            address(0x5678),
            address(rewards)
        );
    }

    function test_deposit() public {
        uint256 amount = 100_000 * 10 ** 6;
        MockERC20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount); // vault pre-funds connector

        connector.deposit(IERC20(address(asset)), amount);

        // After deposit, aTokens credited
        assertGt(pool.balanceOf(address(connector)), 0, "aTokens minted");
    }

    function test_depositWithdraw() public {
        uint256 amount = 100_000 * 10 ** 6;
        MockERC20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        uint256 post = asset.balanceOf(address(this));

        assertEq(post - pre, amount, "Full withdrawal");
    }

    function test_wrongAssetReverts() public {
        IERC20 wrong = IERC20(address(new MockERC20("DAI", "DAI", 18)));
        vm.expectRevert();
        connector.deposit(wrong, 100);
    }

    function test_liquidityIndexChange() public {
        uint256 amount = 100_000 * 10 ** 6;
        MockERC20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        // Simulate yield via liquidity index increase
        pool.setIndex(1.05e27); // 5% yield

        uint256 totalAfter = connector.totalAssets(IERC20(address(asset)));
        assertApproxEqRel(
            totalAfter,
            (amount * 105) / 100,
            0.01e18,
            "Yield reflected"
        );
    }

    function test_partialWithdraw() public {
        uint256 amount = 100_000 * 10 ** 6;
        MockERC20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), 50_000 * 10 ** 6);
        uint256 got = asset.balanceOf(address(this)) - pre;
        assertEq(got, 50_000 * 10 ** 6, "Partial withdraw");
    }
}

// Minimal ERC20 for testing
contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    constructor(string memory n, string memory s, uint8 d) {
        name = n;
        symbol = s;
        decimals = d;
    }
    function mint(address to, uint256 amt) external {
        totalSupply += amt;
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
        uint256 allowed = allowance[f][msg.sender];
        if (allowed != type(uint256).max)
            allowance[f][msg.sender] = allowed - amt;
        _xfer(f, t, amt);
        return true;
    }
    function _xfer(address f, address t, uint256 amt) internal {
        balanceOf[f] -= amt;
        balanceOf[t] += amt;
        emit Transfer(f, t, amt);
    }
}

// AaveV3Connector extracted for testing with mock pool
contract AaveV3ConnectorUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable aave;
    address public immutable poolAddressesProvider;
    address public immutable swapTarget;
    address public immutable rewardsController;

    constructor(
        address _aave,
        address _provider,
        address _swap,
        address _rewards
    ) {
        aave = _aave;
        poolAddressesProvider = _provider;
        swapTarget = _swap;
        rewardsController = _rewards;
    }

    function totalAssets(IERC20 a) external view returns (uint256) {
        return AavePoolMock(aave).balanceOf(address(this));
    }

    function deposit(IERC20 a, uint256 amount) external {
        require(
            address(a) == address(AavePoolMock(aave).asset()),
            "wrong asset"
        );
        a.forceApprove(aave, amount);
        AavePoolMock(aave).supply(address(a), amount, address(this), 0);
    }

    function withdraw(IERC20 a, uint256 amount) external {
        AavePoolMock(aave).withdraw(address(a), amount, address(this));
        a.safeTransfer(msg.sender, amount);
    }

    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external pure returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20 a) external view returns (uint256) {
        return AavePoolMock(aave).balanceOf(address(this));
    }
}
