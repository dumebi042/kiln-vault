// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;
import {Test} from "forge-std/Test.sol";

/// @notice Connector accounting fuzz - verifies split remainder behavior
contract ConnectorFeeFuzzTest is Test {
    uint256 constant MAX_SCALE = 100 * 10 ** 6;

    function testFuzz_splitRounding(uint256 pending, uint256 splitA) public {
        splitA = bound(splitA, 1, MAX_SCALE - 1);
        uint256 splitB = MAX_SCALE - splitA;
        pending = bound(pending, 1, 10 ** 15);

        uint256 a = (pending * splitA) / MAX_SCALE;
        uint256 b = (pending * splitB) / MAX_SCALE;
        uint256 dust = pending - a - b;

        assertLt(dust, 2, "2-recipient dust < 2");
    }
}
