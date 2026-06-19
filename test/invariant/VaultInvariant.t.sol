// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/interfaces/IERC20Metadata.sol";
import {IAccessControl} from "@openzeppelin/access/IAccessControl.sol";

import {Vault} from "../../src/Vault.sol";
import {BlockList} from "../../src/BlockList.sol";
import {IConnector} from "../../src/interfaces/IConnector.sol";
import {IConnectorRegistry} from "../../src/interfaces/IConnectorRegistry.sol";
import {IFeeDispatcher} from "../../src/interfaces/IFeeDispatcher.sol";

contract MockAsset is IERC20Metadata {
    string public name = "Mock Asset";
    string public symbol = "MOCK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => uint256) public managed;

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function moveToManaged(address vault, uint256 amount) external {
        balanceOf[vault] -= amount;
        managed[vault] += amount;
        emit Transfer(vault, address(this), amount);
    }

    function releaseManaged(address vault, uint256 amount) external {
        managed[vault] -= amount;
        balanceOf[vault] += amount;
        emit Transfer(address(this), vault, amount);
    }

    function addYield(address vault, uint256 amount) external {
        totalSupply += amount;
        managed[vault] += amount;
        emit Transfer(address(0), address(this), amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}

contract MockConnector is IConnector {
    function totalAssets(IERC20 asset) external view returns (uint256) {
        MockAsset token = MockAsset(address(asset));
        return token.balanceOf(msg.sender) + token.managed(msg.sender);
    }

    function deposit(IERC20 asset, uint256 amount) external {
        MockAsset(address(asset)).moveToManaged(address(this), amount);
    }

    function withdraw(IERC20 asset, uint256 amount) external {
        MockAsset(address(asset)).releaseManaged(address(this), amount);
    }

    function claim(IERC20, IERC20, bytes calldata) external pure returns (uint256) {
        return 0;
    }

    function reinvest(IERC20, IERC20, bytes calldata) external pure {}

    function maxDeposit(IERC20) external pure returns (uint256) {
        return type(uint256).max;
    }

    function maxWithdraw(IERC20 asset) external view returns (uint256) {
        MockAsset token = MockAsset(address(asset));
        return token.balanceOf(msg.sender) + token.managed(msg.sender);
    }
}

contract MockConnectorRegistry is IConnectorRegistry {
    bytes32 public immutable connectorName;
    address public immutable connector;
    bool public isPaused;

    constructor(bytes32 connectorName_, address connector_) {
        connectorName = connectorName_;
        connector = connector_;
    }

    function get(bytes32 name) external view returns (address) {
        return name == connectorName ? connector : address(0);
    }

    function getOrRevert(bytes32 name) external view returns (address) {
        require(name == connectorName && !isPaused, "connector unavailable");
        return connector;
    }

    function connectorExists(bytes32 name) external view returns (bool) {
        return name == connectorName;
    }

    function add(bytes32, address) external pure {}
    function update(bytes32, address) external pure {}
    function remove(bytes32) external pure {}
    function pause(bytes32) external {
        isPaused = true;
    }
    function pauseFor(bytes32, uint256) external {
        isPaused = true;
    }
    function unPause(bytes32) external {
        isPaused = false;
    }
    function paused(bytes32) external view returns (bool) {
        return isPaused;
    }
    function freeze(bytes32) external pure {}
}

contract MockFeeDispatcher is IFeeDispatcher {
    uint256 public pendingDepositFee;
    uint256 public pendingRewardFee;
    FeeRecipient[] internal recipients;

    function dispatchFees(IERC20, uint8) external {
        pendingDepositFee = 0;
        pendingRewardFee = 0;
    }

    function feeRecipients() external view returns (FeeRecipient[] memory) {
        return recipients;
    }

    function feeRecipient(address recipient) external view returns (FeeRecipient memory) {
        for (uint256 i; i < recipients.length; i++) {
            if (recipients[i].recipient == recipient) return recipients[i];
        }
        return FeeRecipient(address(0), 0, 0);
    }

    function feeRecipientAt(uint256 index) external view returns (FeeRecipient memory) {
        return recipients[index];
    }

    function setFeeRecipients(IFeeDispatcher.FeeRecipient[] memory newRecipients, uint8) external {
        delete recipients;
        for (uint256 i; i < newRecipients.length; i++) {
            recipients.push(newRecipients[i]);
        }
    }

    function incrementPendingRewardFee(uint256 amount) external {
        pendingRewardFee += amount;
    }

    function incrementPendingDepositFee(uint256 amount) external {
        pendingDepositFee += amount;
    }
}

contract MockExternalAccessControl is IAccessControl {
    function hasRole(bytes32, address) external pure returns (bool) {
        return false;
    }

    function getRoleAdmin(bytes32) external pure returns (bytes32) {
        return bytes32(0);
    }

    function grantRole(bytes32, address) external pure {}
    function revokeRole(bytes32, address) external pure {}
    function renounceRole(bytes32, address) external pure {}
    function supportsInterface(bytes4) external pure returns (bool) {
        return true;
    }
}

contract VaultHandler is Test {
    Vault public immutable vault;
    MockAsset public immutable asset;
    address[] public actors;

    constructor(Vault vault_, MockAsset asset_) {
        vault = vault_;
        asset = asset_;
        actors.push(address(0xA11CE));
        actors.push(address(0xB0B));
        actors.push(address(0xCA11));
    }

    function actorAt(uint256 seed) public view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actorAt(actorSeed);
        amount = bound(amount, 1, 1e24);
        asset.mint(actor, amount);
        vm.startPrank(actor);
        asset.approve(address(vault), amount);
        vault.deposit(amount, actor);
        vm.stopPrank();
    }

    function mint(uint256 actorSeed, uint256 shares) external {
        address actor = actorAt(actorSeed);
        shares = bound(shares, 1, 1e24);
        uint256 assets = vault.previewMint(shares);
        vm.assume(assets > 0 && assets < 1e30);
        asset.mint(actor, assets);
        vm.startPrank(actor);
        asset.approve(address(vault), assets);
        vault.mint(shares, actor);
        vm.stopPrank();
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = actorAt(actorSeed);
        uint256 maxAssets = vault.maxWithdraw(actor);
        if (maxAssets == 0) return;
        amount = bound(amount, 1, maxAssets);
        vm.prank(actor);
        vault.withdraw(amount, actor, actor);
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = actorAt(actorSeed);
        uint256 maxShares = vault.maxRedeem(actor);
        if (maxShares == 0) return;
        shares = bound(shares, 1, maxShares);
        vm.prank(actor);
        vault.redeem(shares, actor, actor);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 shares) external {
        address from = actorAt(fromSeed);
        address to = actorAt(toSeed);
        uint256 balance = vault.balanceOf(from);
        if (balance == 0 || from == to) return;
        shares = bound(shares, 1, balance);
        vm.prank(from);
        vault.transfer(to, shares);
    }

    function donateYield(uint256 amount) external {
        amount = bound(amount, 1, 1e22);
        asset.addYield(address(vault), amount);
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }
}

contract VaultInvariantTest is Test {
    bytes32 internal constant CONNECTOR_NAME = bytes32("MOCK");

    Vault internal vault;
    MockAsset internal asset;
    MockConnector internal connector;
    MockConnectorRegistry internal registry;
    MockFeeDispatcher internal feeDispatcher;
    VaultHandler internal handler;

    function setUp() external {
        asset = new MockAsset();
        connector = new MockConnector();
        registry = new MockConnectorRegistry(CONNECTOR_NAME, address(connector));
        feeDispatcher = new MockFeeDispatcher();

        vault = new Vault(address(new MockExternalAccessControl()), address(this));

        Vault.InitializationParams memory initParams = Vault.InitializationParams({
            asset_: asset,
            name_: "Kiln Mock Vault",
            symbol_: "kmMOCK",
            transferable_: true,
            connectorRegistry_: registry,
            connectorName_: CONNECTOR_NAME,
            depositFee_: 0,
            rewardFee_: 0,
            initialDefaultAdmin_: address(this),
            initialFeeManager_: address(this),
            initialSanctionsManager_: address(this),
            initialClaimManager_: address(this),
            initialPauser_: address(this),
            initialUnpauser_: address(this),
            initialDelay_: 0,
            offset_: 0,
            minTotalSupply_: 0
        });

        IFeeDispatcher.FeeRecipient[] memory recipients = new IFeeDispatcher.FeeRecipient[](0);
        Vault.UpgradeParams memory upgradeParams = Vault.UpgradeParams({
            recipients_: recipients,
            feeDispatcher_: address(feeDispatcher),
            additionalRewardsStrategy_: Vault.AdditionalRewardsStrategy.None,
            blockList_: BlockList(address(0)),
            pendingDepositFee_: 0,
            pendingRewardFee_: 0,
            connectorRegistry_: registry,
            initialFeeCollector_: address(this)
        });

        vault.initialize(initParams, upgradeParams);

        handler = new VaultHandler(vault, asset);
        targetContract(address(handler));
    }

    function invariant_totalAssetsEqualsVaultBalancePlusManaged() external view {
        assertEq(vault.totalAssets(), asset.balanceOf(address(vault)) + asset.managed(address(vault)));
    }

    function invariant_shareSupplyEqualsTrackedBalances() external view {
        uint256 tracked;
        uint256 length = handler.actorsLength();
        for (uint256 i; i < length; i++) {
            tracked += vault.balanceOf(handler.actorAt(i));
        }
        tracked += vault.balanceOf(address(vault));
        assertEq(vault.totalSupply(), tracked);
    }

    function invariant_maxRedeemAndWithdrawAreBoundedByBalances() external view {
        uint256 length = handler.actorsLength();
        for (uint256 i; i < length; i++) {
            address actor = handler.actorAt(i);
            assertLe(vault.maxRedeem(actor), vault.balanceOf(actor));
            assertLe(vault.maxWithdraw(actor), vault.totalAssets());
        }
    }

    function invariant_previewRoundTripsDoNotOverpromise() external view {
        uint256 supply = vault.totalSupply();
        if (supply == 0) return;
        uint256 length = handler.actorsLength();
        for (uint256 i; i < length; i++) {
            address actor = handler.actorAt(i);
            uint256 shares = vault.balanceOf(actor);
            if (shares == 0) continue;
            uint256 assets = vault.previewRedeem(shares);
            assertLe(vault.previewWithdraw(assets), shares);
        }
    }
}
