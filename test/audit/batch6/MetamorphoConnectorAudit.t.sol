// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {ERC4626Mock} from "./mocks/ERC4626Mock.sol";

contract MetamorphoConnectorAuditTest is Test {
    using SafeERC20 for IERC20;

    IERC20 asset;
    ERC4626Mock metaMorpho;
    MetamorphoConnectorUnderTest connector;

    function setUp() public {
        asset = IERC20(address(new Mock20("USDC", "USDC", 6)));
        metaMorpho = new ERC4626Mock(asset, "MetaMorpho USDC", "mmUSDC", 6);
        connector = new MetamorphoConnectorUnderTest(address(metaMorpho));
    }

    function test_deposit() public {
        uint256 amount = 100_000 * 10 ** 6;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        // Shares minted to connector (acts as vault via delegatecall)
        assertGt(metaMorpho.balanceOf(address(connector)), 0, "shares minted");
    }

    function test_depositWithdraw() public {
        uint256 amount = 100_000 * 10 ** 6;
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
        uint256 amount = 100_000 * 10 ** 6;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        // Simulate 5% yield via exchange rate increase
        metaMorpho.setExchangeRate(1.05e18);

        uint256 totalAfter = connector.totalAssets(IERC20(address(asset)));
        assertApproxEqRel(
            totalAfter,
            (amount * 105) / 100,
            0.01e18,
            "yield reflected"
        );
    }

    function test_partialWithdraw() public {
        uint256 amount = 100_000 * 10 ** 6;
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        asset.safeTransfer(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);

        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), 50_000 * 10 ** 6);
        uint256 got = asset.balanceOf(address(this)) - pre;
        assertEq(got, 50_000 * 10 ** 6, "partial withdrawal");
    }

    function test_maxFunctions() public {
        // By default, unlimited
        assertEq(
            connector.maxDeposit(IERC20(address(asset))),
            type(uint256).max,
            "maxDeposit"
        );
        assertEq(
            connector.maxWithdraw(IERC20(address(asset))),
            type(uint256).max,
            "maxWithdraw"
        );

        // When vault limits are set, connector reflects them
        metaMorpho.setMaxDepositCap(1000);
        metaMorpho.setMaxWithdrawCap(2000);
        assertEq(
            connector.maxDeposit(IERC20(address(asset))),
            1000,
            "maxDeposit limited"
        );
        assertEq(
            connector.maxWithdraw(IERC20(address(asset))),
            2000,
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

/// @notice Minimal MetaMorpho connector replica using ERC4626Mock.
contract MetamorphoConnectorUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable metamorpho;
    constructor(address _m) {
        metamorpho = _m;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return
            ERC4626Mock(metamorpho).previewRedeem(
                ERC4626Mock(metamorpho).balanceOf(address(this))
            );
    }
    function deposit(IERC20 asset, uint256 amount) external {
        asset.forceApprove(metamorpho, amount);
        ERC4626Mock(metamorpho).deposit(amount, address(this));
    }
    function withdraw(IERC20 asset, uint256 amount) external {
        ERC4626Mock(metamorpho).withdraw(amount, address(this), address(this));
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
        return ERC4626Mock(metamorpho).maxDeposit(address(this));
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return ERC4626Mock(metamorpho).maxWithdraw(address(this));
    }
}
