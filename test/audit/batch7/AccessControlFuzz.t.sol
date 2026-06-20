// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";

contract AccessControlFuzzTest is Test {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER");

    ExternalAccessControl public eac;
    address admin = address(0x100);

    function setUp() public {
        eac = DeployHelper.deployEac(admin, SPENDER_ROLE, address(0), 0);
    }

    function testFuzz_grantThenRevoke(address user) public {
        vm.assume(user != address(0) && user != admin);
        vm.prank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        assertTrue(eac.hasRole(SPENDER_ROLE, user));
        vm.prank(admin);
        eac.revokeRole(SPENDER_ROLE, user);
        assertFalse(eac.hasRole(SPENDER_ROLE, user));
    }

    function testFuzz_doubleGrantIsIdempotent(address user) public {
        vm.assume(user != address(0) && user != admin);
        vm.startPrank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        eac.grantRole(SPENDER_ROLE, user);
        assertTrue(eac.hasRole(SPENDER_ROLE, user));
        vm.stopPrank();
    }

    function testFuzz_unauthorizedCannotGrant(address caller, address user) public {
        vm.assume(caller != admin && caller != address(0));
        vm.assume(user != address(0));
        vm.prank(caller);
        vm.expectRevert();
        eac.grantRole(SPENDER_ROLE, user);
    }

    function testFuzz_unauthorizedCannotRevoke(address caller, address user) public {
        vm.assume(caller != admin && caller != address(0));
        vm.assume(user != address(0) && user != admin);
        vm.prank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        vm.prank(caller);
        vm.expectRevert();
        eac.revokeRole(SPENDER_ROLE, user);
    }
}
