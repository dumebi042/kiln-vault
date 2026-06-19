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

contract MockAsset is IERC20 {
    string public name = "M";
    string public symbol = "M";
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
    uint256 public wl = type(uint256).max;
    function setWL(uint256 l) external {
        wl = l;
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
        uint256 rel = amt < ma.managed(address(this))
            ? amt
            : ma.managed(address(this));
        ma.releaseFromManaged(address(this), rel);
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
        return m < wl ? m : wl;
    }
}

// Ghost accounting: track total deposits and withdrawals
contract VaultHandler is Test {
    Vault public immutable vault;
    MockAsset public immutable asset;
    address[] public actors;

    // Ghost variables
    uint256 public totalDepositedAssets;
    uint256 public totalWithdrawnAssets;
    uint256 public totalDonated;
    uint256 public totalYieldAdded;

    constructor(Vault v, MockAsset a) {
        vault = v;
        asset = a;
        actors.push(makeAddr("USER1"));
        actors.push(makeAddr("USER2"));
        actors.push(makeAddr("USER3"));
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 10 ** 12, 10 ** 15);
        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), type(uint256).max);
        uint256 shares = vault.deposit(amount, actor);
        vm.stopPrank();
        if (shares > 0) {
            totalDepositedAssets += amount;
        }
    }

    function redeem(uint256 actorSeed, uint256 sharePct) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) return;
        sharePct = bound(sharePct, 1, 100);
        uint256 shares = (balance * sharePct) / 100;
        if (shares == 0) return;
        vm.prank(actor);
        uint256 assets = vault.redeem(shares, actor, actor);
        totalWithdrawnAssets += assets;
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 10 ** 6, 10 ** 12);
        asset.mint(address(vault), amount);
        asset.moveToManaged(address(vault), amount);
        totalDonated += amount;
    }

    function addYield(uint256 amount) external {
        amount = bound(amount, 0, 10 ** 12);
        if (amount > 0) {
            asset.addYield(address(vault), amount);
            totalYieldAdded += amount;
        }
    }

    function actorBalance() external view returns (uint256) {
        uint256 total;
        for (uint256 i = 0; i < actors.length; i++) {
            total += vault.balanceOf(actors[i]);
        }
        return total;
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }
}

contract VaultAccountingInvariantTest is StdInvariant, Test {
    Vault vault;
    MockAsset asset;
    MockConnector connector;
    VaultHandler handler;

    function setUp() public {
        address admin = makeAddr("ADMIN");
        address deployer = makeAddr("DEPLOYER");

        asset = new MockAsset(6);
        connector = new MockConnector();

        vm.startPrank(admin);
        ConnectorRegistry reg = new ConnectorRegistry(
            admin,
            admin,
            admin,
            admin,
            admin,
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
        uint256 scale = 100 * 10 ** 6;
        rec[0] = IFeeDispatcher.FeeRecipient({
            recipient: admin,
            depositFeeSplit: scale,
            rewardFeeSplit: scale
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
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(uint160(address(this))))
        );
        vault = f.getDeployedVault(0);

        handler = new VaultHandler(vault, asset);
        targetContract(address(handler));
    }

    /// Invariant: totalAssets equals sum of vault balance + managed by connector
    function invariant_totalAssetsEqBalPlusManaged() public {
        assertEq(
            vault.totalAssets(),
            asset.balanceOf(address(vault)) + asset.managed(address(vault)),
            "totalAssets should reflect actual recoverable assets"
        );
    }

    /// Invariant: total supply equals sum of all user balances + vault's own shares
    function invariant_supplyEqBalances() public {
        uint256 tracked;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            tracked += vault.balanceOf(handler.actors(i));
        }
        tracked += vault.balanceOf(address(vault));
        assertEq(
            vault.totalSupply(),
            tracked,
            "Supply should equal all balances"
        );
    }

    /// Invariant: Max withdraw for each user cannot exceed total assets
    function invariant_maxWithdrawBounded() public {
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            if (vault.balanceOf(actor) > 0) {
                assertLe(
                    vault.maxWithdraw(actor),
                    vault.totalAssets(),
                    "maxWithdraw <= totalAssets"
                );
            }
        }
    }

    /// Invariant: Max redeem for each user cannot exceed their balance
    function invariant_maxRedeemBounded() public {
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            assertLe(
                vault.maxRedeem(actor),
                vault.balanceOf(actor),
                "maxRedeem <= balance"
            );
        }
    }

    /// Invariant: Preview round-trip does not overpromise
    function invariant_previewRoundTrip() public {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            address actor = handler.actors(i);
            uint256 shares = vault.balanceOf(actor);
            if (shares == 0) continue;
            uint256 assets = vault.previewRedeem(shares);
            assertLe(
                vault.previewWithdraw(assets),
                shares,
                "previewWithdraw(previewRedeem(shares)) <= shares"
            );
        }
    }
}
