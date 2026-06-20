// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ConnectorRegistry} from "../../../src/ConnectorRegistry.sol";

contract RoleAdminGraphTest is Test {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 public constant CONNECTOR_MANAGER_ROLE =
        keccak256("CONNECTOR_MANAGER");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");
    bytes32 public constant UNPAUSER_ROLE = keccak256("UNPAUSER");
    bytes32 public constant FREEZER_ROLE = keccak256("FREEZER");

    ConnectorRegistry public registry;
    address admin = address(0x100);

    function setUp() public {
        registry = new ConnectorRegistry(admin, admin, admin, admin, admin, 0);
    }

    function test_connectorRegistryAllRolesAdminByDefaultAdmin() public {
        assertEq(
            registry.getRoleAdmin(CONNECTOR_MANAGER_ROLE),
            DEFAULT_ADMIN_ROLE
        );
        assertEq(registry.getRoleAdmin(PAUSER_ROLE), DEFAULT_ADMIN_ROLE);
        assertEq(registry.getRoleAdmin(UNPAUSER_ROLE), DEFAULT_ADMIN_ROLE);
        assertEq(registry.getRoleAdmin(FREEZER_ROLE), DEFAULT_ADMIN_ROLE);
    }

    function test_connectorManagerCannotGrantOtherRoles() public {
        vm.prank(admin);
        registry.grantRole(CONNECTOR_MANAGER_ROLE, address(0x200));
        vm.prank(address(0x200));
        vm.expectRevert();
        registry.grantRole(PAUSER_ROLE, address(0x300));
    }

    function test_pauserCannotGrantUnpauser() public {
        vm.prank(admin);
        registry.grantRole(PAUSER_ROLE, address(0x200));
        vm.prank(address(0x200));
        vm.expectRevert();
        registry.grantRole(UNPAUSER_ROLE, address(0x300));
    }

    function test_noRoleCanGrantDefaultAdmin() public {
        vm.prank(admin);
        vm.expectRevert();
        registry.grantRole(DEFAULT_ADMIN_ROLE, address(0x200));
    }
}
