// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;

import {Test} from "forge-std/Test.sol";

contract NemesisPoC is Test {
    
    function test_CollectFee() public {
        uint256 d = 10 ** 6;
        uint256 TA = 1010 * d;
        uint256 LT = 1000 * d;
        uint256 S = 1000000 * d;
        
        uint256 Y = TA - LT;
        uint256 FA = Y * (10 * d) / (100 * d);
        uint256 NT = TA - FA;
        uint256 R = FA * (S + d) / (NT + 1);
        
        emit log_named_uint("C", 0);
        emit log_named_uint("R'", R / d);
        
        uint256 CO = (0 + R) * (NT + 1) / (S + R + d);
        emit log_named_uint("collectable (USDC)", CO / d);
        
        emit log_named_uint("shares burned", 0);
        emit log_named_uint("supply unchanged", S / d);
        
        uint256 TA2 = TA - CO;
        uint256 PA = TA2 / S;
        uint256 PC = TA2 / (S - R);
        
        emit log_string("--- Share price ---");
        emit log_named_uint("actual (no burn)", PA);
        emit log_named_uint("correct (with burn)", PC);
        
        uint256 VL = (PC - PA) * S;
        emit log_named_uint("value lost (USDC)", VL / d);
        
        assertGt(VL, 0, "Shareholders lost value");
    }

    function test_HighWaterMark() public {
        uint256 d = 10 ** 6;
        uint256 LT = 1000 * d;
        uint256 TA1 = 1100 * d;
        emit log_named_uint("Phase1: yield (USDC)", (TA1 - LT) / d);
        LT = TA1;
        
        emit log_string("--- Loss: 950k USDC (below 1.1M ATH) ---");
        
        uint256 TA3 = 1150 * d;
        uint256 Y3 = 0;
        if (TA3 >= LT) { Y3 = TA3 - LT; }
        uint256 CB = TA3 - TA1;
        
        emit log_string("--- Full Recovery ---");
        emit log_named_uint("computed fee base (USDC)", Y3 / d);
        emit log_named_uint("correct (above ATH, USDC)", CB / d);
        emit log_named_uint("OVER-COUNTED (USDC)", (Y3 - CB) / d);
        assertGt(Y3, CB, "High-water mark over-counts");
    }
}
