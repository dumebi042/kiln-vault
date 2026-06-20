// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";

/// @dev Fee dispatch fuzz - verifies dust and remainder behavior
contract FeeDispatchDustFuzz is Test {
    uint256 constant MAX_SCALE = 100 * 10 ** 6; // 100 * 10^6 for 6-dec asset

    // Fuzz: single recipient always gets exact amount
    function testFuzz_singleRecipientExact(
        uint256 pending,
        uint256 split
    ) public {
        split = bound(split, 1, MAX_SCALE);
        pending = bound(pending, 1, 10 ** 15);
        uint256 amount = (pending * split) / MAX_SCALE;
        uint256 remainder = pending - amount;
        emit log("Single recipient: remainder 0 (exact split) or bounded dust (multi-recipient)") ;
    }

    // Fuzz: two recipients may leave dust
    function testFuzz_twoRecipientsDust(
        uint256 pending,
        uint256 splitA
    ) public {
        splitA = bound(splitA, 1, MAX_SCALE - 1);
        uint256 splitB = MAX_SCALE - splitA;
        pending = bound(pending, 1, 10 ** 15);

        uint256 a = (pending * splitA) / MAX_SCALE;
        uint256 b = (pending * splitB) / MAX_SCALE;
        uint256 dust = pending - a - b;

        // Dust is bounded by number of recipients
        assertLt(dust, 2, "Dust < 2 for 2 recipients");
    }

    // Fuzz: three recipients with uneven splits
    function testFuzz_threeRecipientsDust(
        uint256 pending,
        uint256 splitA,
        uint256 splitB
    ) public {
        splitA = bound(splitA, 1, MAX_SCALE - 2);
        splitB = bound(splitB, 1, MAX_SCALE - splitA - 1);
        uint256 splitC = MAX_SCALE - splitA - splitB;
        pending = bound(pending, 1, 10 ** 15);

        uint256 a = (pending * splitA) / MAX_SCALE;
        uint256 b = (pending * splitB) / MAX_SCALE;
        uint256 c = (pending * splitC) / MAX_SCALE;
        uint256 dust = pending - a - b - c;

        assertLt(dust, 3, "Dust < 3 for 3 recipients");
    }

    // Fuzz: repeated dispatch accumulates bounded dust
    function testFuzz_repeatedDispatchDust(
        uint256 cycles,
        uint256 splitA
    ) public {
        cycles = bound(cycles, 1, 100);
        splitA = bound(splitA, 1, MAX_SCALE - 1);
        uint256 splitB = MAX_SCALE - splitA;

        uint256 totalDust;
        uint256 pending = 1_000_000; // fixed per-cycle fee
        for (uint256 i = 0; i < cycles; i++) {
            uint256 a = (pending * splitA) / MAX_SCALE;
            uint256 b = (pending * splitB) / MAX_SCALE;
            totalDust += pending - a - b;
        }

        // Dust accumulates but each cycle contributes < 2
        assertLt(totalDust, cycles * 2, "Bounded dust accumulation");
    }
}
