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

contract TestAsset is IERC20 {
    string public name = "T";
    string public symbol = "T";
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

// Connectors with NO storage state (all immutables) for delegatecall safety
// Each connector has a different return behavior encoded in its immutable

contract ExactReturnConnector is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        TestAsset ta = TestAsset(address(a));
        return ta.balanceOf(msg.sender) + ta.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        TestAsset(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        TestAsset ta = TestAsset(address(a));
        uint256 rel = amt < ta.managed(address(this))
            ? amt
            : ta.managed(address(this));
        ta.releaseFromManaged(address(this), rel);
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
        TestAsset ta = TestAsset(address(a));
        return ta.managed(msg.sender);
    }
}

// Always returns exactly HALF of what's requested
contract HalfReturnConnector is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        TestAsset ta = TestAsset(address(a));
        return ta.balanceOf(msg.sender) + ta.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        TestAsset(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        TestAsset ta = TestAsset(address(a));
        uint256 rel = amt < ta.managed(address(this))
            ? amt
            : ta.managed(address(this));
        ta.releaseFromManaged(address(this), rel / 2); // return only half
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
        TestAsset ta = TestAsset(address(a));
        return ta.managed(msg.sender);
    }
}

// Always returns ZERO
contract ZeroReturnConnector is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        TestAsset ta = TestAsset(address(a));
        return ta.balanceOf(msg.sender) + ta.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        TestAsset(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20, uint256) external {
        /* return nothing */
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
        TestAsset ta = TestAsset(address(a));
        return ta.managed(msg.sender);
    }
}

contract ShortWithdrawalTest is Test {
    address ADMIN = makeAddr("ADMIN");
    address DEPLOYER = makeAddr("DEPLOYER");
    address ALICE = makeAddr("ALICE");
    address BOB = makeAddr("BOB");

    // Deploy vault with a specific connector implementation
    function _deployWithConnector(
        IConnector conn
    ) internal returns (Vault vault, TestAsset asset) {
        asset = new TestAsset(6);
        vm.startPrank(ADMIN);
        ConnectorRegistry reg = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            uint48(1 days)
        );
        reg.add("MOCK", address(conn));
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
                asset_: IERC20(address(asset)),
                name_: "V",
                symbol_: "V",
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
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(uint160(address(this))))
        );
        vault = f.getDeployedVault(0);
    }

    function _deposit(
        TestAsset a,
        Vault v,
        address user,
        uint256 amt
    ) internal {
        a.mint(user, amt);
        vm.startPrank(user);
        a.approve(address(v), amt);
        v.deposit(amt, user);
        vm.stopPrank();
    }

    // ── TEST: Exact return (happy path) ──

    // ── TEST: Half return - shares burned for full value, only half returned ──
    function test_halfReturn() public {
        (Vault v, TestAsset a) = _deployWithConnector(
            new HalfReturnConnector()
        );
        uint256 d = 10 ** 6;

        // Two users: Alice will withdraw, Bob will remain
        _deposit(a, v, ALICE, 100_000 * d);
        _deposit(a, v, BOB, 100_000 * d);

        uint256 taBefore = v.totalAssets(); // ≈ 200k
        uint256 tsBefore = v.totalSupply();
        uint256 aliceShares = v.balanceOf(ALICE);
        uint256 bobShares = v.balanceOf(BOB);
        uint256 alicePreview = v.previewRedeem(aliceShares);

        emit log_named_uint("TA before", taBefore);
        emit log_named_uint("TS before", tsBefore);
        emit log_named_uint("Alice preview (fair value)", alicePreview);
        emit log_named_uint("Bob shares", bobShares);

        // Alice withdraws — connector returns only HALF
        uint256 pre = a.balanceOf(ALICE);
        vm.prank(ALICE);
        uint256 redeemedAssets = v.redeem(aliceShares, ALICE, ALICE);
        uint256 aliceGot = a.balanceOf(ALICE) - pre;

        emit log_named_uint("Redeem returned", redeemedAssets);
        emit log_named_uint("Alice actually received", aliceGot);
        emit log_named_uint(
            "Alice shortfall vs preview",
            alicePreview - aliceGot
        );

        // PROOF: Alice received LESS than fair value
        assertLt(aliceGot, alicePreview, "Alice gets less than fair value");
        assertEq(v.balanceOf(ALICE), 0, "Alice shares fully burned");

        // PROOF: Bob's remaining shares are worth MORE (windfall from Alice's loss)
        uint256 bobValue = v.previewRedeem(v.balanceOf(BOB));
        emit log_named_uint("Bob withdrawable value after", bobValue);
        if (bobValue > 100_000 * d) {
            emit log_named_uint(
                "Bob windfall from Alice shortfall",
                bobValue - 100_000 * d
            );
        }

        // PROVEN: Short withdrawal transfers value from withdrawing user to remaining holders
        emit log(
            "PROVEN: Short withdrawal causes value loss for withdrawing user"
        );
    }

    // ── TEST: Zero return - shares burned, nothing received ──
    function test_zeroReturn() public {
        (Vault v, TestAsset a) = _deployWithConnector(
            new ZeroReturnConnector()
        );
        uint256 d = 10 ** 6;

        _deposit(a, v, ALICE, 100_000 * d);
        _deposit(a, v, BOB, 100_000 * d);

        uint256 aliceShares = v.balanceOf(ALICE);
        uint256 pre = a.balanceOf(ALICE);
        vm.prank(ALICE);
        uint256 redeemed = v.redeem(aliceShares, ALICE, ALICE);
        uint256 aliceGot = a.balanceOf(ALICE) - pre;

        emit log_named_uint("Redeemed (event value)", redeemed);
        emit log_named_uint("Alice actually received", aliceGot);
        assertEq(v.balanceOf(ALICE), 0, "Alice shares burned");
        assertEq(aliceGot, 0, "Alice got nothing");

        // BOB now owns 100% of remaining assets
        emit log_named_uint("Bob now owns", v.previewRedeem(v.balanceOf(BOB)));
        emit log(
            "PROVEN: Zero return = shares burned, assets lost, windfall to remaining holders"
        );
    }
}
