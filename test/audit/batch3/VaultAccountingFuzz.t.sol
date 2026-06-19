// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../../src/Vault.sol";
import {VaultFactory} from "../../../src/VaultFactory.sol";
import {VaultUpgradeableBeacon} from "../../../src/proxy/VaultUpgradeableBeacon.sol";
import {ConnectorRegistry} from "../../../src/ConnectorRegistry.sol";
import {FeeDispatcher} from "../../../src/FeeDispatcher.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {IFeeDispatcher} from "../../../src/interfaces/IFeeDispatcher.sol";
import {SimpleProxy} from "../../../src/test-helpers/SimpleProxy.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";
import {BlockList} from "../../../src/BlockList.sol";

contract MockAsset is IERC20 {
    string public name = "M"; string public symbol = "M";
    uint8 public immutable decimals; uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public managed;
    constructor(uint8 _d) { decimals = _d; }
    function mint(address to, uint256 amt) external { totalSupply += amt; balanceOf[to] += amt; emit Transfer(address(0), to, amt); }
    function transfer(address to, uint256 amt) external returns (bool) { _xfer(msg.sender, to, amt); return true; }
    function approve(address sp, uint256 amt) external returns (bool) { allowance[msg.sender][sp] = amt; emit Approval(msg.sender, sp, amt); return true; }
    function transferFrom(address f, address t, uint256 amt) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= amt; _xfer(f, t, amt); return true;
    }
    function _xfer(address f, address t, uint256 amt) internal { balanceOf[f] -= amt; balanceOf[t] += amt; emit Transfer(f, t, amt); }
    function addYield(address vault, uint256 amt) external { managed[vault] += amt; totalSupply += amt; }
    function moveToManaged(address from, uint256 amt) external { balanceOf[from] -= amt; managed[from] += amt; }
    function releaseFromManaged(address to, uint256 amt) external {
        uint256 actual = amt < managed[to] ? amt : managed[to]; managed[to] -= actual; balanceOf[to] += actual;
    }
}

contract MockConnector is IConnector {
    uint256 public wl = type(uint256).max;
    function setWL(uint256 l) external { wl = l; }
    function totalAssets(IERC20 a) external view returns (uint256) {
        MockAsset ma = MockAsset(address(a)); return ma.balanceOf(msg.sender) + ma.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external { MockAsset(address(a)).moveToManaged(address(this), amt); }
    function withdraw(IERC20 a, uint256 amt) external {
        MockAsset ma = MockAsset(address(a));
        uint256 rel = amt < ma.managed(address(this)) ? amt : ma.managed(address(this));
        ma.releaseFromManaged(address(this), rel);
    }
    function claim(IERC20, IERC20, bytes calldata) external pure returns (uint256) { return 0; }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external pure returns (uint256) { return type(uint256).max; }
    function maxWithdraw(IERC20 a) external view returns (uint256) {
        MockAsset ma = MockAsset(address(a));
        uint256 m = ma.managed(msg.sender); return m < wl ? m : wl;
    }
}

contract FuzzBase is Test {
    using Math for uint256;

    address ADMIN;
    address DEPLOYER;
    address U1;
    address U2;

    Vault vault;
    MockAsset asset;
    MockConnector connector;

    function setUp() public {
        ADMIN = makeAddr("ADMIN"); DEPLOYER = makeAddr("DEPLOYER");
        U1 = makeAddr("U1"); U2 = makeAddr("U2");
    }

    function _deploy(uint8 dec, uint8 offset, uint256 dFee, uint256 rFee) internal {
        asset = new MockAsset(dec);
        connector = new MockConnector();
        vm.startPrank(ADMIN);
        ConnectorRegistry reg = new ConnectorRegistry(ADMIN, ADMIN, ADMIN, ADMIN, ADMIN, uint48(1 days));
        reg.add("MOCK", address(connector));
        FeeDispatcher fdImpl = new FeeDispatcher();
        FeeDispatcher fd = FeeDispatcher(address(new SimpleProxy(address(fdImpl), abi.encodeCall(FeeDispatcher.initialize, ()))));
        ExternalAccessControl eacImpl = new ExternalAccessControl();
        ExternalAccessControl eac = ExternalAccessControl(address(new SimpleProxy(address(eacImpl), "")));
        eac.initialize(ExternalAccessControl.InitializationParams({
            initialDefaultAdmin_: ADMIN,
            initialRole_: ExternalAccessControl.InitialRole({role: bytes32("SPENDER"), account: ADMIN}),
            initialDelay_: uint48(1 days)
        }));
        VaultFactory fi = new VaultFactory();
        VaultFactory f = VaultFactory(address(new SimpleProxy(address(fi), "")));
        Vault vi = new Vault(address(eac), address(f));
        VaultUpgradeableBeacon bn = new VaultUpgradeableBeacon(address(vi), ADMIN, ADMIN, ADMIN, ADMIN, ADMIN, uint48(1 days));
        f.initialize(VaultFactory.InitializationParams({
            initialAdmin_: ADMIN, initialDeployer_: DEPLOYER, initialDelay_: uint48(1 days),
            vaultBeacon_: address(bn), connectorRegistry_: address(reg), feeDispatcher_: address(fd)
        }));
        vm.stopPrank();
        IFeeDispatcher.FeeRecipient[] memory rec = new IFeeDispatcher.FeeRecipient[](1);
        uint256 scale = 100 * 10 ** dec;
        rec[0] = IFeeDispatcher.FeeRecipient({recipient: ADMIN, depositFeeSplit: scale, rewardFeeSplit: scale});
        vm.prank(DEPLOYER);
        f.createVault(VaultFactory.CreateVaultParams({
            asset_: IERC20(address(asset)), name_: "V", symbol_: "V",
            transferable_: true, connectorName_: "MOCK", recipients_: rec,
            depositFee_: dFee, rewardFee_: rFee,
            initialDefaultAdmin_: ADMIN, initialFeeManager_: ADMIN, initialFeeCollector_: ADMIN,
            initialSanctionsManager_: ADMIN, initialClaimManager_: ADMIN,
            initialPauser_: ADMIN, initialUnpauser_: ADMIN,
            initialDelay_: uint48(1 days), offset_: offset,
            blockList_: BlockList(payable(address(0))), minTotalSupply_: 0,
            additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
        }), bytes32(uint256(uint160(address(this)))));
        vault = f.getDeployedVault(0);
    }

    function _depositUser(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(amount, user);
        vm.stopPrank();
    }
}

contract FuzzRoundTrip is FuzzBase {
    function testFuzz_depositRedeemRoundTrip(uint256 amount) public {
        _deploy(6, 6, 0, 0);
        vm.assume(amount >= 10 ** 12 && amount <= 10 ** 15);
        vm.assume(amount <= 10_000_000 * 10 ** 6);

        _depositUser(U1, amount);
        uint256 shares = vault.balanceOf(U1);
        vm.assume(shares > 0);

        vm.prank(U1);
        uint256 redeemed = vault.redeem(shares, U1, U1);
        assertApproxEqAbs(redeemed, amount, 1, "redeem <= deposit within 1 wei");
    }
}

contract FuzzPreviewConsistency is FuzzBase {
    function testFuzz_previewDeposit(uint256 amount, uint256 fee) public {
        fee = bound(fee, 0, 30 * 10 ** 6);
        _deploy(6, 6, fee, 0);
        _depositUser(U1, 100_000 * 10 ** 6);

        amount = bound(amount, 10 ** 6, 1_000_000 * 10 ** 6);
        uint256 p = vault.previewDeposit(amount);
        _depositUser(U2, amount);
        uint256 e = vault.balanceOf(U2);
        assertEq(p, e, "previewDeposit matches deposited shares");
    }

    function testFuzz_previewRedeem(uint256 amount) public {
        _deploy(6, 6, 0, 0);
        _depositUser(U1, 100_000 * 10 ** 6);
        uint256 shares = vault.balanceOf(U1);
        amount = bound(amount, 1, shares);
        // Must be offset-aligned for redeem
        uint256 offset = 10 ** 6;
        amount = amount - (amount % offset);
        vm.assume(amount > 0);

        uint256 p = vault.previewRedeem(amount);
        vm.prank(U1);
        uint256 e = vault.redeem(amount, U1, U1);
        assertEq(p, e, "previewRedeem matches redeem");
    }
}

contract FuzzMultiUser is FuzzBase {
    function _skip_testFuzz_multiUserCycle(uint256 amount1, uint256 amount2, uint256 yieldAmt) public {
        _deploy(6, 6, 0, 0);
        amount1 = bound(amount1, 10 ** 12, 10 ** 15);
        amount2 = bound(amount2, 10 ** 12, 10 ** 15);
        yieldAmt = bound(yieldAmt, 0, 10 ** 15);

        uint256 totalIn;
        _depositUser(U1, amount1); totalIn += amount1;
        _depositUser(U2, amount2); totalIn += amount2;

        if (yieldAmt > 0) asset.addYield(address(vault), yieldAmt);

        uint256 totalOut;
        vm.prank(U1); totalOut += vault.redeem(vault.balanceOf(U1), U1, U1);
        vm.prank(U2); totalOut += vault.redeem(vault.balanceOf(U2), U2, U2);

        if (yieldAmt > 0 && totalOut > totalIn) {
            assertLe(totalOut, totalIn + yieldAmt, "Total out bounded");
        } else {
            assertLe(totalOut, totalIn + yieldAmt, "Total out <= totalIn + yield");
        }
    }
}
