// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ProtocolFactory } from 'src/protocol-factory/ProtocolFactory.sol';

import { ProtocolFactoryBase } from 'test/base/ProtocolFactoryBase.t.sol';

contract ProtocolFactoryConcreteTest is ProtocolFactoryBase {
    /************************************************
     *  Test Constructor
     ***********************************************/

    function test_defaultConstructorArgs() public {
        // Check default block time is 12 seconds
        assertEq(protocolFactory.BLOCK_TIME(), 12);

        // Check default protocol deployer is this contract
        assertEq(protocolFactory.protocolDeployer(), address(this));

        // Check default protocol manager is this contract
        assertEq(protocolFactory.protocolManager(), address(this));
    }

    function test_customConstructorArgs() public {
        address protocolDeployer = makeAddr('PROTOCOL_DEPLOYER');
        uint32 blockTime = 1;

        // Check error on invalid prototocol deployer address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        deployProtocolFactory(ZERO_ADDRESS, blockTime);

        // Check error on invalid block time
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidBlockTime.selector);
        deployProtocolFactory(protocolDeployer, 0);

        protocolFactory = deployProtocolFactory(protocolDeployer, blockTime);
        // Check protocol deployer is set correctly
        assertEq(protocolFactory.protocolDeployer(), protocolDeployer);
        // Check block time is set correctly
        assertEq(protocolFactory.BLOCK_TIME(), blockTime);
    }

    /************************************************
     *  Test Permissioned functions
     ***********************************************/

    function test_setGovernanceToken() public {
        address governanceToken = makeAddr('GOVERNANCE_TOKEN');

        // Check error on unauthorized call to set governance token
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setGovernanceToken(governanceToken);

        // Check error on invalid token address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setGovernanceToken(ZERO_ADDRESS);

        protocolFactory.setGovernanceToken(governanceToken);
        // Check governance token is set correctly
        assertEq(protocolFactory.governanceToken(), governanceToken);

        address governanceTokenNew = makeAddr('GOVERNANCE_TOKEN_NEW');
        // Check error on governance token already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setGovernanceToken_alreadySet.selector);
        protocolFactory.setGovernanceToken(governanceTokenNew);
    }

    function test_setProtocolManager() public {
        address protocolManager = makeAddr('PROTOCOL_MANAGER');

        // Check error on unauthorized call to set protocol manager
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setProtocolManager(protocolManager);

        // Check error on invalid protocol manager address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setProtocolManager(ZERO_ADDRESS);

        protocolFactory.setProtocolManager(protocolManager);
        // Check protocol manager is set correctly
        assertEq(protocolFactory.protocolManager(), protocolManager);

        address protocolManagerNew = makeAddr('PROTOCOL_MANAGER_NEW');
        // Check error on protocol manager already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setProtocolManager_alreadySet.selector);
        protocolFactory.setProtocolManager(protocolManagerNew);
    }
}
