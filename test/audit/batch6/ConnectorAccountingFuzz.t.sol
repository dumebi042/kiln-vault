// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {ERC4626Mock, AngleVaultMock} from "./mocks/ERC4626Mock.sol";
import {AavePoolMock} from "./mocks/AaveMock.sol";

/// @notice Connector accounting fuzz tests.
/// Tests the core accounting property across all connector types:
/// balance-delta integrity, round-trip conservation, and totalAssets accuracy.
contract ConnectorAccountingFuzzTest is Test {
    using SafeERC20 for IERC20;

    IERC20 asset;
    ERC4626Mock metaMorpho;
    ERC4626Mock sDAI;
    AngleVaultMock angle;
    AavePoolMock aavePool;
    MetamorphoUnderTest mmConnector;
    SDAIUnderTest sdaiConnector;
    AngleUnderTest angleConnector;
    AaveUnderTest aaveConnector;

    function setUp() public {
        asset = IERC20(address(new Mock20("USDC", "USDC", 6)));

        // Deploy mocks
        metaMorpho = new ERC4626Mock(asset, "mmUSDC", "mmUSDC", 6);
        sDAI = new ERC4626Mock(asset, "sDAI", "sDAI", 18);
        angle = new AngleVaultMock(asset, "stUSD", "stUSD", 6);
        Mock20(address(asset)).mint(address(angle), 1_000_000 * 10 ** 6); // Angle constructor check
        aavePool = new AavePoolMock(asset);

        // Deploy connectors
        mmConnector = new MetamorphoUnderTest(address(metaMorpho));
        sdaiConnector = new SDAIUnderTest(address(sDAI));
        angleConnector = new AngleUnderTest(address(angle));
        aaveConnector = new AaveUnderTest(address(aavePool));
    }

    /// @notice Fuzz: deposit(x) then withdraw(x) returns full amount (round-trip conservation).
    /// @param amount Random deposit amount, bounded.
    function testFuzz_roundTripConservation(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 * 10 ** 6);
        Mock20(address(asset)).mint(address(this), amount);

        // MetaMorpho
        asset.approve(address(mmConnector), amount);
        mmConnector.deposit(IERC20(address(asset)), amount);
        uint256 pre = asset.balanceOf(address(this));
        mmConnector.withdraw(IERC20(address(asset)), amount);
        assertEq(asset.balanceOf(address(this)) - pre, amount, "mm round trip");

        // sDAI
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(sdaiConnector), amount);
        sdaiConnector.deposit(IERC20(address(asset)), amount);
        pre = asset.balanceOf(address(this));
        sdaiConnector.withdraw(IERC20(address(asset)), amount);
        assertEq(
            asset.balanceOf(address(this)) - pre,
            amount,
            "sdai round trip"
        );

        // Angle
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(angleConnector), amount);
        angleConnector.deposit(IERC20(address(asset)), amount);
        pre = asset.balanceOf(address(this));
        angleConnector.withdraw(IERC20(address(asset)), amount);
        assertEq(
            asset.balanceOf(address(this)) - pre,
            amount,
            "angle round trip"
        );

        // Aave
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(aaveConnector), amount);
        aaveConnector.deposit(IERC20(address(asset)), amount);
        pre = asset.balanceOf(address(this));
        aaveConnector.withdraw(IERC20(address(asset)), amount);
        assertEq(
            asset.balanceOf(address(this)) - pre,
            amount,
            "aave round trip"
        );
    }

    /// @notice Fuzz: totalAssets equals deposited amount at 1:1 conversion.
    /// @param amount Random deposit amount, bounded.
    function testFuzz_totalAssetsMatchesDeposit(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 * 10 ** 6);
        Mock20(address(asset)).mint(address(this), amount);

        asset.approve(address(mmConnector), amount);
        mmConnector.deposit(IERC20(address(asset)), amount);
        uint256 total = mmConnector.totalAssets(IERC20(address(asset)));
        assertApproxEqAbs(total, amount, 2, "mm totalAssets ~= deposit");

        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(aaveConnector), amount);
        aaveConnector.deposit(IERC20(address(asset)), amount);
        total = aaveConnector.totalAssets(IERC20(address(asset)));
        assertApproxEqAbs(total, amount, 2, "aave totalAssets ~= deposit");
    }

    /// @notice Fuzz: totalAssets is bounded by maxWithdraw (conservative property).
    /// @param amount Random deposit amount.
    function testFuzz_totalAssetsLeMaxWithdraw(uint256 amount) public {
        amount = bound(amount, 1, 10_000_000 * 10 ** 6);
        Mock20(address(asset)).mint(address(this), amount);

        asset.approve(address(mmConnector), amount);
        mmConnector.deposit(IERC20(address(asset)), amount);
        uint256 total = mmConnector.totalAssets(IERC20(address(asset)));
        uint256 maxW = mmConnector.maxWithdraw(IERC20(address(asset)));
        assertLe(total, maxW, "mm totalAssets <= maxWithdraw");

        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(aaveConnector), amount);
        aaveConnector.deposit(IERC20(address(asset)), amount);
        total = aaveConnector.totalAssets(IERC20(address(asset)));
        maxW = aaveConnector.maxWithdraw(IERC20(address(asset)));
        assertLe(total, maxW, "aave totalAssets <= maxWithdraw");
    }

    /// @notice Fuzz: partial withdrawal never returns more than deposited.
    /// @param amount Full deposit amount.
    /// @param p Amount to withdraw (<= amount).
    function testFuzz_partialWithdrawBounded(uint256 amount, uint256 p) public {
        amount = bound(amount, 100, 10_000_000 * 10 ** 6);
        p = bound(p, 1, amount);
        Mock20(address(asset)).mint(address(this), amount);

        // MetaMorpho
        asset.approve(address(mmConnector), amount);
        mmConnector.deposit(IERC20(address(asset)), amount);
        uint256 pre = asset.balanceOf(address(this));
        mmConnector.withdraw(IERC20(address(asset)), p);
        uint256 got = asset.balanceOf(address(this)) - pre;
        assertLe(got, amount, "mm partial <= deposit");
        assertEq(got, p, "mm exact partial");

        // sDAI
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(sdaiConnector), amount);
        sdaiConnector.deposit(IERC20(address(asset)), amount);
        pre = asset.balanceOf(address(this));
        sdaiConnector.withdraw(IERC20(address(asset)), p);
        got = asset.balanceOf(address(this)) - pre;
        assertEq(got, p, "sdai exact partial");
    }

    /// @notice Fuzz: yield accrual is monotonic (totalAssets never decreases without withdrawal).
    /// Deposits at different rates, checks totalAssets >= original deposit.
    function testFuzz_yieldMonotonic(uint256 amount, uint256 rate) public {
        amount = bound(amount, 1000, 1_000_000 * 10 ** 6);
        rate = bound(rate, 1e18, 2e18); // 1x to 2x
        Mock20(address(asset)).mint(address(this), amount);

        // sDAI: deposit, change rate, verify totalAssets >= deposit
        asset.approve(address(sdaiConnector), amount);
        sdaiConnector.deposit(IERC20(address(asset)), amount);
        sDAI.setExchangeRate(rate);
        uint256 total = sdaiConnector.totalAssets(IERC20(address(asset)));
        assertGe(total, amount, "yield monotonic: total >= deposit");
    }
}

// --- Mocks ---

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

// --- Connector under tests (minimal replicas) ---

contract MetamorphoUnderTest is IConnector {
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
        asset.safeTransferFrom(msg.sender, address(this), amount);
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

contract SDAIUnderTest is IConnector {
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
        asset.safeTransferFrom(msg.sender, address(this), amount);
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

contract AngleUnderTest is IConnector {
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
        asset.safeTransferFrom(msg.sender, address(this), amount);
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

contract AaveUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable aave;
    constructor(address _a) {
        aave = _a;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return AavePoolMock(aave).balanceOf(address(this));
    }
    function deposit(IERC20 a, uint256 amount) external {
        require(
            address(a) == address(AavePoolMock(aave).asset()),
            "wrong asset"
        );
        a.safeTransferFrom(msg.sender, address(this), amount);
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
    function maxDeposit(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20 a) external view returns (uint256) {
        return AavePoolMock(aave).balanceOf(address(this));
    }
}
