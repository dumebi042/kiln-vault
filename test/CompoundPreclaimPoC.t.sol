// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

import {CompoundV3Connector} from "../src/connectors/CompoundV3Connector.sol";
import {MarketRegistry} from "../src/connectors/utils/MarketRegistry.sol";

contract PoCToken {
    string public name;
    string public symbol;
    uint8 public immutable decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockComet {
    mapping(address => uint256) public balanceOf;

    function supply(PoCToken asset, uint256 amount) external {
        asset.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(PoCToken asset, uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        asset.transfer(msg.sender, amount);
    }

    function isSupplyPaused() external pure returns (bool) {
        return false;
    }

    function isWithdrawPaused() external pure returns (bool) {
        return false;
    }
}

contract MockCometRewards {
    PoCToken public immutable comp;
    mapping(address => mapping(address => uint256)) public owed;

    constructor(PoCToken comp_) {
        comp = comp_;
    }

    function setOwed(address comet, address src, uint256 amount) external {
        owed[comet][src] = amount;
        comp.mint(address(this), amount);
    }

    function claim(address comet, address src, bool) external {
        uint256 amount = owed[comet][src];
        if (amount == 0) return;
        owed[comet][src] = 0;
        comp.transfer(src, amount);
    }
}

contract CompoundPreclaimPoCTest is Test {
    function test_anyoneCanPreclaimCompAndBrickLaterConnectorClaim() external {
        PoCToken asset = new PoCToken("USD Coin", "USDC");
        PoCToken comp = new PoCToken("Compound", "COMP");
        MockComet comet = new MockComet();
        MockCometRewards rewards = new MockCometRewards(comp);

        address[] memory assets = new address[](1);
        assets[0] = address(asset);
        address[] memory markets = new address[](1);
        markets[0] = address(comet);
        MarketRegistry registry = new MarketRegistry("CompoundV3", assets, markets);

        CompoundV3Connector connector =
            new CompoundV3Connector(address(registry), address(rewards), address(this), address(comp));

        uint256 owed = 10 ether;
        rewards.setOwed(address(comet), address(connector), owed);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        rewards.claim(address(comet), address(connector), true);
        assertEq(comp.balanceOf(address(connector)), owed, "pre-claim moved COMP into connector context");

        address[] memory recipients = new address[](1);
        recipients[0] = address(0xBEEF);
        uint256[] memory splits = new uint256[](1);
        splits[0] = 100 ether;
        bytes memory payload = abi.encode(recipients, splits);

        vm.expectRevert();
        connector.claim(IERC20(address(asset)), IERC20(address(comp)), payload);
        assertEq(comp.balanceOf(recipients[0]), 0, "claim strategy did not distribute pre-claimed COMP");
    }
}
