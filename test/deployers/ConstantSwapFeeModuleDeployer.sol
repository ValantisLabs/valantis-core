// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ProtocolFactory } from '../../src/protocol-factory/ProtocolFactory.sol';
import { ConstantSwapFeeModule } from '../../src/swap-fee-modules/ConstantSwapFeeModule.sol';
import { ConstantSwapFeeModuleFactory } from '../../src/swap-fee-modules/factories/ConstantSwapFeeModuleFactory.sol';

import { ProtocolFactoryDeployer } from '../deployers/ProtocolFactoryDeployer.sol';
import { ConstantSwapFeeModuleFactoryDeployer } from '../deployers/ConstantSwapFeeModuleFactoryDeployer.sol';

contract ConstantSwapFeeModuleDeployer is ProtocolFactoryDeployer, ConstantSwapFeeModuleFactoryDeployer {
    function deployConstantSwapFeeModule(
        address pool,
        address swapFeeModuleManager,
        uint256 swapFeeBips
    ) public returns (ConstantSwapFeeModule swapFeeModule) {
        ProtocolFactory protocolFactory = deployProtocolFactory();
        ConstantSwapFeeModuleFactory factory = deployConstantSwapFeeModuleFactory(address(protocolFactory));

        protocolFactory.addSwapFeeModuleFactory(address(factory));

        swapFeeModule = _deployConstantSwapFeeModule(
            protocolFactory,
            address(factory),
            pool,
            swapFeeModuleManager,
            swapFeeBips
        );
    }

    function deployConstantSwapFeeModule(
        ProtocolFactory protocolFactory,
        address pool,
        address swapFeeModuleManager,
        uint256 swapFeeBips
    ) public returns (ConstantSwapFeeModule swapFeeModule) {
        ConstantSwapFeeModuleFactory factory = deployConstantSwapFeeModuleFactory(address(protocolFactory));
        protocolFactory.addSwapFeeModuleFactory(address(factory));

        swapFeeModule = _deployConstantSwapFeeModule(
            protocolFactory,
            address(factory),
            pool,
            swapFeeModuleManager,
            swapFeeBips
        );
    }

    function deployConstantSwapFeeModule(
        ProtocolFactory protocolFactory,
        address factory,
        address pool,
        address swapFeeModuleManager,
        uint256 swapFeeBips
    ) public returns (ConstantSwapFeeModule swapFeeModule) {
        swapFeeModule = _deployConstantSwapFeeModule(protocolFactory, factory, pool, swapFeeModuleManager, swapFeeBips);
    }

    function _deployConstantSwapFeeModule(
        ProtocolFactory protocolFactory,
        address factory,
        address pool,
        address swapFeeModuleManager,
        uint256 swapFeeBips
    ) internal returns (ConstantSwapFeeModule swapFeeModule) {
        swapFeeModule = ConstantSwapFeeModule(
            protocolFactory.deploySwapFeeModuleForPool(
                pool,
                factory,
                abi.encode(pool, swapFeeModuleManager, swapFeeBips)
            )
        );
    }
}
