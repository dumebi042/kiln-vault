// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {Vault} from "../../../src/Vault.sol";
import {
    VaultUpgradeableBeacon
} from "../../../src/proxy/VaultUpgradeableBeacon.sol";

contract FactoryBeaconAuthorizationTest is Test {
    bytes32 public constant IMPLEMENTATION_MANAGER_ROLE =
        keccak256("IMPLEMENTATION_MANAGER");

    VaultUpgradeableBeacon public beacon;
    address admin = address(0x100);
    address implManager = address(0x200);
    address attacker = address(0x400);
    address pauser = address(0x500);
    address unpauser = address(0x600);

    function setUp() public {
        beacon = new VaultUpgradeableBeacon(
            address(new Vault(address(0), address(0))),
            admin,
            implManager,
            pauser,
            unpauser,
            admin,
            0
        );
    }

    function test_nonImplManagerCannotUpgrade() public {
        vm.prank(attacker);
        vm.expectRevert();
        beacon.upgradeTo(address(new Vault(address(0), address(0))));
    }

    function test_freezerCanFreeze() public {
        vm.prank(admin);
        beacon.freeze();
        assertTrue(beacon.frozen());
    }

    function test_frozenBeaconCannotUpgrade() public {
        vm.prank(admin);
        beacon.freeze();
        vm.prank(implManager);
        vm.expectRevert();
        beacon.upgradeTo(address(new Vault(address(0), address(0))));
    }

    function test_pauserCanPause() public {
        vm.prank(pauser);
        beacon.pause();
        assertTrue(beacon.paused());
    }

    function test_unpauserCanUnpause() public {
        vm.prank(pauser);
        beacon.pause();
        vm.prank(unpauser);
        beacon.unpause();
        assertFalse(beacon.paused());
    }

    function test_pauserCannotUnpause() public {
        vm.prank(pauser);
        beacon.pause();
        vm.prank(pauser);
        vm.expectRevert();
        beacon.unpause();
    }

    function test_unpauserCannotPause() public {
        vm.prank(unpauser);
        vm.expectRevert();
        beacon.pause();
    }
}
