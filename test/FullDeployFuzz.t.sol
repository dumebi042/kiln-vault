// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;
import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {Vault} from "../src/Vault.sol";
import {VaultFactory} from "../src/VaultFactory.sol";
import {VaultUpgradeableBeacon} from "../src/proxy/VaultUpgradeableBeacon.sol";
import {ConnectorRegistry} from "../src/ConnectorRegistry.sol";
import {FeeDispatcher} from "../src/FeeDispatcher.sol";
import {BlockList} from "../src/BlockList.sol";
import {IConnector} from "../src/interfaces/IConnector.sol";
import {IFeeDispatcher} from "../src/interfaces/IFeeDispatcher.sol";
import {SimpleProxy} from "../src/test-helpers/SimpleProxy.sol";

contract MockE {
    string public n;
    string public s;
    uint8 public immutable D;
    mapping(address => uint256) public b;
    mapping(address => mapping(address => uint256)) public a;
    event T(address indexed f, address indexed t, uint256 v);
    event Ap(address indexed o, address indexed s, uint256 v);
    constructor(string memory _n, string memory _s, uint8 _d) {
        n = _n;
        s = _s;
        D = _d;
    }
    function decimals() external view returns (uint8) {
        return D;
    }
    function mint(address to, uint256 amt) external {
        b[to] += amt;
        emit T(address(0), to, amt);
    }
    function approve(address sp, uint256 amt) external returns (bool) {
        a[msg.sender][sp] = amt;
        emit Ap(msg.sender, sp, amt);
        return true;
    }
    function transferFrom(
        address f,
        address t,
        uint256 amt
    ) external returns (bool) {
        require(a[f][msg.sender] >= amt, "!");
        require(b[f] >= amt, "!");
        a[f][msg.sender] -= amt;
        b[f] -= amt;
        b[t] += amt;
        emit T(f, t, amt);
        return true;
    }
    function transfer(address t, uint256 amt) external returns (bool) {
        require(b[msg.sender] >= amt, "!");
        b[msg.sender] -= amt;
        b[t] += amt;
        emit T(msg.sender, t, amt);
        return true;
    }
}

contract MockC is IConnector {
    mapping(address => uint256) public sup;
    mapping(address => uint256) public y;
    function deposit(IERC20 a, uint256 amt) external override {
        sup[address(a)] += amt;
    }
    function withdraw(IERC20 a, uint256 amt) external override {
        require(sup[address(a)] >= amt, "!");
        sup[address(a)] -= amt;
        IERC20(address(a)).transfer(msg.sender, amt);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external override returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external override {}
    function totalAssets(IERC20 a) external view override returns (uint256) {
        return sup[address(a)] + y[address(a)];
    }
    function maxDeposit(IERC20) external view override returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20 a) external view override returns (uint256) {
        return sup[address(a)] + y[address(a)];
    }
    function addY(IERC20 a, uint256 amt) external {
        y[address(a)] += amt;
    }
}

contract FullDeployFuzz is Test {
    Vault public v;
    MockC public mc;
    MockE public asset;
    address admin = makeAddr("admin");
    address dep = makeAddr("dep");
    address u = makeAddr("u");
    uint8 constant D0 = 6;

    function setUp() public {
        asset = new MockE("U", "U", D0);
        vm.startPrank(admin);
        ConnectorRegistry reg = new ConnectorRegistry(
            admin,
            admin,
            admin,
            admin,
            admin,
            uint48(1 days)
        );
        FeeDispatcher fdi = new FeeDispatcher();
        FeeDispatcher fd = FeeDispatcher(
            address(
                new SimpleProxy(
                    address(fdi),
                    abi.encodeCall(FeeDispatcher.initialize, ())
                )
            )
        );

        VaultFactory fi = new VaultFactory();
        // Deploy factory proxy without init data (SimpleProxy allows this)
        VaultFactory f = VaultFactory(
            address(new SimpleProxy(address(fi), ""))
        );
        // Now we have the factory address - deploy vault impl with it
        Vault vi = new Vault(address(admin), address(f));
        VaultUpgradeableBeacon bn = new VaultUpgradeableBeacon(
            address(vi),
            admin,
            admin,
            admin,
            admin,
            admin,
            uint48(1 days)
        );

        // Init factory
        f.initialize(
            VaultFactory.InitializationParams({
                initialAdmin_: admin,
                initialDeployer_: dep,
                initialDelay_: uint48(1 days),
                vaultBeacon_: address(bn),
                connectorRegistry_: address(reg),
                feeDispatcher_: address(fd)
            })
        );
        vm.stopPrank();

        mc = new MockC();
        vm.prank(admin);
        reg.add("M", address(mc));

        vm.startPrank(dep);
        f.createVault(
            VaultFactory.CreateVaultParams({
                asset_: IERC20(address(asset)),
                name_: "T",
                symbol_: "t",
                transferable_: true,
                connectorName_: "M",
                recipients_: new IFeeDispatcher.FeeRecipient[](0),
                depositFee_: 0,
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
                blockList_: BlockList(address(0)),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(1))
        );
        v = f.getDeployedVault(0);
        vm.stopPrank();
        targetContract(address(this));
    }

    function depo(uint256 amt) public {
        amt = bound(amt, 1, 100_000 * 10 ** D0);
        asset.mint(u, amt);
        vm.startPrank(u);
        asset.approve(address(v), amt);
        v.deposit(amt, u);
        vm.stopPrank();
    }
    function wd(uint256 amt) public {
        uint256 mw = v.maxWithdraw(u);
        if (mw == 0) return;
        amt = bound(amt, 1, mw);
        vm.prank(u);
        v.withdraw(amt, u, u);
    }
    function rd(uint256 s) public {
        uint256 mr = v.maxRedeem(u);
        if (mr == 0) return;
        s = bound(s, 1, mr);
        vm.prank(u);
        v.redeem(s, u, u);
    }
    function yield(uint256 amt) public {
        amt = bound(amt, 0, 100_000 * 10 ** D0);
        mc.addY(IERC20(address(asset)), amt);
    }

    function invariant_v001() public view {
        if (v.totalSupply() > 0) assertGt(v.totalAssets(), 0);
    }
    function invariant_v002() public view {
        assertLe(v.maxWithdraw(u), v.totalAssets());
    }
    function invariant_v003() public view {
        assertLe(v.maxRedeem(u), v.totalSupply());
    }
    function invariant_v004() public view {
        uint256 s = v.balanceOf(u);
        if (s > 0) assertLe(v.previewRedeem(s), v.totalAssets());
    }
}
