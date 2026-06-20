// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
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

contract IA is IERC20 {
    string public name = "I";
    string public symbol = "I";
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
    function moveToManaged(address from, uint256 amt) external {
        balanceOf[from] -= amt;
        managed[from] += amt;
    }
    function releaseFromManaged(address to, uint256 amt) external {
        uint256 actual = amt < managed[to] ? amt : managed[to];
        managed[to] -= actual;
        balanceOf[to] += actual;
    }
    function addYield(address vault, uint256 amt) external {
        managed[vault] += amt;
        totalSupply += amt;
    }
}

contract IC is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        IA ia = IA(address(a));
        return ia.balanceOf(msg.sender) + ia.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        IA(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        IA ia = IA(address(a));
        uint256 rel = amt < ia.managed(address(this))
            ? amt
            : ia.managed(address(this));
        ia.releaseFromManaged(address(this), rel);
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
        IA ia = IA(address(a));
        return ia.managed(msg.sender);
    }
}

contract FeeHandler is Test {
    Vault public vault;
    IA public asset;
    FeeDispatcher public fd;
    address ADMIN = makeAddr("ADMIN");

    // Ghost tracking
    uint256 public totalDepositFeesAccrued;
    uint256 public totalFeesDispatched;
    uint256 public totalPrincipalDeposited;
    uint256 public totalShareholderWithdrawn;

    constructor(Vault v, IA a, FeeDispatcher f) {
        vault = v;
        asset = a;
        fd = f;
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 10 ** 12, 10 ** 15);
        address user = makeAddr("USER");
        asset.mint(user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        uint256 pendingBefore = vault.pendingDepositFee();
        vault.deposit(amount, user);
        uint256 pendingAfter = vault.pendingDepositFee();
        vm.stopPrank();
        totalPrincipalDeposited += amount;
        if (pendingAfter > pendingBefore) {
            totalDepositFeesAccrued += pendingAfter - pendingBefore;
        }
    }

    function dispatch() external {
        uint256 pre = vault.pendingDepositFee() + vault.pendingRewardFee();
        vm.prank(address(vault));
        fd.dispatchFees(IERC20(address(asset)), 6);
        uint256 post = vault.pendingDepositFee() + vault.pendingRewardFee();
        totalFeesDispatched += pre - post;
    }

    function collectReward() external {
        if (vault.collectableRewardFees() > 0) {
            vm.prank(ADMIN);
            vault.collectRewardFees();
        }
    }
}

contract FeeInvariantTest is StdInvariant, Test {
    FeeHandler handler;
    IA asset;
    Vault vault;
    FeeDispatcher fd;

    function setUp() public {
        address admin = makeAddr("ADMIN");
        address deployer = makeAddr("DEPLOYER");
        asset = new IA(6);
        IC c = new IC();
        vm.startPrank(admin);
        ConnectorRegistry reg = new ConnectorRegistry(
            admin,
            admin,
            admin,
            admin,
            admin,
            uint48(1 days)
        );
        reg.add("MOCK", address(c));
        FeeDispatcher fdImpl = new FeeDispatcher();
        fd = FeeDispatcher(
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
                initialDefaultAdmin_: admin,
                initialRole_: ExternalAccessControl.InitialRole({
                    role: bytes32("SPENDER"),
                    account: admin
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
            admin,
            admin,
            admin,
            admin,
            admin,
            uint48(1 days)
        );
        f.initialize(
            VaultFactory.InitializationParams({
                initialAdmin_: admin,
                initialDeployer_: deployer,
                initialDelay_: uint48(1 days),
                vaultBeacon_: address(bn),
                connectorRegistry_: address(reg),
                feeDispatcher_: address(fd)
            })
        );
        vm.stopPrank();
        IFeeDispatcher.FeeRecipient[]
            memory rec = new IFeeDispatcher.FeeRecipient[](1);
        uint256 sc = 100 * 10 ** 6;
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: admin,
            depositFeeSplit: sc,
            rewardFeeSplit: sc
        });
        vm.prank(deployer);
        f.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(asset)),
                name_: "V",
                symbol_: "V",
                transferable_: true,
                connectorName_: "MOCK",
                recipients_: rec,
                depositFee_: 10 * 10 ** 6,
                rewardFee_: 0,
                initialDefaultAdmin_: admin,
                initialFeeManager_: admin,
                initialFeeCollector_: admin,
                initialSanctionsManager_: admin,
                initialClaimManager_: admin,
                initialPauser_: admin,
                initialUnpauser_: admin,
                initialDelay_: uint48(1 days),
                offset_: 6,
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(1))
        );
        vault = f.getDeployedVault(0);
        handler = new FeeHandler(vault, asset, fd);
        targetContract(address(handler));
    }

    function invariant_feesDispatchedLeAccrued() public {
        assertLe(
            handler.totalFeesDispatched(),
            handler.totalDepositFeesAccrued(),
            "Dispatched <= accrued"
        );
    }

    function invariant_pendingFeeBacked() public {
        assertGe(
            asset.balanceOf(address(vault)),
            vault.pendingDepositFee(),
            "Idle >= pending fee"
        );
    }
}
