// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";

contract CometMock {
    IERC20 public baseToken;
    mapping(address => uint256) public basePrincipal;
    uint256 public accruedPerSecond = 1e16; // 1% per ~3 years
    bool public supplyPaused;
    bool public withdrawPaused;

    constructor(IERC20 _base) {
        baseToken = _base;
    }
    function setSupplyPause(bool v) external {
        supplyPaused = v;
    }
    function setWithdrawPause(bool v) external {
        withdrawPaused = v;
    }
    function setAccruedPerSecond(uint256 v) external {
        accruedPerSecond = v;
    }

    function supply(IERC20 a, uint256 amt) external {
        require(!supplyPaused, "paused");
        require(a == baseToken, "wrong asset");
        baseToken.transferFrom(msg.sender, address(this), amt);
        basePrincipal[msg.sender] += amt;
    }

    function withdraw(IERC20 a, uint256 amt) external {
        require(!withdrawPaused, "paused");
        require(a == baseToken, "wrong asset");
        uint256 bal = balanceOf(msg.sender);
        uint256 actual = amt < bal ? amt : bal;
        uint256 principalAmt = (actual * 1e18) / (1e18 + accruedPerSecond);
        if (principalAmt > basePrincipal[msg.sender])
            principalAmt = basePrincipal[msg.sender];
        basePrincipal[msg.sender] -= principalAmt;
        baseToken.transfer(msg.sender, actual);
    }

    function balanceOf(address user) public view returns (uint256) {
        return (basePrincipal[user] * (1e18 + accruedPerSecond)) / 1e18;
    }

    function isSupplyPaused() external view returns (bool) {
        return supplyPaused;
    }
    function isWithdrawPaused() external view returns (bool) {
        return withdrawPaused;
    }
}

contract CompoundConnectorTest is Test {
    using SafeERC20 for IERC20;

    IERC20 base;
    CometMock comet;
    CompoundConnectorUnderTest connector;

    function setUp() public {
        base = IERC20(address(new Mock20("USDC", "USDC", 6)));
        comet = new CometMock(base);
        connector = new CompoundConnectorUnderTest(address(comet));
    }

    function test_depositWithdraw() public {
        uint256 amt = 100_000 * 10 ** 6;
        Mock20(address(base)).mint(address(this), amt);
        base.approve(address(connector), amt);
        base.safeTransfer(address(connector), amt);
        connector.deposit(base, amt);

        uint256 pre = base.balanceOf(address(this));
        connector.withdraw(base, amt);
        assertEq(base.balanceOf(address(this)) - pre, amt, "Full withdraw");
    }

    function test_accruedInterest() public {
        uint256 amt = 100_000 * 10 ** 6;
        Mock20(address(base)).mint(address(this), amt);
        base.approve(address(connector), amt);
        base.safeTransfer(address(connector), amt);
        connector.deposit(base, amt);

        // Simulate accrued interest (5%: 0.05e18)
        comet.setAccruedPerSecond(0.05e18);
        uint256 total = connector.totalAssets(base);
        assertApproxEqRel(
            total,
            (amt * 105) / 100,
            0.01e18,
            "interest accrued"
        );
    }

    function test_supplyPause() public {
        comet.setSupplyPause(true);
        assertEq(connector.maxDeposit(base), 0, "supply paused -> 0");
    }

    function test_withdrawPause() public {
        comet.setWithdrawPause(true);
        assertEq(connector.maxWithdraw(base), 0, "withdraw paused -> 0");
    }

    function test_wrongAssetReverts() public {
        IERC20 wrong = IERC20(address(new Mock20("DAI", "DAI", 18)));
        vm.expectRevert();
        connector.deposit(wrong, 100);
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

contract CompoundConnectorUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable market;
    constructor(address _m) {
        market = _m;
    }
    function totalAssets(IERC20 a) external view returns (uint256) {
        return CometMock(market).balanceOf(address(this));
    }
    function deposit(IERC20 a, uint256 amt) external {
        a.forceApprove(market, amt);
        CometMock(market).supply(a, amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        CometMock(market).withdraw(a, amt);
        a.safeTransfer(msg.sender, amt);
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
        return CometMock(market).isSupplyPaused() ? 0 : type(uint256).max;
    }
    function maxWithdraw(IERC20 a) external view returns (uint256) {
        return
            CometMock(market).isWithdrawPaused()
                ? 0
                : CometMock(market).balanceOf(address(this));
    }
}
