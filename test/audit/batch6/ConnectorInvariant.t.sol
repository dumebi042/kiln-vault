// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {ERC4626Mock, AngleVaultMock} from "./mocks/ERC4626Mock.sol";
import {AavePoolMock} from "./mocks/AaveMock.sol";

struct ConnectorGhosts {
    uint256 grossDeposits;
    uint256 grossWithdrawals;
    uint256 externalYield;
    uint256 externalLoss;
    uint256 immediateLiquidity;
}

contract Mock20 is IERC20 {
    string public n;
    string public s;
    uint8 public immutable d;
    uint256 public ts;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    constructor(string memory _n, string memory _s, uint8 _d) {
        n = _n;
        s = _s;
        d = _d;
    }
    function name() external view returns (string memory) {
        return n;
    }
    function symbol() external view returns (string memory) {
        return s;
    }
    function decimals() external view returns (uint8) {
        return d;
    }
    function totalSupply() external view returns (uint256) {
        return ts;
    }
    function mint(address to, uint256 amt) external {
        ts += amt;
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
}

contract CometInvMock {
    IERC20 public baseToken;
    mapping(address => uint256) public basePrincipal;
    uint256 public accruedPerSecond;
    bool public supplyPaused;
    bool public withdrawPaused;
    constructor(IERC20 _base) {
        baseToken = _base;
    }
    function setSupplyPause(bool v) external {
        supplyPaused = v;
    }
    function setWithdrawPause(bool v) external {
        withdrawPaused = v;
    }
    function setAccruedPerSecond(uint256 v) external {
        accruedPerSecond = v;
    }
    function supply(IERC20 a, uint256 amt) external {
        require(!supplyPaused, "paused");
        require(a == baseToken, "wrong asset");
        baseToken.transferFrom(msg.sender, address(this), amt);
        basePrincipal[msg.sender] += amt;
    }
    function withdraw(IERC20 a, uint256 amt) external {
        require(!withdrawPaused, "paused");
        require(a == baseToken, "wrong asset");
        uint256 bal = balanceOf(msg.sender);
        uint256 actual = amt < bal ? amt : bal;
        uint256 principalAmt = (actual * 1e18) / (1e18 + accruedPerSecond);
        if (principalAmt > basePrincipal[msg.sender])
            principalAmt = basePrincipal[msg.sender];
        basePrincipal[msg.sender] -= principalAmt;
        baseToken.transfer(msg.sender, actual);
    }
    function balanceOf(address user) public view returns (uint256) {
        return (basePrincipal[user] * (1e18 + accruedPerSecond)) / 1e18;
    }
    function isSupplyPaused() external view returns (bool) {
        return supplyPaused;
    }
    function isWithdrawPaused() external view returns (bool) {
        return withdrawPaused;
    }
}

contract MetaMorphoConn_UT is IConnector {
    using SafeERC20 for IERC20;
    address public immutable vault_;
    constructor(address _v) {
        vault_ = _v;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return
            ERC4626Mock(vault_).previewRedeem(
                ERC4626Mock(vault_).balanceOf(address(this))
            );
    }
    function deposit(IERC20 asset, uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(vault_, amount);
        ERC4626Mock(vault_).deposit(amount, address(this));
    }
    function withdraw(IERC20 asset, uint256 amount) external {
        ERC4626Mock(vault_).withdraw(amount, address(this), address(this));
        asset.safeTransfer(msg.sender, amount);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        return ERC4626Mock(vault_).maxDeposit(address(this));
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return ERC4626Mock(vault_).maxWithdraw(address(this));
    }
}

contract AaveConn_UT is IConnector {
    using SafeERC20 for IERC20;
    address public immutable aave_;
    constructor(address _a) {
        aave_ = _a;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return AavePoolMock(aave_).balanceOf(address(this));
    }
    function deposit(IERC20 a, uint256 amount) external {
        require(
            address(a) == address(AavePoolMock(aave_).asset()),
            "wrong asset"
        );
        a.safeTransferFrom(msg.sender, address(this), amount);
        a.forceApprove(aave_, amount);
        AavePoolMock(aave_).supply(address(a), amount, address(this), 0);
    }
    function withdraw(IERC20 a, uint256 amount) external {
        AavePoolMock(aave_).withdraw(address(a), amount, address(this));
        a.safeTransfer(msg.sender, amount);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20 a) external view returns (uint256) {
        return AavePoolMock(aave_).balanceOf(address(this));
    }
}

contract CompoundConn_UT is IConnector {
    using SafeERC20 for IERC20;
    address public immutable market_;
    constructor(address _m) {
        market_ = _m;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return CometInvMock(market_).balanceOf(address(this));
    }
    function deposit(IERC20 a, uint256 amount) external {
        a.safeTransferFrom(msg.sender, address(this), amount);
        a.forceApprove(market_, amount);
        CometInvMock(market_).supply(a, amount);
    }
    function withdraw(IERC20 a, uint256 amount) external {
        CometInvMock(market_).withdraw(a, amount);
        a.safeTransfer(msg.sender, amount);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        return CometInvMock(market_).isSupplyPaused() ? 0 : type(uint256).max;
    }
    function maxWithdraw(IERC20 a) external view returns (uint256) {
        return
            CometInvMock(market_).isWithdrawPaused()
                ? 0
                : CometInvMock(market_).balanceOf(address(this));
    }
}

contract SDAIConn_UT is IConnector {
    using SafeERC20 for IERC20;
    address public immutable sDAI_;
    constructor(address _s) {
        sDAI_ = _s;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return
            ERC4626Mock(sDAI_).previewRedeem(
                ERC4626Mock(sDAI_).balanceOf(address(this))
            );
    }
    function deposit(IERC20 asset, uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(sDAI_, amount);
        ERC4626Mock(sDAI_).deposit(amount, address(this));
    }
    function withdraw(IERC20 asset, uint256 amount) external {
        ERC4626Mock(sDAI_).withdraw(amount, address(this), address(this));
        asset.safeTransfer(msg.sender, amount);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        return ERC4626Mock(sDAI_).maxDeposit(address(this));
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return ERC4626Mock(sDAI_).maxWithdraw(address(this));
    }
}

contract AngleConn_UT is IConnector {
    using SafeERC20 for IERC20;
    address public immutable vault_;
    constructor(address _v) {
        vault_ = _v;
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return
            AngleVaultMock(vault_).previewRedeem(
                AngleVaultMock(vault_).balanceOf(address(this))
            );
    }
    function deposit(IERC20 asset, uint256 amount) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        asset.forceApprove(vault_, amount);
        AngleVaultMock(vault_).deposit(amount, address(this));
    }
    function withdraw(IERC20 asset, uint256 amount) external {
        AngleVaultMock(vault_).withdraw(amount, address(this), address(this));
        asset.safeTransfer(msg.sender, amount);
    }
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        if (AngleVaultMock(vault_).paused() == 1) return 0;
        return AngleVaultMock(vault_).maxDeposit(address(this));
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        if (AngleVaultMock(vault_).paused() == 1) return 0;
        return AngleVaultMock(vault_).maxWithdraw(address(this));
    }
}

/// MetaMorpho Handler
contract MetaMorphoHandler is Test {
    using SafeERC20 for IERC20;
    IERC20 public asset;
    IConnector public connector;
    ERC4626Mock public vault;
    ConnectorGhosts ghosts;
    constructor() {
        asset = IERC20(address(new Mock20("USDC", "USDC", 6)));
        vault = new ERC4626Mock(asset, "mmUSDC", "mmUSDC", 6);
        connector = new MetaMorphoConn_UT(address(vault));
    }
    function ghost_reportedVsClaimable()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            vault.previewRedeem(vault.balanceOf(address(connector)))
        );
    }
    function ghost_maxWithdrawVsLiquidity()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.maxWithdraw(IERC20(address(asset))),
            vault.maxWithdraw(address(connector))
        );
    }
    function ghost_conservation()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            ghosts.grossWithdrawals,
            ghosts.externalYield,
            ghosts.externalLoss,
            ghosts.grossDeposits
        );
    }
    function ghost_grossDeposits() external view returns (uint256) {
        return ghosts.grossDeposits;
    }
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 * 10 ** 6);
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);
        ghosts.grossDeposits += amount;
    }
    function withdraw(uint256 amount) public {
        uint256 ta = connector.totalAssets(IERC20(address(asset)));
        if (ta == 0) return;
        amount = bound(amount, 1, ta);
        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        ghosts.grossWithdrawals += asset.balanceOf(address(this)) - pre;
    }
    function accrueYield(uint256 rate) public {
        uint256 _newRate = bound(rate, 1e18, 2e18); if (_newRate > vault.exchangeRate()) vault.setExchangeRate(_newRate);
    }
    function simulateLoss(uint256 lossPct) private {
        lossPct = bound(lossPct, 1, 50);
        if (vault.balanceOf(address(connector)) == 0) return;
        uint256 shares = vault.balanceOf(address(connector));
        uint256 oldRate = vault.exchangeRate();
        uint256 oldVal = (shares * oldRate) / 1e18;
        vault.setExchangeRate(oldRate - ((oldRate * lossPct) / 100));
        uint256 newVal = (shares * vault.exchangeRate()) / 1e18;
        ghosts.externalLoss += (oldVal > newVal ? oldVal - newVal : 0);
    }
    function setLiquidityCap(uint256 cap) public {
        vault.setMaxWithdrawCap(bound(cap, 0, 1_000_000 * 10 ** 6));
    }
}

/// Aave Handler
contract AaveHandler is Test {
    using SafeERC20 for IERC20;
    IERC20 public asset;
    IConnector public connector;
    AavePoolMock public pool;
    ConnectorGhosts ghosts;
    constructor() {
        asset = IERC20(address(new Mock20("USDC", "USDC", 6)));
        pool = new AavePoolMock(asset);
        connector = new AaveConn_UT(address(pool));
    }
    function ghost_reportedVsClaimable()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            pool.balanceOf(address(connector))
        );
    }
    function ghost_maxWithdrawVsLiquidity()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.maxWithdraw(IERC20(address(asset))),
            pool.balanceOf(address(connector))
        );
    }
    function ghost_conservation()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            ghosts.grossWithdrawals,
            ghosts.externalYield,
            ghosts.externalLoss,
            ghosts.grossDeposits
        );
    }
    function ghost_grossDeposits() external view returns (uint256) {
        return ghosts.grossDeposits;
    }
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 * 10 ** 6);
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);
        ghosts.grossDeposits += amount;
    }
    function withdraw(uint256 amount) public {
        uint256 ta = connector.totalAssets(IERC20(address(asset)));
        if (ta == 0) return;
        amount = bound(amount, 1, ta);
        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        ghosts.grossWithdrawals += asset.balanceOf(address(this)) - pre;
    }
    function accrueYield(uint256 inc) public {
        pool.setIndex(pool.liquidityIndex() + bound(inc, 1e22, 1e28));
    }
    function simulateLoss(uint256 lossPct) private {
        lossPct = bound(lossPct, 1, 50);
        if (pool.scaledBalance(address(connector)) == 0) return;
        uint256 shares = pool.scaledBalance(address(connector));
        uint256 oldIdx = pool.liquidityIndex();
        uint256 oldVal = (shares * oldIdx) / 1e27;
        pool.setIndex(oldIdx - ((oldIdx * lossPct) / 100));
        uint256 newVal = (shares * pool.liquidityIndex()) / 1e27;
        ghosts.externalLoss += (oldVal > newVal ? oldVal - newVal : 0);
    }
}

/// Compound Handler
contract CompoundHandler is Test {
    using SafeERC20 for IERC20;
    IERC20 public asset;
    IConnector public connector;
    CometInvMock public comet;
    ConnectorGhosts ghosts;
    constructor() {
        asset = IERC20(address(new Mock20("USDC", "USDC", 6)));
        comet = new CometInvMock(asset);
        connector = new CompoundConn_UT(address(comet));
    }
    function ghost_reportedVsClaimable()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            comet.balanceOf(address(connector))
        );
    }
    function ghost_maxWithdrawVsLiquidity()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.maxWithdraw(IERC20(address(asset))),
            comet.isWithdrawPaused() ? 0 : comet.balanceOf(address(connector))
        );
    }
    function ghost_conservation()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            ghosts.grossWithdrawals,
            ghosts.externalYield,
            ghosts.externalLoss,
            ghosts.grossDeposits
        );
    }
    function ghost_grossDeposits() external view returns (uint256) {
        return ghosts.grossDeposits;
    }
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 * 10 ** 6);
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);
        ghosts.grossDeposits += amount;
    }
    function withdraw(uint256 amount) public {
        uint256 ta = connector.totalAssets(IERC20(address(asset)));
        if (ta == 0) return;
        amount = bound(amount, 1, ta);
        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        ghosts.grossWithdrawals += asset.balanceOf(address(this)) - pre;
    }
    function accrueYield(uint256 rate) public {
        uint256 _cmpRate = bound(rate, 1e14, 1e18); if (_cmpRate > comet.accruedPerSecond()) comet.setAccruedPerSecond(_cmpRate);
    }
    function simulateLoss(uint256 lossPct) private {
        lossPct = bound(lossPct, 1, 50);
        uint256 principal = comet.basePrincipal(address(connector));
        if (principal == 0) return;
        uint256 oldRate = comet.accruedPerSecond();
        uint256 oldVal = (principal * (1e18 + oldRate)) / 1e18;
        comet.setAccruedPerSecond(oldRate > 0 ? oldRate / 2 : 0);
        uint256 newVal = (principal * (1e18 + comet.accruedPerSecond())) / 1e18;
        ghosts.externalLoss += (oldVal > newVal ? oldVal - newVal : 0);
    }
    function pauseSupply() public {
        comet.setSupplyPause(true);
    }
    function pauseWithdraw() public {
        comet.setWithdrawPause(true);
    }
}

/// sDAI Handler
contract SDAIHandler is Test {
    using SafeERC20 for IERC20;
    IERC20 public asset;
    IConnector public connector;
    ERC4626Mock public vault;
    ConnectorGhosts ghosts;
    constructor() {
        asset = IERC20(address(new Mock20("DAI", "DAI", 18)));
        vault = new ERC4626Mock(asset, "sDAI", "sDAI", 18);
        connector = new SDAIConn_UT(address(vault));
    }
    function ghost_reportedVsClaimable()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            vault.previewRedeem(vault.balanceOf(address(connector)))
        );
    }
    function ghost_maxWithdrawVsLiquidity()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.maxWithdraw(IERC20(address(asset))),
            vault.maxWithdraw(address(connector))
        );
    }
    function ghost_conservation()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            ghosts.grossWithdrawals,
            ghosts.externalYield,
            ghosts.externalLoss,
            ghosts.grossDeposits
        );
    }
    function ghost_grossDeposits() external view returns (uint256) {
        return ghosts.grossDeposits;
    }
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 * 10 ** 18);
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);
        ghosts.grossDeposits += amount;
    }
    function withdraw(uint256 amount) public {
        uint256 ta = connector.totalAssets(IERC20(address(asset)));
        if (ta == 0) return;
        amount = bound(amount, 1, ta);
        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        ghosts.grossWithdrawals += asset.balanceOf(address(this)) - pre;
    }
    function accrueYield(uint256 rate) public {
        uint256 _newRate = bound(rate, 1e18, 2e18); if (_newRate > vault.exchangeRate()) vault.setExchangeRate(_newRate);
    }
    function simulateLoss(uint256 lossPct) private {
        lossPct = bound(lossPct, 1, 50);
        if (vault.balanceOf(address(connector)) == 0) return;
        uint256 shares = vault.balanceOf(address(connector));
        uint256 oldRate = vault.exchangeRate();
        uint256 oldVal = (shares * oldRate) / 1e18;
        vault.setExchangeRate(oldRate - ((oldRate * lossPct) / 100));
        uint256 newVal = (shares * vault.exchangeRate()) / 1e18;
        ghosts.externalLoss += (oldVal > newVal ? oldVal - newVal : 0);
    }
    function setLiquidityCap(uint256 cap) public {
        vault.setMaxWithdrawCap(bound(cap, 0, 1_000_000 * 10 ** 18));
    }
}

/// Angle Handler
contract AngleHandler is Test {
    using SafeERC20 for IERC20;
    IERC20 public asset;
    IConnector public connector;
    AngleVaultMock public vault;
    ConnectorGhosts ghosts;
    constructor() {
        asset = IERC20(address(new Mock20("stEUR", "stEUR", 18)));
        vault = new AngleVaultMock(asset, "stEUR", "stEUR", 18);
        Mock20(address(asset)).mint(address(vault), 1_000_000 * 10 ** 18);
        connector = new AngleConn_UT(address(vault));
    }
    function ghost_reportedVsClaimable()
        external
        view
        returns (uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            vault.previewRedeem(vault.balanceOf(address(connector)))
        );
    }
    function ghost_maxWithdrawVsLiquidity()
        external
        view
        returns (uint256, uint256)
    {
        uint256 mw = connector.maxWithdraw(IERC20(address(asset)));
        uint256 liq = vault.paused() == 1
            ? 0
            : vault.maxWithdraw(address(connector));
        return (mw, liq);
    }
    function ghost_conservation()
        external
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        return (
            connector.totalAssets(IERC20(address(asset))),
            ghosts.grossWithdrawals,
            ghosts.externalYield,
            ghosts.externalLoss,
            ghosts.grossDeposits
        );
    }
    function ghost_grossDeposits() external view returns (uint256) {
        return ghosts.grossDeposits;
    }
    function deposit(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000 * 10 ** 18);
        Mock20(address(asset)).mint(address(this), amount);
        asset.approve(address(connector), amount);
        connector.deposit(IERC20(address(asset)), amount);
        ghosts.grossDeposits += amount;
    }
    function withdraw(uint256 amount) public {
        uint256 ta = connector.totalAssets(IERC20(address(asset)));
        if (ta == 0) return;
        amount = bound(amount, 1, ta);
        uint256 pre = asset.balanceOf(address(this));
        connector.withdraw(IERC20(address(asset)), amount);
        ghosts.grossWithdrawals += asset.balanceOf(address(this)) - pre;
    }
    function accrueYield(uint256 rate) public {
        uint256 _newRate = bound(rate, 1e18, 2e18); if (_newRate > vault.exchangeRate()) vault.setExchangeRate(_newRate);
    }
    function simulateLoss(uint256 lossPct) private {
        lossPct = bound(lossPct, 1, 50);
        if (vault.balanceOf(address(connector)) == 0) return;
        uint256 shares = vault.balanceOf(address(connector));
        uint256 oldRate = vault.exchangeRate();
        uint256 oldVal = (shares * oldRate) / 1e18;
        vault.setExchangeRate(oldRate - ((oldRate * lossPct) / 100));
        uint256 newVal = (shares * vault.exchangeRate()) / 1e18;
        ghosts.externalLoss += (oldVal > newVal ? oldVal - newVal : 0);
    }
    function togglePause() public {
        vault.setPaused(vault.paused() == 1 ? 0 : 1);
    }
}

// ======================================================================
// INVARIANT TEST CONTRACTS
// ======================================================================

contract MetaMorphoInvariantTest is StdInvariant, Test {
    MetaMorphoHandler handler;
    function setUp() public {
        handler = new MetaMorphoHandler();
        targetContract(address(handler));
    }

    function invariant_reportedAssetsBoundedByProtocolClaim() external view {
        (uint256 ta, uint256 claim) = handler.ghost_reportedVsClaimable();
        assertApproxEqAbs(
            ta,
            claim,
            2,
            "MetaMorpho: totalAssets == previewRedeem(balanceOf)"
        );
    }
    function invariant_maxWithdrawNeverExceedsImmediateLiquidity()
        external
        view
    {
        (uint256 mw, uint256 liq) = handler.ghost_maxWithdrawVsLiquidity();
        assertLe(mw, liq, "MetaMorpho: maxWithdraw <= vault.maxWithdraw");
    }
    function invariant_valueConserved() external view {
        (uint256 recoverable, uint256 withdrawn, , uint256 loss, ) = handler
            .ghost_conservation();
        assertGe(
            recoverable + withdrawn + loss + 100000,
            handler.ghost_grossDeposits(),
            "MetaMorpho: value+loss >= deposits"
        );
    }
}

contract AaveInvariantTest is StdInvariant, Test {
    AaveHandler handler;
    function setUp() public {
        handler = new AaveHandler();
        targetContract(address(handler));
    }

    function invariant_reportedAssetsBoundedByProtocolClaim() external view {
        (uint256 ta, uint256 claim) = handler.ghost_reportedVsClaimable();
        assertEq(ta, claim, "Aave: totalAssets == aToken.balanceOf");
    }
    function invariant_maxWithdrawNeverExceedsImmediateLiquidity()
        external
        view
    {
        (uint256 mw, uint256 liq) = handler.ghost_maxWithdrawVsLiquidity();
        assertLe(mw, liq, "Aave: maxWithdraw <= aToken.balanceOf");
    }
    function invariant_valueConserved() external view {
        (uint256 recoverable, uint256 withdrawn, , uint256 loss, ) = handler
            .ghost_conservation();
        assertGe(
            recoverable + withdrawn + loss + 100000,
            handler.ghost_grossDeposits(),
            "Aave: value+loss >= deposits"
        );
    }
}

contract CompoundInvariantTest is StdInvariant, Test {
    CompoundHandler handler;
    function setUp() public {
        handler = new CompoundHandler();
        targetContract(address(handler));
    }

    function invariant_reportedAssetsBoundedByProtocolClaim() external view {
        (uint256 ta, uint256 claim) = handler.ghost_reportedVsClaimable();
        assertEq(ta, claim, "Compound: totalAssets == comet.balanceOf");
    }
    function invariant_maxWithdrawNeverExceedsImmediateLiquidity()
        external
        view
    {
        (uint256 mw, uint256 liq) = handler.ghost_maxWithdrawVsLiquidity();
        assertLe(mw, liq, "Compound: maxWithdraw <= comet.balanceOf");
    }
    function invariant_valueConserved() external view {
        (uint256 recoverable, uint256 withdrawn, , uint256 loss, ) = handler
            .ghost_conservation();
        assertGe(
            recoverable + withdrawn + loss + 100000,
            handler.ghost_grossDeposits(),
            "Compound: value+loss >= deposits"
        );
    }
}

contract SDAIInvariantTest is StdInvariant, Test {
    SDAIHandler handler;
    function setUp() public {
        handler = new SDAIHandler();
        targetContract(address(handler));
    }

    function invariant_reportedAssetsBoundedByProtocolClaim() external view {
        (uint256 ta, uint256 claim) = handler.ghost_reportedVsClaimable();
        assertApproxEqAbs(
            ta,
            claim,
            2,
            "sDAI: totalAssets == previewRedeem(balanceOf)"
        );
    }
    function invariant_maxWithdrawNeverExceedsImmediateLiquidity()
        external
        view
    {
        (uint256 mw, uint256 liq) = handler.ghost_maxWithdrawVsLiquidity();
        assertLe(mw, liq, "sDAI: maxWithdraw <= vault.maxWithdraw");
    }
    function invariant_valueConserved() external view {
        (uint256 recoverable, uint256 withdrawn, , uint256 loss, ) = handler
            .ghost_conservation();
        assertGe(
            recoverable + withdrawn + loss + 100000,
            handler.ghost_grossDeposits(),
            "sDAI: value+loss >= deposits"
        );
    }
}

contract AngleInvariantTest is StdInvariant, Test {
    AngleHandler handler;
    function setUp() public {
        handler = new AngleHandler();
        targetContract(address(handler));
    }

    function invariant_reportedAssetsBoundedByProtocolClaim() external view {
        (uint256 ta, uint256 claim) = handler.ghost_reportedVsClaimable();
        assertApproxEqAbs(
            ta,
            claim,
            2,
            "Angle: totalAssets == previewRedeem(balanceOf)"
        );
    }
    function invariant_maxWithdrawNeverExceedsImmediateLiquidity()
        external
        view
    {
        (uint256 mw, uint256 liq) = handler.ghost_maxWithdrawVsLiquidity();
        assertLe(mw, liq, "Angle: maxWithdraw <= vault.maxWithdraw");
    }
    function invariant_valueConserved() external view {
        (uint256 recoverable, uint256 withdrawn, , uint256 loss, ) = handler
            .ghost_conservation();
        assertGe(
            recoverable + withdrawn + loss + 100000,
            handler.ghost_grossDeposits(),
            "Angle: value+loss >= deposits"
        );
    }
}
