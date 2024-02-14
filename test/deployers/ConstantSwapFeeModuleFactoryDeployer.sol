// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ConstantSwapFeeModuleFactory } from '../../src/swap-fee-modules/factories/ConstantSwapFeeModuleFactory.sol';

contract ConstantSwapFeeModuleFactoryDeployer {
    function deployConstantSwapFeeModuleFactory(
        address protocolFactory
    ) public returns (ConstantSwapFeeModuleFactory factory) {
        factory = new ConstantSwapFeeModuleFactory(protocolFactory);
    }
}
