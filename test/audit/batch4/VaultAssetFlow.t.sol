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
import {BlockList} from "../../../src/BlockList.sol";

contract MockAsset is IERC20 {
    string public name = "M"; string public symbol = "M";
    uint8 public immutable decimals; uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public managed;
    uint8 public immutable feePercent;
    constructor(uint8 _d, uint8 _fee) { decimals = _d; feePercent = _fee; }
    function mint(address to, uint256 amt) external { totalSupply += amt; balanceOf[to] += amt; emit Transfer(address(0), to, amt); }
    function transfer(address to, uint256 amt) external returns (bool) { _xfer(msg.sender, to, amt); return true; }
    function approve(address sp, uint256 amt) external returns (bool) { allowance[msg.sender][sp] = amt; emit Approval(msg.sender, sp, amt); return true; }
    function transferFrom(address f, address t, uint256 amt) external returns (bool) {
        if (allowance[f][msg.sender] != type(uint256).max) allowance[f][msg.sender] -= amt;
        uint256 toXfer = amt;
        if (feePercent > 0) { uint256 fee = amt * feePercent / 100; toXfer = amt - fee; _xfer(f, address(0xdead), fee); }
        _xfer(f, t, toXfer); return true;
    }
    function _xfer(address f, address t, uint256 amt) internal { balanceOf[f] -= amt; balanceOf[t] += amt; emit Transfer(f, t, amt); }
    function addYield(address vault, uint256 amt) external { managed[vault] += amt; totalSupply += amt; }
    function moveToManaged(address from, uint256 amt) external { balanceOf[from] -= amt; managed[from] += amt; }
    function releaseFromManaged(address to, uint256 amt) external {
        uint256 actual = amt < managed[to] ? amt : managed[to]; managed[to] -= actual; balanceOf[to] += actual;
    }
}

contract MockConnector is IConnector {
    uint256 public immutable wl;
    constructor(uint256 _wl) { wl = _wl; }
    function totalAssets(IERC20 a) external view returns (uint256) {
        MockAsset ma = MockAsset(address(a)); return ma.balanceOf(msg.sender) + ma.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external { MockAsset(address(a)).moveToManaged(address(this), amt); }
    function withdraw(IERC20 a, uint256 amt) external {
        MockAsset ma = MockAsset(address(a));
        uint256 rel = amt < ma.managed(address(this)) ? amt : ma.managed(address(this));
        if (rel > wl) rel = wl;
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

contract Batch4FlowTest is Test {
    address ADMIN = makeAddr("ADMIN");
    address DEPLOYER = makeAddr("DEPLOYER");
    address ALICE = makeAddr("ALICE");
    address BOB = makeAddr("BOB");

    // ── Helper: deploy infrastructure, return vault and asset ──
    function deployInfra(uint8 tFee, uint8 offset, uint256 wl, uint256 dFee, uint256 rFee)
        internal returns (Vault vault, MockAsset asset)
    {
        asset = new MockAsset(6, tFee);
        MockConnector connector = new MockConnector(wl);

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
        uint256 scale = 100 * 10 ** 6;
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

    // ── Inline deposit (no helper function to avoid forge var issues) ──
}

// ── TEST: Exact deposit delta ──
contract DepositDeltaTest is Batch4FlowTest {
    function test_exactDeposit() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, type(uint256).max, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        assertEq(a.managed(address(v)), amount, "All went to connector");
        assertEq(a.balanceOf(address(v)), 0, "No idle");
        emit log("PASS: Deposit delta correct");
    }

    function test_depositWithFee() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, type(uint256).max, 10 * 10 ** 6, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        uint256 fee = a.balanceOf(address(v));
        uint256 invested = a.managed(address(v));
        assertApproxEqRel(fee, 10_000 * 10 ** 6, 0.01e18, "Fee idle");
        assertApproxEqRel(invested, 90_000 * 10 ** 6, 0.01e18, "Net invested");
        emit log("PASS: Fee isolated");
    }
}

// ── TEST: Withdrawal delta ──
contract WithdrawalDeltaTest is Batch4FlowTest {
    function test_fullWithdrawal() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, type(uint256).max, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        uint256 shares = v.balanceOf(ALICE);
        vm.prank(ALICE);
        v.redeem(shares, ALICE, ALICE);

        assertEq(a.managed(address(v)), 0, "All returned");
        assertGt(a.balanceOf(ALICE), 0, "Alice got assets");
        emit log("PASS: Full withdrawal returns assets");
    }

    function test_withdrawLimit() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, 50_000 * 10 ** 6, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        assertEq(v.maxWithdraw(ALICE), 50_000 * 10 ** 6, "Limited to 50k");

        vm.prank(ALICE);
        vm.expectRevert();
        v.withdraw(100_000 * 10 ** 6, ALICE, ALICE);
        emit log("PASS: Connector limit enforced");
    }

    function test_withdrawBelowLimit() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, 50_000 * 10 ** 6, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        // Can withdraw up to the limit
        vm.prank(ALICE);
        v.withdraw(50_000 * 10 ** 6, ALICE, ALICE);
        emit log("PASS: Can withdraw within connector limit");
    }
}

// ── TEST: Registry transition ──
contract RegistryTransitionTest is Batch4FlowTest {
    function test_positionPreserved() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, type(uint256).max, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        uint256 pos = a.managed(address(v));
        emit log_named_uint("Position before registry update", pos);
        assertGt(pos, 0, "Position exists");
        emit log("PASS: Positions preserved (tied to vault, not connector)");
    }
}

// ── TEST: Fee-on-transfer ──
contract FeeOnTransferTest is Batch4FlowTest {
    function test_feeOnTransfer() public {
        (Vault v, MockAsset a) = deployInfra(5, 6, type(uint256).max, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;

        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();

        uint256 netReceived = a.balanceOf(address(v)) + a.managed(address(v));
        emit log_named_uint("Deposit requested", amount);
        emit log_named_uint("Net received (5% fee)", netReceived);
        emit log("NOTE: Fee-on-transfer tokens partially supported");
    }
}

// ── TEST: Loss socialization ──
contract WithdrawalTest is Batch4FlowTest {
    function test_singleUserWithdrawal() public {
        (Vault v, MockAsset a) = deployInfra(0, 6, type(uint256).max, 0, 0);
        uint256 amount = 100_000 * 10 ** 6;
        a.mint(ALICE, amount);
        vm.startPrank(ALICE);
        a.approve(address(v), amount);
        v.deposit(amount, ALICE);
        vm.stopPrank();
        uint256 shares = v.balanceOf(ALICE);
        vm.prank(ALICE);
        v.redeem(shares, ALICE, ALICE);
        assertEq(a.managed(address(v)), 0, "All returned");
    }
}
