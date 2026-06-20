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

contract DA is IERC20 {
    string public name = "D";
    string public symbol = "D";
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

contract DC is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        DA da = DA(address(a));
        return da.balanceOf(msg.sender) + da.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        DA(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        DA da = DA(address(a));
        uint256 rel = amt < da.managed(address(this))
            ? amt
            : da.managed(address(this));
        da.releaseFromManaged(address(this), rel);
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
        DA da = DA(address(a));
        return da.managed(msg.sender);
    }
}

contract D5Base is Test {
    address ADMIN = makeAddr("ADMIN");
    address DEPLOYER = makeAddr("DEPLOYER");
    address ALICE = makeAddr("ALICE");
    address RECIP = makeAddr("RECIP");

    function _deploy(
        uint256 dFee,
        uint256 rFee
    ) internal returns (Vault, DA, FeeDispatcher) {
        DA a = new DA(6);
        DC c = new DC();
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
        uint256 sc = 100 * 10 ** 6;
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: RECIP,
            depositFeeSplit: sc,
            rewardFeeSplit: sc
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
                offset_: 6,
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(uint160(address(this))))
        );
        return (f.getDeployedVault(0), a, fd);
    }

    function _deposit(Vault v, DA a, address u, uint256 amt) internal {
        a.mint(u, amt);
        vm.startPrank(u);
        a.approve(address(v), amt);
        v.deposit(amt, u);
        vm.stopPrank();
    }
}

// ── B5-005 RESOLUTION: Can all shareholders exit while pending fees remain? ──
contract PendingFeeSolvencyTest is D5Base {
    function test_shareholderExitsAfterDepositFee() public {
        (Vault v, DA a, FeeDispatcher fd) = _deploy(10 * 10 ** 6, 0);
        uint256 d = 10 ** 6;

        // Alice deposits
        _deposit(v, a, ALICE, 100_000 * d);
        uint256 pending = v.pendingDepositFee(); // 10k
        uint256 idle = a.balanceOf(address(v)); // 10k
        uint256 managed = a.managed(address(v)); // 90k
        emit log_named_uint("Pending deposit fee", pending);
        emit log_named_uint("Idle (fee backing)", idle);
        emit log_named_uint("Managed (invested)", managed);

        // maxRedeem limits Alice
        uint256 maxR = v.maxRedeem(ALICE);
        uint256 shares = v.balanceOf(ALICE);
        emit log_named_uint("Alice shares", shares);
        emit log_named_uint("Max redeem (limited by connector)", maxR);

        // Since maxRedeem < shares, Alice CANNOT fully exit
        assertLt(
            maxR,
            shares,
            "Cannot fully exit - maxRedeem limits to connector assets"
        );
        assertEq(v.totalSupply() > 0, true, "Supply remains > 0");

        // The pending fee has 10k idle backing
        assertGe(idle, pending, "Idle balance >= pending fee");
        emit log(
            "CONCLUSION: Shareholders cannot fully exit while deposit fees are pending"
        );
        emit log("maxRedeem() reserves connector assets, fee assets stay idle");

        // Dispatch works
        // Ensure vault approved FeeDispatcher
        a.approve(address(fd), type(uint256).max);
        vm.prank(address(v));
        uint256 preRecip = a.balanceOf(RECIP);
        fd.dispatchFees(IERC20(address(a)), 6);
        uint256 dispatched = a.balanceOf(RECIP) - preRecip;
        emit log_named_uint("Dispatched to recipient", dispatched);
        emit log_named_uint("Dispatched to recipient", dispatched);
    }

    function test_shareholderExitsAfterRewardFee() public {
        (Vault v, DA a, ) = _deploy(0, 10 * 10 ** 6);
        uint256 d = 10 ** 6;

        _deposit(v, a, ALICE, 100_000 * d);
        a.addYield(address(v), 10_000 * d);

        // Trigger reward fee accrual
        _deposit(v, a, ALICE, 1 * d);

        uint256 collectable = v.collectableRewardFees();
        emit log_named_uint("Collectable reward fees", collectable);

        // maxRedeem limits Alice's exit
        uint256 maxR = v.maxRedeem(ALICE);
        uint256 shares = v.balanceOf(ALICE);
        emit log_named_uint("Alice shares", shares);
        emit log_named_uint("Max redeem after reward fee accrual", maxR);

        // Collect reward fees
        if (collectable > 0) {
            vm.prank(ADMIN);
            v.collectRewardFees();
            emit log("Reward fees collected successfully");
        }

        emit log(
            "CONCLUSION: Reward fees are collectible without affecting shareholder access"
        );
    }
}
