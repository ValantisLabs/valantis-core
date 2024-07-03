// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { SovereignPoolConstructorArgs } from '../../src/pools/structs/SovereignPoolStructs.sol';
import { SovereignPool } from '../../src/pools/SovereignPool.sol';
import { SovereignPoolFactory } from '../../src/pools/factories/SovereignPoolFactory.sol';
import { ProtocolFactory } from '../../src/protocol-factory/ProtocolFactory.sol';

import { SovereignPoolFactoryDeployer } from '../deployers/SovereignPoolFactoryDeployer.sol';
import { ProtocolFactoryDeployer } from '../deployers/ProtocolFactoryDeployer.sol';

contract SovereignPoolDeployer is ProtocolFactoryDeployer, SovereignPoolFactoryDeployer {
    function deploySovereignPool(
        SovereignPoolConstructorArgs calldata constructorArgs
    ) public returns (SovereignPool pool) {
        ProtocolFactory protocolFactory = deployProtocolFactory();

        SovereignPoolFactory sovereignPoolFactory = deploySovereignPoolFactory();

        protocolFactory.setSovereignPoolFactory(address(sovereignPoolFactory));

        pool = _deploySovereignPool(protocolFactory, constructorArgs);
    }

    function deploySovereignPool(
        ProtocolFactory protocolFactory,
        SovereignPoolConstructorArgs calldata constructorArgs
    ) public returns (SovereignPool pool) {
        pool = _deploySovereignPool(protocolFactory, constructorArgs);
    }

    function _deploySovereignPool(
        ProtocolFactory protocolFactory,
        SovereignPoolConstructorArgs calldata constructorArgs
    ) internal returns (SovereignPool pool) {
        pool = SovereignPool(protocolFactory.deploySovereignPool(constructorArgs));
    }
}
