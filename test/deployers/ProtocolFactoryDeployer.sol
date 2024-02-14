// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ProtocolFactory } from '../../src/protocol-factory/ProtocolFactory.sol';

contract ProtocolFactoryDeployer {
    function deployProtocolFactory() public returns (ProtocolFactory protocolFactory) {
        protocolFactory = new ProtocolFactory(address(this), 12);
    }

    function deployProtocolFactory(address deployer) public returns (ProtocolFactory protocolFactory) {
        protocolFactory = new ProtocolFactory(deployer, 12);
    }

    function deployProtocolFactory(uint32 blockTime) public returns (ProtocolFactory protocolFactory) {
        protocolFactory = new ProtocolFactory(address(this), blockTime);
    }

    function deployProtocolFactory(
        address deployer,
        uint32 blockTime
    ) public returns (ProtocolFactory protocolFactory) {
        protocolFactory = new ProtocolFactory(deployer, blockTime);
    }
}
