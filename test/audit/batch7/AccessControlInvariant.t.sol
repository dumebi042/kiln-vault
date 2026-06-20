// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";

contract AccessControlInvariantTest is StdInvariant, Test {
    ACHandler handler;
    function setUp() public {
        handler = new ACHandler();
        targetContract(address(handler));
    }

    function invariant_onlyAdminCanGrant() external view {
        assertTrue(handler.g_adminCanGrant());
        assertFalse(handler.g_nonAdminCouldGrant());
    }

    function invariant_revocationImmediate() external view {
        assertFalse(handler.g_revokedStillHasRole());
    }
}

contract ACHandler is Test {
    ExternalAccessControl public eac;
    address admin = address(0x100);
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER");

    bool private _adminCanGrant;
    bool private _nonAdminCouldGrant;
    bool private _revokedStillHasRole;

    constructor() {
        eac = DeployHelper.deployEac(admin, SPENDER_ROLE, address(0), 0);
    }

    function g_adminCanGrant() external view returns (bool) {
        return _adminCanGrant;
    }
    function g_nonAdminCouldGrant() external view returns (bool) {
        return _nonAdminCouldGrant;
    }
    function g_revokedStillHasRole() external view returns (bool) {
        return _revokedStillHasRole;
    }

    function grantAsAdmin(address user) public {
        vm.assume(user != address(0) && user != admin);
        vm.prank(admin);
        eac.grantRole(SPENDER_ROLE, user);
        _adminCanGrant = eac.hasRole(SPENDER_ROLE, user);
    }

    function grantAsNonAdmin(address caller, address user) public {
        vm.assume(caller != admin && caller != address(0));
        vm.assume(user != address(0));
        vm.prank(caller);
        vm.expectRevert();
        eac.grantRole(SPENDER_ROLE, user);
        _nonAdminCouldGrant = eac.hasRole(SPENDER_ROLE, user);
    }

    function revokeRole(address user) public {
        vm.assume(user != address(0));
        vm.prank(admin);
        eac.revokeRole(SPENDER_ROLE, user);
        _revokedStillHasRole = eac.hasRole(SPENDER_ROLE, user);
    }
}
