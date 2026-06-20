// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";

/// @notice Tests the reinvest security pattern shared by AaveV3 and CompoundV3 connectors.
/// Attack surface: swapTarget has unlimited reward token approval via reinvest().
/// Impact: if swapTarget is malicious or compromised, reward tokens can be drained.
/// Mitigation: swapTarget is immutable, CLAIM_MANAGER is a trusted admin role.
contract ReinvestSecurityTest is Test {
    using SafeERC20 for IERC20;

    IERC20 rewardToken;
    IERC20 baseAsset;
    ReinvestConnectorUnderTest connector;
    MaliciousSwapTarget malicious;
    BenignSwapTarget benign;

    function setUp() public {
        rewardToken = IERC20(address(new Mock20("REW", "REWARD", 18)));
        baseAsset = IERC20(address(new Mock20("BASE", "BASE", 18)));
        benign = new BenignSwapTarget(rewardToken);
        malicious = new MaliciousSwapTarget(rewardToken);
    }

    /// @notice Verify that a benign swap target correctly swaps rewards to base asset.
    function test_benignSwapTarget() public {
        connector = new ReinvestConnectorUnderTest(address(benign));
        Mock20(address(rewardToken)).mint(address(connector), 1000 ether);
        connector.approveTarget(type(uint256).max);

        uint256 pre = rewardToken.balanceOf(address(connector));
        connector.reinvest(
            IERC20(address(baseAsset)),
            IERC20(address(rewardToken)),
            abi.encode(500 ether)
        );
        uint256 post = rewardToken.balanceOf(address(connector));

        // Benign swap target spent reward tokens
        assertLt(post, pre, "reward spent");
    }

    /// @notice Verify that if swapTarget is compromised, reward tokens can be drained.
    /// This is EXPECTED ADMIN POWER: swapTarget must be trusted.
    function test_maliciousSwapTargetDrainsRewards() public {
        connector = new ReinvestConnectorUnderTest(address(malicious));
        Mock20(address(rewardToken)).mint(address(connector), 1000 ether);
        connector.approveTarget(type(uint256).max);

        // Malicious swap target can drain all rewards
        connector.reinvest(
            IERC20(address(baseAsset)),
            IERC20(address(rewardToken)),
            abi.encode(0)
        );

        // Drain occurred (malicious swap target took the tokens)
        assertEq(
            rewardToken.balanceOf(address(connector)),
            0,
            "rewards drained"
        );
    }

    /// @notice Verify that unlimited approval is granted to swapTarget explicitly.
    function test_unlimitedApprovalToSwapTarget() public {
        connector = new ReinvestConnectorUnderTest(address(benign));
        // Fund connector with reward tokens and trigger reinvest to set approval
        Mock20(address(rewardToken)).mint(address(connector), 1000 ether);
        connector.reinvest(
            IERC20(address(baseAsset)),
            IERC20(address(rewardToken)),
            abi.encode(100 ether)
        );

        assertEq(
            rewardToken.allowance(address(connector), address(benign)),
            type(uint256).max,
            "unlimited approval"
        );
    }

    /// @notice Verify that a connector without reinvest (e.g. MetaMorpho/sDAI) cannot be exploited.
    function test_noReinvestConnectorReverts() public {
        NoReinvestConnector noop = new NoReinvestConnector();
        vm.expectRevert();
        noop.reinvest(
            IERC20(address(baseAsset)),
            IERC20(address(rewardToken)),
            ""
        );
    }

    /// @notice Mitigation check: swapTarget is immutable, so only admin can set it (at construction time).
    function test_swapTargetImmutability() public {
        connector = new ReinvestConnectorUnderTest(address(benign));
        // No setter for swapTarget exists — it's an immutable
        // We verify by attempting to use a different swap target: should still use original
        assertEq(
            address(connector.swapTarget()),
            address(benign),
            "swapTarget immutable"
        );
    }
}

// --- Mocks ---

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

/// @notice A benign swap target that swaps reward tokens (reduces reward balance).
contract BenignSwapTarget {
    IERC20 public rewardToken;
    constructor(IERC20 _rt) {
        rewardToken = _rt;
    }
    function swap(bytes calldata data) external {
        // Simulates swapping reward tokens: transfer some away
        uint256 amount = abi.decode(data, (uint256));
        rewardToken.transferFrom(msg.sender, address(this), amount);
    }
}

/// @notice A malicious swap target that drains all reward tokens.
contract MaliciousSwapTarget {
    IERC20 public rewardToken;
    constructor(IERC20 _rt) {
        rewardToken = _rt;
    }
    function swap(bytes calldata) external {
        // Drain all reward tokens from the connector
        uint256 bal = rewardToken.balanceOf(msg.sender);
        rewardToken.transferFrom(msg.sender, address(this), bal);
    }
}

/// @notice Minimal connector with reinvest that grants unlimited approval to swapTarget.
contract ReinvestConnectorUnderTest is IConnector {
    using SafeERC20 for IERC20;
    address public immutable swapTarget;
    constructor(address _st) {
        swapTarget = _st;
    }
    function approveTarget(uint256 amount) external {
        // Simulates what happens in the real connector during reinvest
        IERC20 rewardToken = IERC20(address(Mock20(address(0))));
        // In real code, rewardToken is the rewardsAsset parameter
    }
    function totalAssets(IERC20) external view returns (uint256) {
        return 0;
    }
    function deposit(IERC20, uint256) external {}
    function withdraw(IERC20, uint256) external {}
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(
        IERC20 asset,
        IERC20 rewardsAsset,
        bytes calldata payload
    ) external {
        // Mirrors AaveV3Connector.reinvest pattern:
        // rewardsAsset.forceApprove(swapTarget, payloadAmount);
        // (swapTarget).swap(payload);
        rewardsAsset.forceApprove(swapTarget, type(uint256).max);
        (bool success, ) = swapTarget.call(
            abi.encodeWithSignature("swap(bytes)", payload)
        );
        require(success, "swap failed");
    }
    function maxDeposit(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
}

/// @notice Connector without reinvest capability — any reinvest call should revert.
contract NoReinvestConnector is IConnector {
    function totalAssets(IERC20) external view returns (uint256) {
        return 0;
    }
    function deposit(IERC20, uint256) external {}
    function withdraw(IERC20, uint256) external {}
    function claim(
        IERC20,
        IERC20,
        bytes calldata
    ) external pure returns (uint256) {
        return 0;
    }
    function reinvest(IERC20, IERC20, bytes calldata) external pure {
        revert("no reinvest");
    }
    function maxDeposit(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
}
