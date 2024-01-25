// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { UniversalPool } from 'src/pools/UniversalPool.sol';
import { UniversalPoolFactory } from 'src/pools/factories/UniversalPoolFactory.sol';
import { ProtocolFactory } from 'src/protocol-factory/ProtocolFactory.sol';

import { ProtocolFactoryDeployer } from 'test/deployers/ProtocolFactoryDeployer.sol';
import { UniversalPoolFactoryDeployer } from 'test/deployers/UniversalPoolFactoryDeployer.sol';

contract UniversalPoolDeployer is UniversalPoolFactoryDeployer, ProtocolFactoryDeployer {
    function deployUniversalPool(
        address token0Address,
        address token1Address,
        address poolManager,
        uint256 defaultSwapFeeBips
    ) public returns (UniversalPool poolDeployed) {
        ProtocolFactory protocolFactory = deployProtocolFactory();

        UniversalPoolFactory universalPoolFactory = deployUniversalPoolFactory();

        protocolFactory.setUniversalPoolFactory(address(universalPoolFactory));

        poolDeployed = _deployUniversalPool(
            protocolFactory,
            token0Address,
            token1Address,
            poolManager,
            defaultSwapFeeBips
        );
    }

    function deployUniversalPool(
        ProtocolFactory protocolFactory,
        address token0Address,
        address token1Address,
        address poolManager,
        uint256 defaultSwapFeeBips
    ) public returns (UniversalPool poolDeployed) {
        poolDeployed = _deployUniversalPool(
            protocolFactory,
            token0Address,
            token1Address,
            poolManager,
            defaultSwapFeeBips
        );
    }

    function _deployUniversalPool(
        ProtocolFactory protocolFactory,
        address token0Address,
        address token1Address,
        address poolManager,
        uint256 defaultSwapFeeBips
    ) internal returns (UniversalPool poolDeployed) {
        poolDeployed = UniversalPool(
            protocolFactory.deployUniversalPool(token0Address, token1Address, poolManager, defaultSwapFeeBips)
        );
    }
}
