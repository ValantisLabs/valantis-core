// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { UniversalPoolFactory } from '../../src/pools/factories/UniversalPoolFactory.sol';

contract UniversalPoolFactoryDeployer {
    function deployUniversalPoolFactory() public returns (UniversalPoolFactory factory) {
        factory = new UniversalPoolFactory();
    }
}
