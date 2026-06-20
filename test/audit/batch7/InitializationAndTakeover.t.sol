// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {ExternalAccessControl} from "../../../src/ExternalAccessControl.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";

contract InitializationAndTakeoverTest is Test {
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER");

    ExternalAccessControl public eac;
    address admin = address(0x100);
    address attacker = address(0x400);

    function setUp() public {
        eac = DeployHelper.deployEac(admin, SPENDER_ROLE, address(0), 0);
    }

    function test_initializationSetsOwner() public {
        assertTrue(eac.owner() == admin);
    }

    function test_reinitializationReverts() public {
        vm.expectRevert();
        eac.initialize(
            ExternalAccessControl.InitializationParams({
                initialDefaultAdmin_: admin,
                initialRole_: ExternalAccessControl.InitialRole({
                    role: SPENDER_ROLE,
                    account: address(0)
                }),
                initialDelay_: 0
            })
        );
    }

    function test_defaultAdminTransferDelay() public {
        ExternalAccessControl eac2 = DeployHelper.deployEac(
            admin,
            SPENDER_ROLE,
            address(0),
            7 days
        );
        (address pendingAdmin, ) = eac2.pendingDefaultAdmin();
        assertTrue(pendingAdmin == address(0));
        vm.prank(admin);
        eac2.beginDefaultAdminTransfer(attacker);
        (address pendingAdmin2, ) = eac2.pendingDefaultAdmin();
        assertTrue(pendingAdmin2 == attacker);
    }

    function test_pendingAdminCannotActBeforeAcceptance() public {
        ExternalAccessControl eac2 = DeployHelper.deployEac(
            admin,
            SPENDER_ROLE,
            address(0),
            7 days
        );
        vm.prank(admin);
        eac2.beginDefaultAdminTransfer(attacker);
        vm.prank(attacker);
        vm.expectRevert();
        eac2.grantRole(SPENDER_ROLE, address(0x500));
    }
}
