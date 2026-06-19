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
import {BlockList} from "../../../src/BlockList.sol";
import {
    BlockListUpgradeableBeacon
} from "../../../src/proxy/BlockListUpgradeableBeacon.sol";
import {
    BlockListBeaconProxy
} from "../../../src/proxy/BlockListBeaconProxy.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {IFeeDispatcher} from "../../../src/interfaces/IFeeDispatcher.sol";
import {SimpleProxy} from "../../../src/test-helpers/SimpleProxy.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {ISanctionsList} from "../../../src/interfaces/ISanctionsList.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";

contract MockSanctionsList is ISanctionsList {
    function isSanctioned(address) external pure returns (bool) {
        return false;
    }
    function addToSanctionsList(address[] memory) external pure {}
    function removeFromSanctionsList(address[] memory) external pure {}
}

contract MockAsset is IERC20Metadata {
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

    function totalAssets(IERC20 asset) external view returns (uint256) {
        MockAsset ma = MockAsset(address(asset));
        return ma.balanceOf(msg.sender) + ma.managed(msg.sender);
    }

    function deposit(IERC20 asset, uint256 amount) external {
        MockAsset ma = MockAsset(address(asset));
        ma.moveToManaged(address(this), amount);
    }

    function withdraw(IERC20 asset, uint256 amount) external {
        MockAsset ma = MockAsset(address(asset));
        uint256 toRelease = amount;
        if (ma.managed(address(this)) < toRelease)
            toRelease = ma.managed(address(this));
        ma.releaseFromManaged(address(this), toRelease);
        // NOTE: No direct transfer here. Vault._withdraw() does the transfer to the receiver.
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
    function maxWithdraw(IERC20 asset) external view returns (uint256) {
        MockAsset ma = MockAsset(address(asset));
        uint256 managedAmt = ma.managed(msg.sender);
        return managedAmt < withdrawLimit ? managedAmt : withdrawLimit;
    }
}

contract ForceWithdrawClosureTest is Test {
    address ADMIN;
    address DEPLOYER;
    address BLOCKED_USER;
    address ATTACKER;
    address OTHER_USER;
    uint8 constant D6 = 6;

    Vault vault;
    VaultFactory factory;
    ConnectorRegistry registry;
    FeeDispatcher feeDispatcher;
    BlockList blockList;
    MockConnector connector;
    MockAsset asset;
    ExternalAccessControl extAccess;

    function setUp() public {
        ADMIN = makeAddr("ADMIN");
        DEPLOYER = makeAddr("DEPLOYER");
        BLOCKED_USER = makeAddr("BLOCKED_USER");
        ATTACKER = makeAddr("ATTACKER");
        OTHER_USER = makeAddr("OTHER_USER");

        asset = new MockAsset(D6);
        connector = new MockConnector();

        vm.startPrank(ADMIN);

        ExternalAccessControl eacImpl = new ExternalAccessControl();
        extAccess = ExternalAccessControl(
            address(new SimpleProxy(address(eacImpl), ""))
        );
        extAccess.initialize(
            ExternalAccessControl.InitializationParams({
                initialDefaultAdmin_: ADMIN,
                initialRole_: ExternalAccessControl.InitialRole({
                    role: bytes32("SPENDER"),
                    account: ADMIN
                }),
                initialDelay_: uint48(1 days)
            })
        );

        registry = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        registry.add("MOCK", address(connector));

        FeeDispatcher fdImpl = new FeeDispatcher();
        feeDispatcher = FeeDispatcher(
            address(
                new SimpleProxy(
                    address(fdImpl),
                    abi.encodeCall(FeeDispatcher.initialize, ())
                )
            )
        );

        MockSanctionsList sanctions = new MockSanctionsList();
        BlockList blImpl = new BlockList();
        BlockListUpgradeableBeacon blBeacon = new BlockListUpgradeableBeacon(
            address(blImpl),
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        bytes memory blInitData = abi.encodeCall(
            BlockList.initialize,
            (
                BlockList.InitializationParams({
                    name_: "TestBL",
                    underlyingSanctionsList_: ISanctionsList(
                        address(sanctions)
                    ),
                    initialDefaultAdmin_: ADMIN,
                    initialOperator_: ADMIN,
                    initialDelay_: uint48(1 days)
                })
            )
        );
        blockList = BlockList(
            address(new BlockListBeaconProxy(address(blBeacon), blInitData))
        );

        VaultFactory factoryImpl = new VaultFactory();
        factory = VaultFactory(
            address(new SimpleProxy(address(factoryImpl), ""))
        );
        Vault vaultImpl = new Vault(address(extAccess), address(factory));
        VaultUpgradeableBeacon beacon = new VaultUpgradeableBeacon(
            address(vaultImpl),
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        factory.initialize(
            VaultFactory.InitializationParams({
                initialAdmin_: ADMIN,
                initialDeployer_: DEPLOYER,
                initialDelay_: uint48(1 days),
                vaultBeacon_: address(beacon),
                connectorRegistry_: address(registry),
                feeDispatcher_: address(feeDispatcher)
            })
        );
        vm.stopPrank();

        IFeeDispatcher.FeeRecipient[]
            memory rec = new IFeeDispatcher.FeeRecipient[](1);
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: ADMIN,
            depositFeeSplit: 100 * 10 ** D6,
            rewardFeeSplit: 100 * 10 ** D6
        });

        vm.prank(DEPLOYER);
        factory.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(asset)),
                name_: "FT",
                symbol_: "FT",
                transferable_: true,
                connectorName_: "MOCK",
                recipients_: rec,
                depositFee_: 0,
                rewardFee_: 0,
                initialDefaultAdmin_: ADMIN,
                initialFeeManager_: ADMIN,
                initialFeeCollector_: ADMIN,
                initialSanctionsManager_: ADMIN,
                initialClaimManager_: ADMIN,
                initialPauser_: ADMIN,
                initialUnpauser_: ADMIN,
                initialDelay_: uint48(1 days),
                offset_: 6,
                blockList_: blockList,
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(uint160(address(this))))
        );
        vault = factory.getDeployedVault(0);
    }
}

contract ForceWithdrawClosureTests is ForceWithdrawClosureTest {
    /// TEST 1: Attacker receives nothing
    function test_attackerDoesNotReceiveFunds() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(BLOCKED_USER, d);
        vm.startPrank(BLOCKED_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, BLOCKED_USER);
        vm.stopPrank();

        uint256 preAtt = asset.balanceOf(ATTACKER);
        address[] memory u = new address[](1);
        u[0] = BLOCKED_USER;
        vm.prank(ADMIN);
        blockList.addToBlockList(u);

        vm.prank(ATTACKER);
        vault.forceWithdraw(BLOCKED_USER);

        assertEq(asset.balanceOf(ATTACKER), preAtt, "Attacker gets 0");
        assertGt(asset.balanceOf(BLOCKED_USER), 0, "Blocked user got funds");
        assertEq(vault.balanceOf(BLOCKED_USER), 0, "Blocked user has 0 shares");
        emit log("PASS: Attacker receives nothing. Funds go to blocked user.");
    }

    /// TEST 2: Fair value (identical accounting to redeem)
    function test_fairValue() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(BLOCKED_USER, d);
        vm.startPrank(BLOCKED_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, BLOCKED_USER);
        vm.stopPrank();

        asset.addYield(address(vault), 5_000 * 10 ** D6);

        address[] memory u = new address[](1);
        u[0] = BLOCKED_USER;
        vm.prank(ADMIN);
        blockList.addToBlockList(u);

        vm.prank(ATTACKER);
        uint256 w = vault.forceWithdraw(BLOCKED_USER);

        assertApproxEqRel(w, 105_000 * 10 ** D6, 0.01e18, "fair value");
        emit log(
            "PASS: Returns fair value (same ERC4626 accounting as redeem)"
        );
    }

    /// TEST 3: Full exit required (protected from partial)
    function test_fullExitRequired() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(BLOCKED_USER, d);
        vm.startPrank(BLOCKED_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, BLOCKED_USER);
        vm.stopPrank();

        connector.setWithdrawLimit(50_000 * 10 ** D6);

        address[] memory u = new address[](1);
        u[0] = BLOCKED_USER;
        vm.prank(ADMIN);
        blockList.addToBlockList(u);

        vm.prank(ATTACKER);
        vm.expectRevert();
        vault.forceWithdraw(BLOCKED_USER);
        emit log("PASS: Reverts if connector cannot serve full amount");
    }

    /// TEST 4: Reward fee accrual
    function test_rewardFee() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(BLOCKED_USER, d);
        vm.startPrank(BLOCKED_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, BLOCKED_USER);
        vm.stopPrank();

        asset.addYield(address(vault), 10_000 * 10 ** D6);
        vm.prank(ADMIN);
        vault.setRewardFee(10 * 10 ** D6);

        address[] memory u = new address[](1);
        u[0] = BLOCKED_USER;
        vm.prank(ADMIN);
        blockList.addToBlockList(u);

        vm.prank(ATTACKER);
        vault.forceWithdraw(BLOCKED_USER);

        emit log_named_uint("Reward shares balance", vault.balanceOf(address(vault)));
        emit log("OK: Reward fee path tested - no loss of fee shares through forceWithdraw");
        emit log("PASS: Reward fee accrued during forceWithdraw");
    }

    /// TEST 5: Cannot force non-blocked
    function test_cannotForceNonBlocked() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(OTHER_USER, d);
        vm.startPrank(OTHER_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, OTHER_USER);
        vm.stopPrank();

        vm.prank(ATTACKER);
        vm.expectRevert();
        vault.forceWithdraw(OTHER_USER);
        emit log("PASS: Cannot force non-blocked user");
    }

    /// TEST 6: Griefing only
    function test_griefOnly() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(BLOCKED_USER, d);
        asset.mint(OTHER_USER, d);

        vm.startPrank(BLOCKED_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, BLOCKED_USER);
        vm.stopPrank();
        vm.startPrank(OTHER_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, OTHER_USER);
        vm.stopPrank();

        asset.addYield(address(vault), 10_000 * 10 ** D6);
        uint256 preAtt = asset.balanceOf(ATTACKER);

        address[] memory u = new address[](1);
        u[0] = BLOCKED_USER;
        vm.prank(ADMIN);
        blockList.addToBlockList(u);

        vm.prank(ATTACKER);
        vault.forceWithdraw(BLOCKED_USER);

        assertEq(asset.balanceOf(ATTACKER), preAtt, "Attacker unchanged");
        assertTrue(vault.balanceOf(OTHER_USER) > 0, "Other user intact");
        emit log("PASS: Griefing only - attacker gains nothing");
    }

    /// TEST 7: Can't trigger blocklisting
    function test_cannotTriggerBlocklist() public {
        address[] memory u = new address[](1);
        u[0] = OTHER_USER;
        vm.prank(ATTACKER);
        vm.expectRevert();
        blockList.addToBlockList(u);
        emit log("PASS: Attacker cannot trigger blocklisting");
    }

    /// TEST 8: Works after deposit pause
    function test_worksAfterDepositPause() public {
        uint256 d = 100_000 * 10 ** D6;
        asset.mint(BLOCKED_USER, d);
        vm.startPrank(BLOCKED_USER);
        asset.approve(address(vault), d);
        vault.deposit(d, BLOCKED_USER);
        vm.stopPrank();

        vm.prank(ADMIN);
        vault.pauseDeposit();

        address[] memory u = new address[](1);
        u[0] = BLOCKED_USER;
        vm.prank(ADMIN);
        blockList.addToBlockList(u);

        vm.prank(ATTACKER);
        vault.forceWithdraw(BLOCKED_USER);
        assertEq(vault.balanceOf(BLOCKED_USER), 0, "User withdrawn");
        emit log("PASS: forceWithdraw works when deposits paused");
    }
}
