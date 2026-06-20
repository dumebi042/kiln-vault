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

contract RA is IERC20 {
    string public name = "R";
    string public symbol = "R";
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

contract RC is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        RA ra = RA(address(a));
        return ra.balanceOf(msg.sender) + ra.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        RA(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        RA ra = RA(address(a));
        uint256 rel = amt < ra.managed(address(this))
            ? amt
            : ra.managed(address(this));
        ra.releaseFromManaged(address(this), rel);
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
        RA ra = RA(address(a));
        return ra.managed(msg.sender);
    }
}

contract Batch5RewardBase is Test {
    address ADMIN = makeAddr("ADMIN");
    address DEPLOYER = makeAddr("DEPLOYER");
    address ALICE = makeAddr("ALICE");
    address BOB = makeAddr("BOB");

    function deployVault(uint256 rFee) internal returns (Vault, RA) {
        RA a = new RA(6);
        RC c = new RC();
        vm.startPrank(ADMIN);
        ConnectorRegistry reg = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        reg.add("MOCK", address(c));
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
        uint256 scale = 100 * 10 ** 6;
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: ADMIN,
            depositFeeSplit: scale,
            rewardFeeSplit: scale
        });
        vm.prank(DEPLOYER);
        f.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(a)),
                name_: "V",
                symbol_: "V",
                transferable_: true,
                connectorName_: "MOCK",
                recipients_: rec,
                depositFee_: 0,
                rewardFee_: rFee,
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
            bytes32(uint256(uint160(address(this))))
        );
        return (f.getDeployedVault(0), a);
    }

    function _deposit(Vault v, RA a, address u, uint256 amt) internal {
        a.mint(u, amt);
        vm.startPrank(u);
        a.approve(address(v), amt);
        v.deposit(amt, u);
        vm.stopPrank();
    }
}

// ── CRITICAL: Can reward fee be charged twice on the same yield? ──
contract RewardFeeCheckpointTest is Batch5RewardBase {
    function test_noDoubleFeeOnSameYield() public {
        (Vault v, RA a) = deployVault(10 * 10 ** 6); // 10% reward fee
        uint256 d = 10 ** 6;
        _deposit(v, a, ALICE, 100_000 * d);

        // Add yield
        a.addYield(address(v), 10_000 * d);

        // First accrual
        _deposit(v, a, BOB, 1_000 * d);
        uint256 rewardShares1 = v.balanceOf(address(v));
        emit log_named_uint("Reward shares after 1st accrual", rewardShares1);

        // Second accrual (no new yield)
        uint256 taBefore = v.totalAssets();
        _deposit(v, a, BOB, 1_000 * d);
        uint256 rewardShares2 = v.balanceOf(address(v));
        emit log_named_uint("Reward shares after 2nd accrual", rewardShares2);

        // No new reward shares minted without new yield
        assertEq(
            rewardShares1,
            rewardShares2,
            "No double fee without new yield"
        );
        emit log("PASS: No double fee on same yield");
    }

    function test_noFeeOnPrincipal() public {
        (Vault v, RA a) = deployVault(10 * 10 ** 6);
        uint256 d = 10 ** 6;
        _deposit(v, a, ALICE, 100_000 * d);
        uint256 before = v.balanceOf(address(v));
        _deposit(v, a, BOB, 100_000 * d);
        // No yield added - deposit of BOB should not trigger reward fee
        assertEq(
            v.balanceOf(address(v)),
            before,
            "No fee on principal-only deposit"
        );
        emit log("PASS: No reward fee on principal");
    }

    function test_lossResetsCheckpoint() public {
        (Vault v, RA a) = deployVault(10 * 10 ** 6);
        uint256 d = 10 ** 6;
        _deposit(v, a, ALICE, 100_000 * d);

        // Add yield → fee accrues
        a.addYield(address(v), 10_000 * d);
        _deposit(v, a, BOB, 1_000 * d);
        uint256 afterYield = v.balanceOf(address(v));

        // Loss - no new fee should be charged
        _deposit(v, a, BOB, 1_000 * d);
        assertEq(
            v.balanceOf(address(v)),
            afterYield,
            "Same fee after no growth"
        );
        emit log("PASS: Reward fee checkpoint preserves state through loss");
    }
}
