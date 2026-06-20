// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ConnectorRegistry} from "../../../src/ConnectorRegistry.sol";
import {IConnector} from "../../../src/interfaces/IConnector.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract ConnectorRegistryRolesTest is Test {
    ConnectorRegistry public registry;
    address admin = address(this); // test contract is admin
    address connManager = address(0x200);
    address pauser = address(0x300);
    address unpauser = address(0x400);
    address freezer = address(0x500);
    address attacker = address(0x600);

    bytes32 constant NAME = "test-connector";

    function setUp() public {
        registry = new ConnectorRegistry(
            admin,
            pauser,
            unpauser,
            freezer,
            connManager,
            0
        );
        registry.add(NAME, address(new MockConnector()));
    }

    function test_connectorManagerCanAdd() public {
        vm.prank(connManager);
        registry.add("new-connector", address(new MockConnector()));
        assertTrue(registry.connectorExists("new-connector"));
    }

    function test_connectorManagerCanUpdate() public {
        vm.prank(connManager);
        registry.update(NAME, address(new MockConnector()));
    }

    function test_connectorManagerCanRemove() public {
        vm.prank(connManager);
        registry.remove(NAME);
        assertFalse(registry.connectorExists(NAME));
    }

    function test_nonManagerCannotAdd() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.add("new-connector", address(new MockConnector()));
    }

    function test_pauserCanPause() public {
        vm.prank(pauser);
        registry.pause(NAME);
        assertTrue(registry.paused(NAME));
    }

    function test_unpauserCanUnpause() public {
        vm.prank(pauser);
        registry.pause(NAME);
        vm.prank(unpauser);
        registry.unPause(NAME);
        assertFalse(registry.paused(NAME));
    }

    function test_freezerCanFreeze() public {
        vm.prank(freezer);
        registry.freeze(NAME);
        assertTrue(registry.frozen(NAME));
    }

    function test_frozenConnectorCannotBeUpdated() public {
        vm.prank(freezer);
        registry.freeze(NAME);
        vm.prank(connManager);
        vm.expectRevert();
        registry.update(NAME, address(new MockConnector()));
    }

    function test_nonFreezerCannotFreeze() public {
        vm.prank(attacker);
        vm.expectRevert();
        registry.freeze(NAME);
    }
}

contract MockConnector is IConnector {
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
    function reinvest(IERC20, IERC20, bytes calldata) external pure {}
    function maxDeposit(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
    function maxWithdraw(IERC20) external view returns (uint256) {
        return type(uint256).max;
    }
}
