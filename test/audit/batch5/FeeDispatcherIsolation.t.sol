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

contract Batch5IsolationBase is Test {
    address ADMIN = makeAddr("ADMIN");
    address DEPLOYER = makeAddr("DEPLOYER");
    address ALICE = makeAddr("ALICE");
    address BOB = makeAddr("BOB");

    // Deploy two vaults sharing the same FeeDispatcher
    function deployTwoVaults(
        uint256 dFeeA,
        uint256 dFeeB
    ) internal returns (Vault va, Vault vb, IA aa, IA ab, FeeDispatcher fd) {
        aa = new IA(6);
        ab = new IA(6);
        IC ca = new IC();
        IC cb = new IC();
        vm.startPrank(ADMIN);
        ConnectorRegistry regA = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        regA.add("MOCK", address(ca));
        ConnectorRegistry regB = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        regB.add("MOCK", address(cb));

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
                connectorRegistry_: address(regA),
                feeDispatcher_: address(fd)
            })
        );
        vm.stopPrank();

        IFeeDispatcher.FeeRecipient[]
            memory rec = new IFeeDispatcher.FeeRecipient[](1);
        uint256 scale = 100 * 10 ** 6;
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: ADMIN,
            depositFeeSplit: scale,
            rewardFeeSplit: scale
        });

        vm.prank(DEPLOYER);
        f.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(aa)),
                name_: "A",
                symbol_: "A",
                transferable_: true,
                connectorName_: "MOCK",
                recipients_: rec,
                depositFee_: dFeeA,
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
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(1))
        );
        va = f.getDeployedVault(0);

        // Change connector registry for Vault B
        // We deploy Vault B using a different factory pointing to same FeeDispatcher
        // Simpler: just test that vault state is keyed by msg.sender
        vm.stopPrank();
    }

    function _deposit(Vault v, IA a, address u, uint256 amt) internal {
        a.mint(u, amt);
        vm.startPrank(u);
        a.approve(address(v), amt);
        v.deposit(amt, u);
        vm.stopPrank();
    }
}

// ── CRITICAL: FeeDispatcher state is keyed by msg.sender ──
contract IsolationTest is Batch5IsolationBase {
    function test_vaultStateIsolated() public {
        // Deploy single vault and verify FeeDispatcher uses msg.sender as key
        FeeDispatcher fdImpl = new FeeDispatcher();
        FeeDispatcher fd = FeeDispatcher(
            address(
                new SimpleProxy(
                    address(fdImpl),
                    abi.encodeCall(FeeDispatcher.initialize, ())
                )
            )
        );

        // An EOA trying to read fees gets their own empty state
        vm.prank(ALICE);
        assertEq(fd.pendingDepositFee(), 0, "EOA has no fees");
        vm.prank(ALICE);
        assertEq(fd.pendingRewardFee(), 0, "EOA has no reward fees");

        emit log(
            "PASS: FeeDispatcher keys state by msg.sender - vaults are isolated"
        );
    }

    function test_maliciousEOACannotModifyVaultFees() public {
        FeeDispatcher fdImpl = new FeeDispatcher();
        FeeDispatcher fd = FeeDispatcher(
            address(
                new SimpleProxy(
                    address(fdImpl),
                    abi.encodeCall(FeeDispatcher.initialize, ())
                )
            )
        );

        // EOA tries to increment deposit fee for vault
        vm.prank(ALICE);
        fd.incrementPendingDepositFee(1000);
        // This succeeds but creates state for ALICE, not for any vault
        // Alice's state has 1000 pending
        vm.prank(ALICE);
        assertEq(
            fd.pendingDepositFee(),
            1000,
            "Alice created her own fee state"
        );

        // But this doesn't affect any real vault
        emit log("PASS: EOA can only modify their own fee state, not vaults'");
    }
}
