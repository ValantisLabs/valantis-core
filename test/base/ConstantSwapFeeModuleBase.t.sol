// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { console } from 'forge-std/console.sol';

import { ConstantSwapFeeModule } from '../../src/swap-fee-modules/ConstantSwapFeeModule.sol';
import { ConstantSwapFeeModuleFactory } from '../../src/swap-fee-modules/factories/ConstantSwapFeeModuleFactory.sol';
import { UniversalPool } from '../../src/pools/UniversalPool.sol';
import { UniversalPoolFactory } from '../../src/pools/factories/UniversalPoolFactory.sol';
import { ProtocolFactory } from '../../src/protocol-factory/ProtocolFactory.sol';

import { Base } from '../base/Base.sol';
import { ProtocolFactoryDeployer } from '../deployers/ProtocolFactoryDeployer.sol';
import { ConstantSwapFeeModuleDeployer } from '../deployers/ConstantSwapFeeModuleDeployer.sol';
import { UniversalPoolDeployer } from '../deployers/UniversalPoolDeployer.sol';

contract ConstantSwapFeeModuleBase is Base, ConstantSwapFeeModuleDeployer, UniversalPoolDeployer {
    ProtocolFactory public protocolFactory;

    UniversalPool public pool;

    ConstantSwapFeeModule public swapFeeModule;

    ConstantSwapFeeModuleFactory public factory;

    function setUp() public {
        _setupBase();

        protocolFactory = deployProtocolFactory();

        UniversalPoolFactory poolFactory = deployUniversalPoolFactory();

        protocolFactory.setUniversalPoolFactory(address(poolFactory));

        pool = deployUniversalPool(protocolFactory, address(token0), address(token1), POOL_MANAGER, 0);

        factory = deployConstantSwapFeeModuleFactory(address(protocolFactory));

        protocolFactory.addSwapFeeModuleFactory(address(factory));

        swapFeeModule = deployConstantSwapFeeModule(protocolFactory, address(factory), address(pool), POOL_MANAGER, 0);
    }
}
