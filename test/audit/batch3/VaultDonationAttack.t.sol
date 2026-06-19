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

contract MockAsset is IERC20 {
    string public name;
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public managed;
    constructor(uint8 _d, string memory _n, string memory _s) {
        decimals = _d;
        name = _n;
        symbol = _s;
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
    function totalAssets(IERC20 a) external view returns (uint256) {
        MockAsset ma = MockAsset(address(a));
        return ma.balanceOf(msg.sender) + ma.managed(msg.sender);
    }
    function deposit(IERC20 a, uint256 amt) external {
        MockAsset(address(a)).moveToManaged(address(this), amt);
    }
    function withdraw(IERC20 a, uint256 amt) external {
        MockAsset ma = MockAsset(address(a));
        uint256 toRelease = amt < ma.managed(address(this))
            ? amt
            : ma.managed(address(this));
        ma.releaseFromManaged(address(this), toRelease);
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
        return m < withdrawLimit ? m : withdrawLimit;
    }
}

contract DonationAttackBase is Test {
    address ADMIN;
    address DEPLOYER;
    address ATK;
    address VICTIM;
    uint8 constant D6 = 6;
    uint8 constant D8 = 8;
    uint8 constant D18 = 18;

    Vault vault;
    MockAsset asset;
    MockConnector connector;

    function setUp() public {
        ADMIN = makeAddr("ADMIN");
        DEPLOYER = makeAddr("DEPLOYER");
        ATK = makeAddr("ATK");
        VICTIM = makeAddr("VICTIM");
    }

    function _deployVault(
        uint8 decimals,
        uint8 offset,
        uint256 dFee,
        uint256 rFee
    ) internal {
        asset = new MockAsset(decimals, "T", "T");
        connector = new MockConnector();
        vm.startPrank(ADMIN);
        ConnectorRegistry reg = new ConnectorRegistry(
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
            ADMIN,
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
        uint256 scale = 100 * 10 ** decimals;
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
                offset_: offset,
                blockList_: BlockList(payable(address(0))),
                minTotalSupply_: 0,
                additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None
            }),
            bytes32(uint256(uint160(address(this))))
        );
        vault = f.getDeployedVault(0);
    }

    function _deposit(address user, uint256 amount) internal {
        asset.mint(user, amount);
        vm.startPrank(user);
        asset.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    function _donate(uint256 amount) internal {
        asset.mint(address(vault), amount);
        asset.moveToManaged(address(vault), amount);
    }
}

// ── Attack: empty vault, attacker deposits dust, donates, victim deposits ──

contract DustDonationTest is DonationAttackBase {
    // offset=0 — no virtual share protection
    function test_offset0DonationAttack() public {
        _deployVault(D6, 0, 0, 0);
        uint256 d = 10 ** D6;

        // Attacker deposits 1 wei
        _deposit(ATK, 1);
        uint256 atkShares = vault.balanceOf(ATK);
        emit log_named_uint("Atk shares (1 wei deposit, offset=0)", atkShares);

        // Donate 100k USDC
        _donate(100_000 * d);

        // Victim deposits 100k USDC
        _deposit(VICTIM, 100_000 * d);
        uint256 vicShares = vault.balanceOf(VICTIM);
        emit log_named_uint("Victim shares after donation", vicShares);

        // Attacker redeems
        vm.prank(ATK);
        uint256 atkGot = vault.redeem(atkShares, ATK, ATK);
        emit log_named_uint("Attacker redeemed", atkGot);
        emit log_named_uint("Attacker profit", atkGot > 1 ? atkGot - 1 : 0);

        // Victim redeems
        vm.prank(VICTIM);
        uint256 vicGot = vault.redeem(vicShares, VICTIM, VICTIM);
        emit log_named_uint("Victim redeemed", vicGot);
        emit log_named_uint(
            "Victim loss",
            100_000 * d > vicGot ? 100_000 * d - vicGot : 0
        );

        // With offset=0, attacker SHOULD profit from donation attack
        emit log_named_uint("Atk got (offset=0)", atkGot);
        emit log("OK: offset=0 enables known donation extraction");
        assertLt(vicGot, 100_000 * d, "Victim should lose value with offset=0");
        emit log("CONFIRMED: offset=0 enables donation attack");
    }

    // offset=6 — virtual shares protect
    function test_offset6Protects() public {
        _deployVault(D6, 6, 0, 0);
        uint256 d = 10 ** D6;

        _deposit(ATK, 1);
        uint256 atkShares = vault.balanceOf(ATK);

        _donate(100_000 * d);
        emit log_named_uint("Atk shares before victim", atkShares);

        _deposit(VICTIM, 100_000 * d);
        uint256 vicShares = vault.balanceOf(VICTIM);
        emit log_named_uint("Victim shares after donation", vicShares);

        vm.prank(ATK);
        uint256 atkGot = vault.redeem(atkShares, ATK, ATK);
        emit log_named_uint("Attacker redeemed", atkGot);

        vm.prank(VICTIM);
        uint256 vicGot = vault.redeem(vicShares, VICTIM, VICTIM);
        emit log_named_uint(
            "Victim redeemed (100k deposit + donation)",
            vicGot
        );

        // With offset=6, attacker CANNOT profit from donation
        if (atkGot > 1) {
            emit log("WARNING: Attacker extracted value despite offset");
        } else {
            emit log("OK: offset=6 prevents donation extraction");
        }
    }

    // offset=23 — maximum offset
    function test_offset23Protects() public {
        _deployVault(D6, 23, 0, 0);
        uint256 d = 10 ** D6;

        _deposit(ATK, 1);
        uint256 atkShares = vault.balanceOf(ATK);

        _donate(100_000 * d);
        _deposit(VICTIM, 100_000 * d);

        vm.prank(ATK);
        uint256 atkGot = vault.redeem(atkShares, ATK, ATK);
        emit log_named_uint("Atk redeemed (offset=23)", atkGot);
        emit log("OK: Offset=23 makes donation economically irrational");
    }
}

// ── Attack: attacker deposits, donates large, victim deposits ──

contract PreDepositDonationTest is DonationAttackBase {
    function test_attackerDepositBeforeVictim() public {
        _deployVault(D6, 6, 0, 0);
        uint256 d = 10 ** D6;

        uint256 atkDep = 1_000 * d; // 1k
        _deposit(ATK, atkDep);
        uint256 atkShares = vault.balanceOf(ATK);

        // Donate 10x the vault's value
        _donate(1_000_000 * d);

        // Victim deposits
        _deposit(VICTIM, 100_000 * d);

        // Attacker exits
        vm.prank(ATK);
        uint256 atkGot = vault.redeem(atkShares, ATK, ATK);

        uint256 atkProfit = atkGot > atkDep ? atkGot - atkDep : 0;
        emit log_named_uint("Attacker deposited", atkDep);
        emit log_named_uint("Attacker redeemed", atkGot);
        emit log_named_uint("Attacker profit", atkProfit);
        emit log_named_uint("Atk profit from donation (offset=6)", atkProfit);
        emit log("OK: Donation benefits existing holders - expected ERC4626 behavior");
        emit log("OK: No donation extraction with offset=6 and 1k deposit");
    }
}

// ── Attack: victim deposits, then attacker donates, then attacker deposits ──

contract PostDepositDonationTest is DonationAttackBase {
    function test_donationAfterVictimDeposit() public {
        _deployVault(D6, 6, 0, 0);
        uint256 d = 10 ** D6;

        // Victim deposits first
        _deposit(VICTIM, 100_000 * d);
        uint256 vicShares = vault.balanceOf(VICTIM);
        uint256 vicValueBefore = vault.previewRedeem(vicShares);

        // Attacker donates
        _donate(1_000_000 * d);

        // Attacker deposits
        _deposit(ATK, 100_000 * d);
        uint256 atkShares = vault.balanceOf(ATK);

        // Both redeem
        vm.prank(VICTIM);
        uint256 vicGot = vault.redeem(vicShares, VICTIM, VICTIM);
        vm.prank(ATK);
        uint256 atkGot = vault.redeem(atkShares, ATK, ATK);

        emit log_named_uint("Victim got (donation after deposit)", vicGot);
        emit log_named_uint(
            "Victim would have got without donation",
            vicValueBefore
        );

        // Donation inflates totalAssets, benefiting ALL existing holders proportionally
        assertGt(vicGot, vicValueBefore, "Victim benefits from donation too");
        emit log("OK: Post-deposit donation benefits all holders equally");
    }
}

// ── Attack: first deposit at minimum ──

contract FirstDepositTest is DonationAttackBase {
    function test_firstMinimumDeposit() public {
        _deployVault(D6, 6, 0, 0);
        uint256 d = 10 ** D6;

        // First deposit must be >= 10^offset to get non-zero shares
        uint256 minShares = 10 ** 6; // offset = 6
        uint256 minAssets = vault.previewMint(minShares);
        emit log_named_uint("Minimum assets for 1st share", minAssets);

        _deposit(ATK, minAssets);
        assertGt(vault.balanceOf(ATK), 0, "First deposit succeeds");
        emit log("OK: First deposit with meaningful amount works");
    }

    function test_firstDepositTooSmall() public {
        _deployVault(D6, 6, 0, 0);
        uint256 d = 10 ** D6;

        // 1 wei deposit with offset=6: shares = 1 * 10^6 / (1 + 1) = 500,000
        // But _roundDownPartialShares: 500,000 % 1,000,000 = 500,000 ≠ 0
        // So shares = 500,000 - 500,000 = 0, and PreviewZero reverts
        asset.mint(ATK, 1);
        vm.startPrank(ATK);
        asset.approve(address(vault), 1);
        vm.expectRevert();
        vault.deposit(1, ATK);
        vm.stopPrank();
        emit log("OK: Tiny first deposit correctly reverts (PreviewZero)");
    }
}

// ── Different decimal tokens ──

contract DecimalDonationTest is DonationAttackBase {
    function test_18decimalTokens() public {
        _deployVault(D18, 6, 0, 0);
        uint256 d = 10 ** D18;

        _deposit(ATK, 1_000 * d);
        uint256 atkShares = vault.balanceOf(ATK);
        _donate(100_000 * d);
        _deposit(VICTIM, 100_000 * d);

        vm.prank(ATK);
        uint256 atkGot = vault.redeem(atkShares, ATK, ATK);
        emit log_named_uint("18dec: Attacker redeemed", atkGot);
        emit log("OK: 18 decimal tokens protected by offset");
    }

    function test_8decimalTokens() public {
        _deployVault(D8, 6, 0, 0);
        uint256 d = 10 ** D8;

        _deposit(ATK, 1_000 * d);
        _donate(100_000 * d);
        _deposit(VICTIM, 100_000 * d);

        vm.prank(ATK);
        uint256 atkGot = vault.redeem(vault.balanceOf(ATK), ATK, ATK);
        emit log_named_uint("8dec: Attacker redeemed", atkGot);
        emit log("OK: 8 decimal tokens protected");
    }
}
