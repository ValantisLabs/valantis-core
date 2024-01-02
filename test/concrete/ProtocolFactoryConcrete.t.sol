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

    function test_setUniversalPoolFactory() public {
        address universalPoolFactory = makeAddr('UNIVERSAL_POOL_FACTORY');

        // Check error on unauthorized call to set Universal Pool factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setUniversalPoolFactory(universalPoolFactory);

        // Check error on invalid Universal Pool factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setUniversalPoolFactory(ZERO_ADDRESS);

        protocolFactory.setUniversalPoolFactory(universalPoolFactory);
        // Check Universal Pool factory is set correctly
        assertEq(protocolFactory.universalPoolFactory(), universalPoolFactory);

        address universalPoolFactoryNew = makeAddr('UNIVERSAL_POOL_FACTORY_NEW');
        // Check error on Universal Pool factory already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setUniversalPoolFactory_alreadySet.selector);
        protocolFactory.setUniversalPoolFactory(universalPoolFactoryNew);
    }

    function test_setSovereignPoolFactory() public {
        address sovereignPoolFactory = makeAddr('SOVEREIGN_POOL_FACTORY');

        // Check error on unauthorized call to set Sovereign Pool factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);

        // Check error on invalid Sovereign Pool factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setSovereignPoolFactory(ZERO_ADDRESS);

        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);
        // Check Sovereign Pool factory is set correctly
        assertEq(protocolFactory.sovereignPoolFactory(), sovereignPoolFactory);

        address sovereignPoolFactoryNew = makeAddr('SOVEREIGN_POOL_FACTORY_NEW');
        // Check error on Sovereign Pool factory already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setSovereignPoolFactory_alreadySet.selector);
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactoryNew);
    }

    function test_setAuctionController() public {
        address auctionController = address(this);

        // Check that Auction Controller is not initialized
        assertEq(isAuctionControllerInitialized, false);

        // Check error on unauthorized call to set Auction Controller
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setAuctionController(auctionController);

        // Check error on invalid Auction Controller address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setAuctionController(ZERO_ADDRESS);

        protocolFactory.setAuctionController(auctionController);
        // Check Auction Controller is set correctly
        assertEq(protocolFactory.auctionController(), address(this));
        assertEq(isAuctionControllerInitialized, true);

        address auctionControllerNew = makeAddr('AUCTION_CONTROLLER_NEW');
        // Check error on Auction Controller already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setAuctionController_alreadySet.selector);
        protocolFactory.setAuctionController(auctionControllerNew);
        assertEq(isAuctionControllerInitialized, true);
    }

    function test_setEmissionsController() public {
        address emissionsController = makeAddr('EMISSIONS_CONTROLLER');

        // Check error on unauthorized call to set Emissions Controller
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setEmissionsController(emissionsController);

        // Check error on invalid Emissions Controller address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setEmissionsController(ZERO_ADDRESS);

        protocolFactory.setEmissionsController(emissionsController);
        // Check Emissions Controller is set correctly
        assertEq(protocolFactory.emissionsController(), emissionsController);

        address emissionsControllerNew = makeAddr('EMISSIONS_CONTROLLER_NEW');
        // Check error on Emissions Controller already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setEmissionsController_alreadySet.selector);
        protocolFactory.setEmissionsController(emissionsControllerNew);
    }

    function test_setUniversalGaugeFactory() public {
        address universalGaugeFactory = makeAddr('UNIVERSAL_GAUGE_FACTORY');

        // Check error on unauthorized call to set Universal Gauge factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setUniversalGaugeFactory(universalGaugeFactory);

        // Check error on invalid Universal Gauge factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setUniversalGaugeFactory(ZERO_ADDRESS);

        protocolFactory.setUniversalGaugeFactory(universalGaugeFactory);
        // Check Universal Gauge factory is set correctly
        assertEq(protocolFactory.universalGaugeFactory(), universalGaugeFactory);

        address universalGaugeFactoryNew = makeAddr('UNIVERSAL_GAUGE_FACTORY_NEW');
        // Check error on Universal Gauge factory already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setUniversalGaugeFactory_alreadySet.selector);
        protocolFactory.setUniversalGaugeFactory(universalGaugeFactoryNew);
    }

    function test_setSovereignGaugeFactory() public {
        address sovereignGaugeFactory = makeAddr('SOVEREIGN_GAUGE_FACTORY');

        // Check error on unauthorized call to set Sovereign Gauge factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolDeployer.selector);
        protocolFactory.setSovereignGaugeFactory(sovereignGaugeFactory);

        // Check error on invalid Sovereign Gauge factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.setSovereignGaugeFactory(ZERO_ADDRESS);

        protocolFactory.setSovereignGaugeFactory(sovereignGaugeFactory);
        // Check Sovereign Gauge factory is set correctly
        assertEq(protocolFactory.sovereignGaugeFactory(), sovereignGaugeFactory);

        address sovereignGaugeFactoryNew = makeAddr('SOVEREIGN_GAUGE_FACTORY_NEW');
        // Check error on Sovereign Gauge factory already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__setSovereignGaugeFactory_alreadySet.selector);
        protocolFactory.setSovereignGaugeFactory(sovereignGaugeFactoryNew);
    }

    function test_addUniversalALMFactory() public {
        address universalALMFactory = makeAddr('UNIVERSAL_ALM_FACTORY');

        // Check error on unauthorized call to add Universal ALM factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.addUniversalALMFactory(universalALMFactory);

        // Check error on invalid Universal ALM factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.addUniversalALMFactory(ZERO_ADDRESS);

        protocolFactory.addUniversalALMFactory(universalALMFactory);
        // Check Universal ALM factory is added correctly
        assertEq(protocolFactory.getUniversalALMFactories()[0], universalALMFactory);
        assertEq(protocolFactory.getUniversalALMFactories().length, 1);

        // Check error on Universal ALM factory already added
        vm.expectRevert(ProtocolFactory.ProtocolFactory___addFactory_alreadyAdded.selector);
        protocolFactory.addUniversalALMFactory(universalALMFactory);
    }

    function test_addSovereignALMFactory() public {
        address sovereignALMFactory = makeAddr('SOVEREIGN_ALM_FACTORY');

        // Check error on unauthorized call to add Sovereign ALM factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.addSovereignALMFactory(sovereignALMFactory);

        // Check error on invalid Sovereign ALM factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.addSovereignALMFactory(ZERO_ADDRESS);

        protocolFactory.addSovereignALMFactory(sovereignALMFactory);
        // Check Sovereign ALM factory is added correctly
        assertEq(protocolFactory.getSovereignALMFactories()[0], sovereignALMFactory);
        assertEq(protocolFactory.getSovereignALMFactories().length, 1);

        // Check error on Sovereign ALM factory already added
        vm.expectRevert(ProtocolFactory.ProtocolFactory___addFactory_alreadyAdded.selector);
        protocolFactory.addSovereignALMFactory(sovereignALMFactory);
    }

    function test_addSwapFeeModuleFactory() public {
        address swapFeeModuleFactory = makeAddr('SWAP_FEE_MODULE_FACTORY');

        // Check error on unauthorized call to add Swap Fee Module factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.addSwapFeeModuleFactory(swapFeeModuleFactory);

        // Check error on invalid Swap Fee Module factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.addSwapFeeModuleFactory(ZERO_ADDRESS);

        protocolFactory.addSwapFeeModuleFactory(swapFeeModuleFactory);
        // Check Swap Fee Module factory is added correctly
        assertEq(protocolFactory.getSwapFeeModuleFactories()[0], swapFeeModuleFactory);
        assertEq(protocolFactory.getSwapFeeModuleFactories().length, 1);

        // Check error on Swap Fee Module factory already added
        vm.expectRevert(ProtocolFactory.ProtocolFactory___addFactory_alreadyAdded.selector);
        protocolFactory.addSwapFeeModuleFactory(swapFeeModuleFactory);
    }

    function test_addUniversalOracleModuleFactory() public {
        address universalOracleModuleFactory = makeAddr('UNIVERSAL_ORACLE_MODULE_FACTORY');

        // Check error on unauthorized call to add Universal Oracle Module factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.addUniversalOracleModuleFactory(universalOracleModuleFactory);

        // Check error on invalid Universal Oracle Module factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.addUniversalOracleModuleFactory(ZERO_ADDRESS);

        protocolFactory.addUniversalOracleModuleFactory(universalOracleModuleFactory);
        // Check Universal Oracle Module factory is added correctly
        assertEq(protocolFactory.getUniversalOracleModuleFactories()[0], universalOracleModuleFactory);
        assertEq(protocolFactory.getUniversalOracleModuleFactories().length, 1);

        // Check error on Universal Oracle Module factory already added
        vm.expectRevert(ProtocolFactory.ProtocolFactory___addFactory_alreadyAdded.selector);
        protocolFactory.addUniversalOracleModuleFactory(universalOracleModuleFactory);
    }

    function test_addSovereignOracleModuleFactory() public {
        address sovereignOracleModuleFactory = makeAddr('SOVEREIGN_ORACLE_MODULE_FACTORY');

        // Check error on unauthorized call to add Sovereign Oracle Module factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.addSovereignOracleModuleFactory(sovereignOracleModuleFactory);

        // Check error on invalid Sovereign Oracle Module factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.addSovereignOracleModuleFactory(ZERO_ADDRESS);

        protocolFactory.addSovereignOracleModuleFactory(sovereignOracleModuleFactory);
        // Check Sovereign Oracle Module factory is added correctly
        assertEq(protocolFactory.getSovereignOracleModuleFactories()[0], sovereignOracleModuleFactory);
        assertEq(protocolFactory.getSovereignOracleModuleFactories().length, 1);

        // Check error on Sovereign Oracle Module factory already added
        vm.expectRevert(ProtocolFactory.ProtocolFactory___addFactory_alreadyAdded.selector);
        protocolFactory.addSovereignOracleModuleFactory(sovereignOracleModuleFactory);
    }
}
