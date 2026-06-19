// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../../src/Vault.sol";
import {VaultFactory} from "../../../src/VaultFactory.sol";
import {
    VaultUpgradeableBeacon
} from "../../../src/proxy/VaultUpgradeableBeacon.sol";
import {ConnectorRegistry} from "../../../src/ConnectorRegistry.sol";
import {FeeDispatcher} from "../../../src/FeeDispatcher.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {IFeeDispatcher} from "../../../src/interfaces/IFeeDispatcher.sol";
import {SimpleProxy} from "../../../src/test-helpers/SimpleProxy.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {BlockList} from "../../../src/BlockList.sol";

contract MockAsset is IERC20 {
    string public name = "MA";
    string public symbol = "MA";
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public managed;
    constructor(uint8 _d) {
        decimals = _d;
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
    function addYield(address vault, uint256 amt) external {
        managed[vault] += amt;
        totalSupply += amt;
    }
    function moveToManaged(address from, uint256 amt) external {
        balanceOf[from] -= amt;
        managed[from] += amt;
    }
    function releaseFromManaged(address to, uint256 amt) external {
        uint256 actual = amt < managed[to] ? amt : managed[to];
        managed[to] -= actual;
        balanceOf[to] += actual;
    }
}

contract MockConnector is IConnector {
    uint256 public withdrawLimit = type(uint256).max;
    function setWithdrawLimit(uint256 limit) external {
        withdrawLimit = limit;
    }
    function totalAssets(IERC20 a) external view returns (uint256) {
        MockAsset ma = MockAsset(address(a));
        return ma.balanceOf(msg.sender) + ma.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        MockAsset(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        MockAsset ma = MockAsset(address(a));
        uint256 toRelease = amt < ma.managed(address(this))
            ? amt
            : ma.managed(address(this));
        ma.releaseFromManaged(address(this), toRelease);
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
        MockAsset ma = MockAsset(address(a));
        uint256 m = ma.managed(msg.sender);
        return m < withdrawLimit ? m : withdrawLimit;
    }
}

contract Batch3AccountingBase is Test {
    address ADMIN;
    address DEPLOYER;
    address ALICE;
    address BOB;
    uint8 constant D6 = 6;

    Vault vault;
    MockAsset asset;
    MockConnector connector;

    function setUp() public {
        ADMIN = makeAddr("ADMIN");
        DEPLOYER = makeAddr("DEPLOYER");
        ALICE = makeAddr("ALICE");
        BOB = makeAddr("BOB");
    }

    function _deployVault(
        uint8 offset,
        uint256 minSupply,
        uint256 dFee,
        uint256 rFee
    ) internal {
        asset = new MockAsset(D6);
        connector = new MockConnector();

        vm.startPrank(ADMIN);
        ConnectorRegistry reg = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        reg.add("MOCK", address(connector));
        FeeDispatcher fdImpl = new FeeDispatcher();
        FeeDispatcher fd = FeeDispatcher(
            address(
                new SimpleProxy(
                    address(fdImpl),
                    abi.encodeCall(FeeDispatcher.initialize, ())
                )
            )
        );
        ExternalAccessControl eacImpl = new ExternalAccessControl();
        ExternalAccessControl eac = ExternalAccessControl(
            address(new SimpleProxy(address(eacImpl), ""))
        );
        eac.initialize(
            ExternalAccessControl.InitializationParams({
                initialDefaultAdmin_: ADMIN,
                initialRole_: ExternalAccessControl.InitialRole({
                    role: bytes32("SPENDER"),
                    account: ADMIN
                }),
                initialDelay_: uint48(1 days)
            })
        );
        VaultFactory fi = new VaultFactory();
        VaultFactory f = VaultFactory(
            address(new SimpleProxy(address(fi), ""))
        );
        Vault vi = new Vault(address(eac), address(f));
        VaultUpgradeableBeacon bn = new VaultUpgradeableBeacon(
            address(vi),
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        f.initialize(
            VaultFactory.InitializationParams({
                initialAdmin_: ADMIN,
                initialDeployer_: DEPLOYER,
                initialDelay_: uint48(1 days),
                vaultBeacon_: address(bn),
                connectorRegistry_: address(reg),
                feeDispatcher_: address(fd)
            })
        );
        vm.stopPrank();

        IFeeDispatcher.FeeRecipient[]
            memory rec = new IFeeDispatcher.FeeRecipient[](1);
        uint256 scale = 100 * 10 ** D6;
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: ADMIN,
            depositFeeSplit: scale,
            rewardFeeSplit: scale
        });

        vm.prank(DEPLOYER);
        f.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(asset)),
                name_: "V",
                symbol_: "V",
                transferable_: true,
                connectorName_: "MOCK",
                recipients_: rec,
                depositFee_: dFee,
                rewardFee_: rFee,
                initialDefaultAdmin_: ADMIN,
                initialFeeManager_: ADMIN,
                initialFeeCollector_: ADMIN,
                initialSanctionsManager_: ADMIN,
                initialClaimManager_: ADMIN,
                initialPauser_: ADMIN,
                initialUnpauser_: ADMIN,
                initialDelay_: uint48(1 days),
                offset_: offset,
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: minSupply,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(uint160(address(this))))
        );
        vault = f.getDeployedVault(0);
    }

    function _deposit(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }
}

contract RoundTripTest is Batch3AccountingBase {
    function test_noProfit() public {
        _deployVault(6, 0, 0, 0);
        uint256 amt = 100_000 * 10 ** D6;
        _deposit(ALICE, amt);
        uint256 shares = vault.balanceOf(ALICE);
        vm.prank(ALICE);
        uint256 redeemed = vault.redeem(shares, ALICE, ALICE);
        assertLe(redeemed, amt, "No profit from round-trip");
    }
}

contract PreviewTest is Batch3AccountingBase {
    function test_previewDeposit() public {
        _deployVault(6, 0, 0, 0);
        _deposit(ALICE, 100_000 * 10 ** D6);
        uint256 amt = 10_000 * 10 ** D6;
        uint256 p = vault.previewDeposit(amt);
        asset.mint(BOB, amt);
        vm.startPrank(BOB);
        asset.approve(address(vault), amt);
        uint256 e = vault.deposit(amt, BOB);
        vm.stopPrank();
        assertEq(p, e, "previewDeposit matches");
    }
    function test_previewRedeem() public {
        _deployVault(6, 0, 0, 0);
        _deposit(ALICE, 100_000 * 10 ** D6);
        uint256 s = vault.balanceOf(ALICE) / 2;
        uint256 p = vault.previewRedeem(s);
        vm.prank(ALICE);
        uint256 e = vault.redeem(s, ALICE, ALICE);
        assertEq(p, e, "previewRedeem matches");
    }
}

contract FeeTest is Batch3AccountingBase {
    function test_depositFee() public {
        _deployVault(6, 0, 10 * 10 ** D6, 0);
        _deposit(ALICE, 100_000 * 10 ** D6);
        uint256 shares = vault.balanceOf(ALICE);
        uint256 expectedFee = (100_000 * 10 ** D6 * 10) / 100;
        emit log_named_uint("Deposit fee", expectedFee);
        emit log_named_uint("Shares minted", shares);
        emit log("Deposit fee reduces shares, not redemption value");
        assertApproxEqRel(vault.pendingDepositFee(), expectedFee, 0.01e18, "Fee captured as pending");
    }
    function test_rewardFee() public {
        _deployVault(6, 0, 0, 10 * 10 ** D6);
        _deposit(ALICE, 100_000 * 10 ** D6);
        asset.addYield(address(vault), 10_000 * 10 ** D6);
        _deposit(BOB, 1_000 * 10 ** D6);
        assertGt(vault.balanceOf(address(vault)), 0, "Reward shares minted");
    }
}

contract MultiUserTest is Batch3AccountingBase {
    function test_proportionalYield() public {
        _deployVault(6, 0, 0, 0);
        _deposit(ALICE, 100_000 * 10 ** D6);
        _deposit(BOB, 200_000 * 10 ** D6);
        uint256 aS = vault.balanceOf(ALICE);
        uint256 bS = vault.balanceOf(BOB);
        asset.addYield(address(vault), 30_000 * 10 ** D6);
        vm.prank(ALICE);
        uint256 aG = vault.redeem(aS, ALICE, ALICE);
        vm.prank(BOB);
        uint256 bG = vault.redeem(bS, BOB, BOB);
        assertApproxEqRel(aG, 110_000 * 10 ** D6, 0.02e18, "Alice yield");
        assertApproxEqRel(bG, 220_000 * 10 ** D6, 0.02e18, "Bob yield");
    }
}
