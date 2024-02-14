// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SovereignPoolFactory } from '../../src/pools/factories/SovereignPoolFactory.sol';

contract SovereignPoolFactoryDeployer {
    function deploySovereignPoolFactory() public returns (SovereignPoolFactory factory) {
        factory = new SovereignPoolFactory();
    }
}
