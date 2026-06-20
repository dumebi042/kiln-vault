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

contract FA is IERC20 {
    string public name = "F";
    string public symbol = "F";
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

contract FC is IConnector {
    function totalAssets(IERC20 a) external view returns (uint256) {
        FA fa = FA(address(a));
        return fa.balanceOf(msg.sender) + fa.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        FA(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        FA fa = FA(address(a));
        uint256 rel = amt < fa.managed(address(this))
            ? amt
            : fa.managed(address(this));
        fa.releaseFromManaged(address(this), rel);
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
        FA fa = FA(address(a));
        return fa.managed(msg.sender);
    }
}

contract DepositFeeTest is Test {
    address ADMIN = makeAddr("ADMIN");
    address DEPLOYER = makeAddr("DEPLOYER");
    address ALICE = makeAddr("ALICE");

    function _deploy(uint256 dFee) internal returns (Vault, FA) {
        FA a = new FA(6);
        FC c = new FC();
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
                depositFee_: dFee,
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
        return (f.getDeployedVault(0), a);
    }

    function _deposit(Vault v, FA a, address u, uint256 amt) internal {
        a.mint(u, amt);
        vm.startPrank(u);
        a.approve(address(v), amt);
        v.deposit(amt, u);
        vm.stopPrank();
    }

    function test_feeCaptured() public {
        (Vault v, FA a) = _deploy(10 * 10 ** 6);
        uint256 d = 10 ** 6;
        _deposit(v, a, ALICE, 100_000 * d);
        assertApproxEqRel(
            v.pendingDepositFee(),
            10_000 * d,
            0.01e18,
            "Fee captured"
        );
        assertEq(a.balanceOf(address(v)), 10_000 * d, "10k idle");
        assertEq(a.managed(address(v)), 90_000 * d, "90k invested");
    }

    function test_feeAssetsProtectedByMaxRedeem() public {
        (Vault v, FA a) = _deploy(10 * 10 ** 6);
        uint256 d = 10 ** 6;
        _deposit(v, a, ALICE, 100_000 * d);
        uint256 maxRedeem = v.maxRedeem(ALICE);
        uint256 aliceShares = v.balanceOf(ALICE);
        // maxRedeem limits to connector-accessible assets (90k invested, not 10k fee)
        assertLt(
            maxRedeem,
            aliceShares,
            "Fee assets not redeemable via maxRedeem"
        );
        emit log(
            "PASS: Fee assets protected - maxRedeem limits to connector-accessible assets"
        );
    }
}
