// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ProtocolFactory } from '../../src/protocol-factory/ProtocolFactory.sol';

contract ProtocolFactoryDeployer {
    function deployProtocolFactory() public returns (ProtocolFactory protocolFactory) {
        protocolFactory = new ProtocolFactory(address(this));
    }

    function deployProtocolFactory(address deployer) public returns (ProtocolFactory protocolFactory) {
        protocolFactory = new ProtocolFactory(deployer);
    }
}
