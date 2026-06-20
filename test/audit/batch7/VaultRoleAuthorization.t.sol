// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";

contract VaultRoleAuthorizationTest is Test {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER");
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0);

    ExternalAccessControl public eac;
    address admin = address(0x100);
    address user = address(0x300);
    address attacker = address(0x400);

    function setUp() public {
        eac = DeployHelper.deployEac(admin, SPENDER_ROLE, address(0x200), 0);
    }

    function test_adminCanGrantSpender() public {
        vm.prank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        assertTrue(eac.hasRole(SPENDER_ROLE, user));
    }

    function test_nonAdminCannotGrantSpender() public {
        vm.prank(attacker);
        vm.expectRevert();
        eac.grantRole(SPENDER_ROLE, user);
    }

    function test_adminCanRevokeSpender() public {
        vm.startPrank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        assertTrue(eac.hasRole(SPENDER_ROLE, user));
        eac.revokeRole(SPENDER_ROLE, user);
        assertFalse(eac.hasRole(SPENDER_ROLE, user));
        vm.stopPrank();
    }

    function test_allRolesAdministeredByDefaultAdmin() public {
        assertEq(eac.getRoleAdmin(SPENDER_ROLE), DEFAULT_ADMIN_ROLE);
    }

    function test_holderCanRenounceRole() public {
        vm.prank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        vm.prank(user);
        eac.renounceRole(SPENDER_ROLE, user);
        assertFalse(eac.hasRole(SPENDER_ROLE, user));
    }

    function test_defaultAdminCanTransfer() public {
        vm.prank(admin);
        eac.beginDefaultAdminTransfer(user);
        (address pending, ) = eac.pendingDefaultAdmin();
        assertTrue(pending == user);
    }

    function test_pendingAdminCanAccept() public {
        vm.prank(admin);
        eac.beginDefaultAdminTransfer(user);
        vm.warp(block.timestamp + 2 days);
        vm.roll(block.number + 1);
        vm.prank(user);
        eac.acceptDefaultAdminTransfer();
        assertTrue(eac.owner() == user);
    }
}
