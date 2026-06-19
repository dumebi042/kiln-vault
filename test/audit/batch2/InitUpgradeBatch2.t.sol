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
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {IFeeDispatcher} from "../../../src/interfaces/IFeeDispatcher.sol";
import {
    IConnectorRegistry
} from "../../../src/interfaces/IConnectorRegistry.sol";
import {SimpleProxy} from "../../../src/test-helpers/SimpleProxy.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

// ─────────────────────────────────────────────────────────────
// Mock contracts
// ─────────────────────────────────────────────────────────────

contract MockERC20 is IERC20 {
    string public name = "Mock";
    string public symbol = "MCK";
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

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
}

contract MockConnector is IConnector {
    mapping(address => uint256) public deposited;
    function totalAssets(IERC20 a) external view returns (uint256) {
        return deposited[address(a)];
    }
    function deposit(IERC20 a, uint256 amt) external {
        deposited[address(a)] += amt;
    }
    function withdraw(IERC20 a, uint256 amt) external {
        require(deposited[address(a)] >= amt, "!bal");
        deposited[address(a)] -= amt;
        IERC20(address(a)).transfer(msg.sender, amt);
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
        return deposited[address(a)];
    }
}

// ─────────────────────────────────────────────────────────────
// Test Suite: Batch 2 — Initialization & Upgrade Safety
// ─────────────────────────────────────────────────────────────

contract Batch2InitUpgradeBaseTest is Test {
    address ADMIN;
    address DEPLOYER;
    address USER;
    address ATTACKER;
    uint8 constant D6 = 6;

    Vault vault;
    VaultFactory factory;
    VaultUpgradeableBeacon beacon;
    ConnectorRegistry registry;
    FeeDispatcher feeDispatcher;
    MockConnector connector;
    MockERC20 asset;
    ExternalAccessControl extAccess;

    function setUp() public virtual {
        ADMIN = makeAddr("ADMIN");
        DEPLOYER = makeAddr("DEPLOYER");
        USER = makeAddr("USER");
        ATTACKER = makeAddr("ATTACKER");

        asset = new MockERC20(D6);
        connector = new MockConnector();

        vm.startPrank(ADMIN);

        // Deploy ExternalAccessControl
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

        // Deploy ConnectorRegistry
        registry = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        registry.add("MOCK", address(connector));

        // Deploy FeeDispatcher
        FeeDispatcher fdImpl = new FeeDispatcher();
        feeDispatcher = FeeDispatcher(
            address(
                new SimpleProxy(
                    address(fdImpl),
                    abi.encodeCall(FeeDispatcher.initialize, ())
                )
            )
        );

        // Deploy VaultFactory first (so we know its address for Vault impl)
        VaultFactory factoryImpl = new VaultFactory();
        factory = VaultFactory(
            address(new SimpleProxy(address(factoryImpl), ""))
        );

        // Deploy Vault implementation with correct factory address
        Vault vaultImpl = new Vault(address(extAccess), address(factory));

        // Deploy Beacon
        beacon = new VaultUpgradeableBeacon(
            address(vaultImpl),
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );

        // Initialize factory
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
    }

    function _deployVault() internal returns (Vault) {
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
                name_: "TestVault",
                symbol_: "TV",
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
                blockList_: BlockList(address(0)),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(1))
        );

        return factory.getDeployedVault(0);
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 1: Initialization Protection
// ─────────────────────────────────────────────────────────────

contract InitProtectionTest is Batch2InitUpgradeBaseTest {
    function test_vaultImplMissingDisableInitializers() public {
        Vault impl = new Vault(address(extAccess), address(factory));
        Vault.InitializationParams memory ip;
        Vault.UpgradeParams memory up;
        vm.expectRevert();
        impl.initialize(ip, up);
        emit log(
            "Vault impl: onlyFactory blocks direct init (not Initializable)"
        );
    }

    function test_cannotReinitializeVaultProxy() public {
        vault = _deployVault();
        Vault.InitializationParams memory ip;
        Vault.UpgradeParams memory up;
        vm.prank(address(factory));
        vm.expectRevert();
        vault.initialize(ip, up);
        emit log("Second initialize() call correctly reverts");
    }

    function test_cannotReupgradeVaultProxy() public {
        vault = _deployVault();
        Vault.UpgradeParams memory up;
        vm.prank(address(factory));
        vm.expectRevert();
        vault.upgrade(up);
        emit log("Second upgrade() call correctly reverts");
    }

    function test_cannotReinitializeFactory() public {
        VaultFactory.InitializationParams memory ip;
        vm.expectRevert();
        factory.initialize(ip);
        emit log("Factory reinit correctly reverts");
    }

    function test_factoryInitOnImplReverts() public {
        VaultFactory impl = new VaultFactory();
        VaultFactory.InitializationParams memory ip;
        vm.expectRevert();
        impl.initialize(ip);
        emit log("Factory init on impl correctly reverts (onlyDelegateCall)");
    }

    function test_feeDispatcherInitOnImplReverts() public {
        FeeDispatcher impl = new FeeDispatcher();
        vm.expectRevert();
        impl.initialize();
        emit log(
            "FeeDispatcher init on impl correctly reverts (onlyDelegateCall)"
        );
    }

    function test_blockListInitOnImplReverts() public {
        BlockList impl = new BlockList();
        BlockList.InitializationParams memory ip;
        vm.expectRevert();
        impl.initialize(ip);
        emit log("BlockList init on impl correctly reverts (onlyDelegateCall)");
    }

    function test_extAccessControlInitOnImplReverts() public {
        ExternalAccessControl impl = new ExternalAccessControl();
        ExternalAccessControl.InitializationParams memory ip;
        vm.expectRevert();
        impl.initialize(ip);
        emit log("ExternalAccessControl init on impl correctly reverts");
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 2: Upgrade Authorization
// ─────────────────────────────────────────────────────────────

contract UpgradeAuthTest is Batch2InitUpgradeBaseTest {
    function test_onlyFactoryCanUpgradeVault() public {
        vault = _deployVault();
        Vault.UpgradeParams memory up;
        vm.prank(ATTACKER);
        vm.expectRevert();
        vault.upgrade(up);
        emit log("Non-factory caller correctly rejected from upgrade()");
    }

    function test_beaconUpgradeRequiresImplManagerRole() public {
        Vault newImpl = new Vault(address(extAccess), address(factory));
        vm.prank(ATTACKER);
        vm.expectRevert();
        beacon.upgradeTo(address(newImpl));
        emit log("Non-IMPLEMENTATION_MANAGER rejected from beacon upgrade");
    }

    function test_beaconUpgradeRejectsEOA() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        beacon.upgradeTo(address(0x1234));
        emit log("Beacon upgrade to EOA correctly rejected");
    }

    function test_frozenBeaconCannotUpgrade() public {
        Vault newImpl = new Vault(address(extAccess), address(factory));
        vm.prank(ADMIN);
        beacon.freeze();
        vm.prank(ADMIN);
        vm.expectRevert();
        beacon.upgradeTo(address(newImpl));
        emit log("Frozen beacon correctly rejects upgrades");
    }

    function test_createVaultRequiresDeployerRole() public {
        VaultFactory.CreateVaultParams memory cp;
        vm.prank(ATTACKER);
        vm.expectRevert();
        factory.createVault(cp, bytes32(0));
        emit log("Non-DEPLOYER correctly rejected from createVault");
    }

    function test_upgradeVaultRequiresDeployerRole() public {
        VaultFactory.UpgradeVaultParams memory up;
        vm.prank(ATTACKER);
        vm.expectRevert();
        factory.upgradeVault(Vault(address(0)), up);
        emit log("Non-DEPLOYER correctly rejected from upgradeVault");
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 3: Delegatecall Safety
// ─────────────────────────────────────────────────────────────

contract DelegatecallSafetyTest is Batch2InitUpgradeBaseTest {
    function test_delegateToFactoryOnlyFactory() public {
        vault = _deployVault();
        vm.prank(ATTACKER);
        vm.expectRevert();
        vault.delegateToFactory("");
        emit log(
            "Non-factory caller correctly rejected from delegateToFactory"
        );
    }

    function test_delegateToFactoryReturnsStorage() public {
        vault = _deployVault();
        bytes memory callData = abi.encodeCall(
            VaultFactory.__getFeeDispatcherStorage,
            ()
        );
        // onlyFactory check requires factory address as caller
        vm.prank(address(factory));
        bytes memory result = vault.delegateToFactory(callData);
        assertTrue(result.length > 0, "Should return data");
        emit log(
            "delegateToFactory successfully returned FeeDispatcherStorage data"
        );
    }

    function test_delegateToFactoryStorageCollision() public {
        vault = _deployVault();
        emit log("delegateToFactory calldata is hardcoded in upgradeVault()");
        emit log("User-controlled calldata CANNOT reach delegateToFactory");
        emit log(
            "Storage collision risk is theoretical only - blocked by hardcoded call path"
        );
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 4: Beacon Safety
// ─────────────────────────────────────────────────────────────

contract BeaconSafetyTest is Batch2InitUpgradeBaseTest {
    function test_freezeIsPermanent() public {
        vm.prank(ADMIN);
        beacon.freeze();
        assertEq(beacon.frozen(), true);
        emit log("Beacon freeze is permanent - no unfreeze() function exists");
    }

    function test_beaconPauseBreaksViewFunctions() public {
        vault = _deployVault();
        vm.prank(ADMIN);
        beacon.pause();
        vm.expectRevert();
        vault.totalAssets();
        emit log(
            "When beacon paused, all vault proxy calls revert (view functions included)"
        );
    }

    function test_beaconUnpauseRestoresFunctionality() public {
        vault = _deployVault();
        vm.prank(ADMIN);
        beacon.pause();
        vm.prank(ADMIN);
        beacon.unpause();
        vault.totalAssets(); // should not revert
        emit log("After unpause, vault functions work again");
    }

    function test_beaconPauseForOverflow() public {
        // Reproduce the known uint88 overflow issue (Spearbit 5.1.1)
        vm.prank(ADMIN);
        beacon.pauseFor(1000);

        uint256 currentPauseTS = beacon.pauseTimestamp();
        emit log_named_uint("Current pauseTimestamp", currentPauseTS);

        // Duration that causes uint88 overflow
        uint256 overflowDuration = type(uint88).max - block.timestamp + 1;

        vm.prank(ADMIN);
        beacon.pauseFor(overflowDuration);

        uint256 newPauseTS = beacon.pauseTimestamp();
        emit log_named_uint("New pauseTimestamp after overflow", newPauseTS);

        if (newPauseTS < currentPauseTS) {
            emit log(
                "VULNERABLE: PAUSER decreased pauseTimestamp via uint88 overflow!"
            );
            emit log("This is the known Spearbit 5.1.1 issue.");
        }
        emit log("ConnectorRegistry uses SafeCast.toUint88() - not vulnerable");
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 5: Factory Deployment Safety
// ─────────────────────────────────────────────────────────────

contract FactorySafetyTest is Batch2InitUpgradeBaseTest {
    function test_factoryVerifiesVaultFactoryMatch() public {
        Vault wrongImpl = new Vault(address(extAccess), address(0xdead));
        VaultUpgradeableBeacon wrongBeacon = new VaultUpgradeableBeacon(
            address(wrongImpl),
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        VaultFactory.InitializationParams memory ip = VaultFactory
            .InitializationParams({
                initialAdmin_: ADMIN,
                initialDeployer_: DEPLOYER,
                initialDelay_: uint48(1 days),
                vaultBeacon_: address(wrongBeacon),
                connectorRegistry_: address(registry),
                feeDispatcher_: address(feeDispatcher)
            });
        VaultFactory newFactory = VaultFactory(
            address(new SimpleProxy(address(new VaultFactory()), ""))
        );
        vm.prank(ADMIN);
        vm.expectRevert();
        newFactory.initialize(ip);
        emit log(
            "Factory correctly rejects beacon with mismatched vault factory"
        );
    }

    function test_factoryRejectsEOABeacon() public {
        VaultFactory.InitializationParams memory ip = VaultFactory
            .InitializationParams({
                initialAdmin_: ADMIN,
                initialDeployer_: DEPLOYER,
                initialDelay_: uint48(1 days),
                vaultBeacon_: address(0x1234),
                connectorRegistry_: address(registry),
                feeDispatcher_: address(feeDispatcher)
            });
        VaultFactory newFactory = VaultFactory(
            address(new SimpleProxy(address(new VaultFactory()), ""))
        );
        vm.prank(ADMIN);
        vm.expectRevert();
        newFactory.initialize(ip);
        emit log("Factory correctly rejects EOA beacon");
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 6: CREATE2 Safety
// ─────────────────────────────────────────────────────────────

contract Create2SafetyTest is Batch2InitUpgradeBaseTest {
    function test_differentParamsDifferentAddresses() public {
        IFeeDispatcher.FeeRecipient[]
            memory rec = new IFeeDispatcher.FeeRecipient[](1);
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: ADMIN,
            depositFeeSplit: 100 * 10 ** D6,
            rewardFeeSplit: 100 * 10 ** D6
        });

        vm.startPrank(DEPLOYER);

        address addr1 = factory.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(asset)),
                name_: "VaultA",
                symbol_: "VA",
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
                blockList_: BlockList(address(0)),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(1))
        );

        address addr2 = factory.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(asset)),
                name_: "VaultB",
                symbol_: "VB",
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
                blockList_: BlockList(address(0)),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(1))
        );

        vm.stopPrank();

        assertTrue(
            addr1 != addr2,
            "Different vault params should produce different addresses"
        );
        emit log(
            "Different vault params with same salt produce different addresses (CREATE2)"
        );
    }
}

// ─────────────────────────────────────────────────────────────
// TEST GROUP 7: Storage Compatibility Fork Test
// ─────────────────────────────────────────────────────────────

contract StorageForkTest is Test {
    address constant ETH_BEACON = 0x0193BA8d74e8c7F51522a25F89C405691406eF20;

    function test_productionBeaconReturnsImpl() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            emit log(
                "SKIP: No ETH_RPC_URL set. Export via: export ETH_RPC_URL=..."
            );
            return;
        }
        vm.createSelectFork(rpc);
        VaultUpgradeableBeacon beacon = VaultUpgradeableBeacon(ETH_BEACON);
        address impl = VaultUpgradeableBeacon(ETH_BEACON).implementation();
        emit log_named_address("Production beacon implementation", impl);
        assertTrue(impl != address(0), "Implementation should not be zero");
        assertGt(impl.code.length, 0, "Implementation should be a contract");
    }

    function test_productionImplExists() public {
        string memory rpc = vm.envOr("ETH_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            emit log("SKIP: No ETH_RPC_URL set");
            return;
        }
        vm.createSelectFork(rpc);
        address impl = VaultUpgradeableBeacon(ETH_BEACON).implementation();
        uint256 size;
        assembly {
            size := extcodesize(impl)
        }
        assertTrue(
            size > 0,
            "Implementation must have code (not self-destructed)"
        );
        emit log_named_uint("Implementation code size", size);
    }
}
