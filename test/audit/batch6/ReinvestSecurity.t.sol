// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.22;
import {Test} from "forge-std/Test.sol";
contract ReinvestSecurityTest is Test {
    function test_approvalRisk() public {
        emit log("Reinvest: swapTarget has unlimited reward token approval.");
        emit log(
            "Risk: if swapTarget is compromised, reward tokens can be drained."
        );
        emit log(
            "Mitigation: swapTarget is immutable, CLAIM_MANAGER is trusted role."
        );
    }
}
