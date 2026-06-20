// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";
import {SimpleProxy} from "../../../src/test-helpers/SimpleProxy.sol";

contract ExternalAccessControlAuditTest is Test {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER");

    ExternalAccessControl public eac;
    address admin = address(0x100);
    address spender = address(0x200);
    address attacker = address(0x400);

    function setUp() public {
        eac = DeployHelper.deployEac(admin, SPENDER_ROLE, spender, 0);
    }

    function test_initializeSetsSpender() public {
        assertTrue(eac.hasRole(SPENDER_ROLE, spender));
    }

    function test_cannotReinitialize() public {
        vm.expectRevert();
        eac.initialize(
            ExternalAccessControl.InitializationParams({
                initialDefaultAdmin_: admin,
                initialRole_: ExternalAccessControl.InitialRole({
                    role: SPENDER_ROLE,
                    account: spender
                }),
                initialDelay_: 0
            })
        );
    }

    function test_spenderCannotGrantRole() public {
        vm.prank(spender);
        vm.expectRevert();
        eac.grantRole(SPENDER_ROLE, attacker);
    }

    function test_defaultAdminCanGrant() public {
        vm.prank(admin);
        eac.grantRole(SPENDER_ROLE, attacker);
        assertTrue(eac.hasRole(SPENDER_ROLE, attacker));
    }

    function test_roleRevocationImmediate() public {
        vm.prank(admin);
        eac.revokeRole(SPENDER_ROLE, spender);
        assertFalse(eac.hasRole(SPENDER_ROLE, spender));
    }
}
