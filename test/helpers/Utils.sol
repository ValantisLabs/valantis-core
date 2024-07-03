// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

library Utils {
    function getAbsoluteDiff(uint256 num0, uint256 num1) internal pure returns (uint256) {
        if (num0 > num1) {
            return num0 - num1;
        }
        return num1 - num0;
    }
}
