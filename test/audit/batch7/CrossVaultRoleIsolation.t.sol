// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";

contract CrossVaultRoleIsolationTest is Test {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER");

    ExternalAccessControl public eac;
    address admin = address(0x100);
    address userA = address(0x200);
    address userB = address(0x300);

    function setUp() public {
        eac = DeployHelper.deployEac(admin, SPENDER_ROLE, userA, 0);
    }

    function test_spenderRoleIsGlobal() public {
        assertTrue(eac.hasRole(SPENDER_ROLE, userA));
    }

    function test_userBDidNotInheritRole() public {
        assertFalse(eac.hasRole(SPENDER_ROLE, userB));
    }

    function test_globalRoleRevocation() public {
        assertTrue(eac.hasRole(SPENDER_ROLE, userA));
        vm.prank(admin);
        eac.revokeRole(SPENDER_ROLE, userA);
        assertFalse(eac.hasRole(SPENDER_ROLE, userA));
    }
}
