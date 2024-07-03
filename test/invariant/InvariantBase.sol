// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Test } from 'forge-std/Test.sol';

contract InvariantBase is Test {
    bytes4[] internal selectors;

    // Should be called from setup, numbers means weights to each function
    function _setupSelectors(address target, bytes4[] memory newSelectors, uint256[] memory numbers) internal {
        for (uint256 i = 0; i < newSelectors.length; i++) {
            for (uint256 j = 0; j < numbers[i]; j++) {
                selectors.push(newSelectors[i]);
            }
        }

        targetSelector(FuzzSelector({ addr: target, selectors: selectors }));
    }
}
