// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";

contract SDAIConnectorAuditTest is Test {
    using SafeERC20 for IERC20;

    IERC20 asset;
    ERC4626Mock sDai;
    SDAIConnectorUnderTest connector;

    function setUp() public {
        asset = IERC20(address(new Mock20("DAI", "DAI", 18)));
        sDai = new ERC4626Mock(asset, "Savings DAI", "sDAI", 18);
        connector = new SDAIConnectorUnderTest(address(sDai));
    }

    function test_deposit() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        // sDAI shares minted to connector (acts as vault via delegatecall)
        assertGt(sDai.balanceOf(address(connector)), 0, "sDAI shares minted");
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

    function test_conversionRateChange() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        // DSR accumulates: sDAI/DAI conversion rate increases
        sDai.setExchangeRate(1.08e18); // 8% yield

        uint256 totalAfter = connector.totalAssets(IERC20(address(asset)));
        assertApproxEqRel(
            totalAfter,
            (amount * 108) / 100,
            0.01e18,
            "DSR yield reflected"
        );
    }

    function test_partialWithdraw() public {
        uint256 amount = 100_000 * 10 ** 18;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), 50_000 * 10 ** 18);
        uint256 got = asset.balanceOf(address(this)) - pre;
        assertEq(got, 50_000 * 10 ** 18, "partial withdrawal");
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

        sDai.setMaxDepositCap(5000);
        sDai.setMaxWithdrawCap(8000);
        assertEq(
            connector.maxDeposit(IERC20(address(asset))),
            5000,
            "maxDeposit limited"
        );
        assertEq(
            connector.maxWithdraw(IERC20(address(asset))),
            8000,
            "maxWithdraw limited"
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

/// @notice Minimal sDAI connector replica.
contract SDAIConnectorUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable sDAI;
    constructor(address _s) {
        sDAI = _s;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return
            ERC4626Mock(sDAI).previewRedeem(
                ERC4626Mock(sDAI).balanceOf(address(this))
            );
    }
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(sDAI, amount);
        ERC4626Mock(sDAI).deposit(amount, address(this));
    }
    function withdraw(IERC20 asset, uint256 amount) external {
        ERC4626Mock(sDAI).withdraw(amount, address(this), address(this));
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
        return ERC4626Mock(sDAI).maxDeposit(address(this));
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return ERC4626Mock(sDAI).maxWithdraw(address(this));
    }
}
