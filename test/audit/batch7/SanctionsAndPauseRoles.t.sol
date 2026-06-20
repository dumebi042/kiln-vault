// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";
import {BlockList} from "../../../src/BlockList.sol";
import {DeployHelper} from "./mocks/DeployHelper.sol";

contract SanctionsAndPauseRolesTest is Test {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR");

    BlockList public blockList;
    address admin = address(0x100);
    address operator = address(0x200);
    address attacker = address(0x300);
    address user = address(0x400);

    function setUp() public {
        blockList = DeployHelper.deployBlockList(admin, operator);
    }

    function test_operatorCanAddToBlocklist() public {
        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        blockList.addToBlockList(users);
        assertTrue(blockList.isBlockedByInternalList(user));
    }

    function test_operatorCanRemoveFromBlocklist() public {
        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(operator);
        blockList.addToBlockList(users);
        vm.prank(operator);
        blockList.removeFromBlockList(users);
        assertFalse(blockList.isBlockedByInternalList(user));
    }

    function test_nonOperatorCannotAdd() public {
        address[] memory users = new address[](1);
        users[0] = user;
        vm.prank(attacker);
        vm.expectRevert();
        blockList.addToBlockList(users);
    }

    function test_adminCanGrantOperator() public {
        vm.prank(admin);
        blockList.grantRole(OPERATOR_ROLE, attacker);
        assertTrue(blockList.hasRole(OPERATOR_ROLE, attacker));
    }
}
