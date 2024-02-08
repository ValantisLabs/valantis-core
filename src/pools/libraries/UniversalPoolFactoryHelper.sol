// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { UniversalPool } from '../UniversalPool.sol';

library UniversalPoolFactoryHelper {
    function getContractBytecode() external pure returns (bytes memory) {
        return type(UniversalPool).creationCode;
    }
}
