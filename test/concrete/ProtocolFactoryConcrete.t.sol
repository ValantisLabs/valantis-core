// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IUniversalPool } from 'src/pools/interfaces/IUniversalPool.sol';
import { PoolState } from 'src/pools/structs/UniversalPoolStructs.sol';
import { ProtocolFactory } from 'src/protocol-factory/ProtocolFactory.sol';

import { ProtocolFactoryBase } from 'test/base/ProtocolFactoryBase.t.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';

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
        assertEq(protocolFactory.isValidUniversalALMFactory(universalALMFactory), true);

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
        assertEq(protocolFactory.isValidSovereignALMFactory(sovereignALMFactory), true);

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
        assertEq(protocolFactory.isValidSwapFeeModuleFactory(swapFeeModuleFactory), true);

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
        assertEq(protocolFactory.isValidUniversalOracleModuleFactory(universalOracleModuleFactory), true);

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
        assertEq(protocolFactory.isValidSovereignOracleModuleFactory(sovereignOracleModuleFactory), true);

        // Check error on Sovereign Oracle Module factory already added
        vm.expectRevert(ProtocolFactory.ProtocolFactory___addFactory_alreadyAdded.selector);
        protocolFactory.addSovereignOracleModuleFactory(sovereignOracleModuleFactory);
    }

    function test_removeUniversalALMFactory() public {
        test_addUniversalALMFactory();

        address universalALMFactory = makeAddr('UNIVERSAL_ALM_FACTORY');

        // Check error on unauthorized call to remove Universal ALM factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.removeUniversalALMFactory(universalALMFactory);

        // Check error on invalid Universal ALM factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.removeUniversalALMFactory(ZERO_ADDRESS);

        protocolFactory.removeUniversalALMFactory(universalALMFactory);
        // Check Universal ALM factory is removed correctly
        assertEq(protocolFactory.getUniversalALMFactories().length, 0);
        assertEq(protocolFactory.isValidUniversalALMFactory(universalALMFactory), false);

        // Check error on Universal ALM factory already removed
        vm.expectRevert(ProtocolFactory.ProtocolFactory___removeFactory_notWhitelisted.selector);
        protocolFactory.removeUniversalALMFactory(universalALMFactory);
    }

    function test_removeSovereignALMFactory() public {
        test_addSovereignALMFactory();

        address sovereignALMFactory = makeAddr('SOVEREIGN_ALM_FACTORY');

        // Check error on unauthorized call to remove Sovereign ALM factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.removeSovereignALMFactory(sovereignALMFactory);

        // Check error on invalid Sovereign ALM factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.removeSovereignALMFactory(ZERO_ADDRESS);

        protocolFactory.removeSovereignALMFactory(sovereignALMFactory);
        // Check Sovereign ALM factory is removed correctly
        assertEq(protocolFactory.getSovereignALMFactories().length, 0);
        assertEq(protocolFactory.isValidSovereignALMFactory(sovereignALMFactory), false);

        // Check error on Sovereign ALM factory already removed
        vm.expectRevert(ProtocolFactory.ProtocolFactory___removeFactory_notWhitelisted.selector);
        protocolFactory.removeSovereignALMFactory(sovereignALMFactory);
    }

    function test_removeSwapFeeModuleFactory() public {
        test_addSwapFeeModuleFactory();

        address swapFeeModuleFactory = makeAddr('SWAP_FEE_MODULE_FACTORY');

        // Check error on unauthorized call to remove Swap Fee Module factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.removeSwapFeeModuleFactory(swapFeeModuleFactory);

        // Check error on invalid Swap Fee Module factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.removeSwapFeeModuleFactory(ZERO_ADDRESS);

        protocolFactory.removeSwapFeeModuleFactory(swapFeeModuleFactory);
        // Check Swap Fee Module factory is removed correctly
        assertEq(protocolFactory.getSwapFeeModuleFactories().length, 0);
        assertEq(protocolFactory.isValidSwapFeeModuleFactory(swapFeeModuleFactory), false);

        // Check error on Swap Fee Module factory already removed
        vm.expectRevert(ProtocolFactory.ProtocolFactory___removeFactory_notWhitelisted.selector);
        protocolFactory.removeSwapFeeModuleFactory(swapFeeModuleFactory);
    }

    function test_removeUniversalOracleModuleFactory() public {
        test_addUniversalOracleModuleFactory();

        address universalOracleModuleFactory = makeAddr('UNIVERSAL_ORACLE_MODULE_FACTORY');

        // Check error on unauthorized call to remove Universal Oracle Module factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.removeUniversalOracleModuleFactory(universalOracleModuleFactory);

        // Check error on invalid Universal Oracle Module factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.removeUniversalOracleModuleFactory(ZERO_ADDRESS);

        protocolFactory.removeUniversalOracleModuleFactory(universalOracleModuleFactory);
        // Check Universal Oracle Module factory is removed correctly
        assertEq(protocolFactory.getUniversalOracleModuleFactories().length, 0);
        assertEq(protocolFactory.isValidUniversalOracleModuleFactory(universalOracleModuleFactory), false);

        // Check error on Universal Oracle Module factory already removed
        vm.expectRevert(ProtocolFactory.ProtocolFactory___removeFactory_notWhitelisted.selector);
        protocolFactory.removeUniversalOracleModuleFactory(universalOracleModuleFactory);
    }

    function test_removeSovereignOracleModuleFactory() public {
        test_addSovereignOracleModuleFactory();

        address sovereignOracleModuleFactory = makeAddr('SOVEREIGN_ORACLE_MODULE_FACTORY');

        // Check error on unauthorized call to remove Sovereign Oracle Module factory
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__onlyProtocolManager.selector);
        protocolFactory.removeSovereignOracleModuleFactory(sovereignOracleModuleFactory);

        // Check error on invalid Sovereign Oracle Module factory address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__zeroAddress.selector);
        protocolFactory.removeSovereignOracleModuleFactory(ZERO_ADDRESS);

        protocolFactory.removeSovereignOracleModuleFactory(sovereignOracleModuleFactory);
        // Check Sovereign Oracle Module factory is removed correctly
        assertEq(protocolFactory.getSovereignOracleModuleFactories().length, 0);
        assertEq(protocolFactory.isValidSovereignOracleModuleFactory(sovereignOracleModuleFactory), false);

        // Check error on Sovereign Oracle Module factory already removed
        vm.expectRevert(ProtocolFactory.ProtocolFactory___removeFactory_notWhitelisted.selector);
        protocolFactory.removeSovereignOracleModuleFactory(sovereignOracleModuleFactory);
    }

    function test_deploySovereignGauge() public {
        address gaugeManager = address(this);

        // Check error on invalid Sovereign Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidSovereignPool.selector);
        protocolFactory.deploySovereignGauge(makeAddr('FAKE_POOL'), gaugeManager);

        address pool = test_deploySovereignPool();

        // Check error on unauthorized call to deploy Sovereign Gauge
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__deploySovereignGauge_onlyPoolManager.selector);
        protocolFactory.deploySovereignGauge(pool, gaugeManager);

        // Check error on Auction Controller not set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__auctionControllerNotSet.selector);
        protocolFactory.deploySovereignGauge(pool, gaugeManager);

        test_setAuctionController();

        // Check error on Emissions Controller not set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__emissionsControllerNotSet.selector);
        protocolFactory.deploySovereignGauge(pool, gaugeManager);

        test_setEmissionsController();

        // Check error on Governance Token not set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__valTokenNotSet.selector);
        protocolFactory.deploySovereignGauge(pool, gaugeManager);

        test_setGovernanceToken();

        // Set Sovereign Gauge factory as this contract
        protocolFactory.setSovereignGaugeFactory(gaugeManager);

        // Check Sovereign Gauge is deployed correctly
        address gauge = protocolFactory.deploySovereignGauge(pool, gaugeManager);
        // For testing purposes, we do not deploy any contract
        assertEq(gauge, makeAddr('NO_CONTRACT_DEPLOYMENT'));
        assertEq(protocolFactory.gaugeByPool(pool), gauge);
        assertEq(protocolFactory.poolByGauge(gauge), pool);

        // Check error on Sovereign Gauge already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__deploySovereignGauge_alreadySet.selector);
        protocolFactory.deploySovereignGauge(pool, gaugeManager);

        // Deploy Sovereign Pool, first with this contract as the pool manager
        SovereignPoolConstructorArgs memory args = _generateSovereignPoolDeploymentArgs(
            address(token0),
            address(token1),
            address(0)
        );
        address poolWithoutManager = protocolFactory.deploySovereignPool(args);

        // Check error on unauthorized call to pool without a pool manager
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__deploySovereignGauge_onlyPoolManager.selector);
        protocolFactory.deploySovereignGauge(poolWithoutManager, gaugeManager);

        // This contract is protocol manager, hence is authorized to deploy a Gauge
        address gaugePoolWithoutManager = protocolFactory.deploySovereignGauge(poolWithoutManager, gaugeManager);
        // For testing purposes, we do not deploy any contract
        assertEq(gaugePoolWithoutManager, makeAddr('NO_CONTRACT_DEPLOYMENT'));
        assertEq(protocolFactory.gaugeByPool(poolWithoutManager), gaugePoolWithoutManager);
        assertEq(protocolFactory.poolByGauge(gaugePoolWithoutManager), poolWithoutManager);
    }

    function test_deployUniversalGauge() public {
        address gaugeManager = address(this);

        // Check error on invalid Universal Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidUniversalPool.selector);
        protocolFactory.deployUniversalGauge(makeAddr('FAKE_POOL'), gaugeManager);

        address pool = test_deployUniversalPool();

        // Check error on unauthorized call to deploy Universal Gauge
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__deployUniversalGauge_onlyPoolManager.selector);
        protocolFactory.deployUniversalGauge(pool, gaugeManager);

        // Check error on Auction Controller not set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__auctionControllerNotSet.selector);
        protocolFactory.deployUniversalGauge(pool, gaugeManager);

        test_setAuctionController();

        // Check error on Emissions Controller not set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__emissionsControllerNotSet.selector);
        protocolFactory.deployUniversalGauge(pool, gaugeManager);

        test_setEmissionsController();

        // Check error on Governance Token not set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__valTokenNotSet.selector);
        protocolFactory.deployUniversalGauge(pool, gaugeManager);

        test_setGovernanceToken();

        // Set Universal Gauge factory as this contract
        protocolFactory.setUniversalGaugeFactory(gaugeManager);

        // Check Universal Gauge is deployed correctly
        address gauge = protocolFactory.deployUniversalGauge(pool, gaugeManager);
        // For testing purposes, we do not deploy any contract
        assertEq(gauge, makeAddr('NO_CONTRACT_DEPLOYMENT'));
        assertEq(protocolFactory.gaugeByPool(pool), gauge);
        assertEq(protocolFactory.poolByGauge(gauge), pool);

        // Check error on Universal Gauge already set
        vm.expectRevert(ProtocolFactory.ProtocolFactory__deployUniversalGauge_alreadySet.selector);
        protocolFactory.deployUniversalGauge(pool, gaugeManager);

        // Deploy Universal Pool, first with this contract as the pool manager
        address poolWithoutManager = protocolFactory.deployUniversalPool(
            address(token0),
            address(token1),
            address(this),
            0
        );
        IUniversalPool poolInterface = IUniversalPool(poolWithoutManager);
        assertEq(poolInterface.state().poolManager, address(this));
        PoolState memory poolState = PoolState({
            poolManagerFeeBips: 0,
            feeProtocol0: 0,
            feeProtocol1: 0,
            feePoolManager0: 0,
            feePoolManager1: 0,
            swapFeeModuleUpdateTimestamp: block.timestamp,
            swapFeeModule: address(0),
            poolManager: address(0),
            universalOracle: address(0),
            gauge: address(0)
        });
        poolInterface.initializeTick(2, poolState);
        assertEq(poolInterface.spotPriceTick(), 2);
        assertEq(protocolFactory.isValidUniversalPool(pool), true);
        // Reset pool manager
        assertEq(poolInterface.state().poolManager, address(0));

        // Check error on unauthorized call to pool without a pool manager
        vm.prank(signers[0]);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__deployUniversalGauge_onlyPoolManager.selector);
        protocolFactory.deployUniversalGauge(poolWithoutManager, gaugeManager);

        // This contract is protocol manager, hence is authorized to deploy a Gauge
        address gaugePoolWithoutManager = protocolFactory.deployUniversalGauge(poolWithoutManager, gaugeManager);
        // For testing purposes, we do not deploy any contract
        assertEq(gaugePoolWithoutManager, makeAddr('NO_CONTRACT_DEPLOYMENT'));
        assertEq(protocolFactory.gaugeByPool(poolWithoutManager), gaugePoolWithoutManager);
        assertEq(protocolFactory.poolByGauge(gaugePoolWithoutManager), poolWithoutManager);
    }

    /************************************************
     *  Test Public Functions
     ***********************************************/

    function test_deploySovereignPool() public returns (address pool) {
        _setSovereignPoolFactory();

        SovereignPoolConstructorArgs memory args = _generateSovereignPoolDeploymentArgs(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            address(this)
        );

        // Check error on invalid token address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__tokenNotContract.selector);
        protocolFactory.deploySovereignPool(args);

        args.token0 = address(token0);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__tokenNotContract.selector);
        protocolFactory.deploySovereignPool(args);

        args.token0 = ZERO_ADDRESS;
        args.token1 = address(token1);
        vm.expectRevert(ProtocolFactory.ProtocolFactory__tokenNotContract.selector);
        protocolFactory.deploySovereignPool(args);

        // Check Sovereign Pool is deployed correctly
        args.token0 = address(token0);
        pool = protocolFactory.deploySovereignPool(args);
        assertEq(protocolFactory.isValidSovereignPool(pool), true);
        assertFalse(protocolFactory.isValidSovereignPool(makeAddr('FAKE_MODULE')));
    }

    function test_deploySovereignOracleForPool() public {
        address fakePool = makeAddr('FAKE_POOL');
        address fakeModuleFactory = makeAddr('FAKE_MODULE_FACTORY');

        // Check error on invalid Sovereign Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidSovereignPool.selector);
        protocolFactory.deploySovereignOracleForPool(fakePool, fakeModuleFactory, new bytes(0));

        address pool = test_deploySovereignPool();
        // Check error on invalid Sovereign Oracle Module factory
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidSovereignOracleModuleFactory.selector);
        protocolFactory.deploySovereignOracleForPool(pool, fakeModuleFactory, new bytes(0));

        // Set Sovereign Oracle module factory as this contract
        protocolFactory.addSovereignOracleModuleFactory(address(this));

        // Check Sovereign Oracle module is deployed correctly
        setIsDeployment(true);
        address sovereignOracleModule = protocolFactory.deploySovereignOracleForPool(
            pool,
            address(this),
            abi.encode(address(this), 12)
        );
        assertEq(protocolFactory.sovereignOracleModuleNonce(), 1);
        assertTrue(protocolFactory.isValidSovereignOracleModule(sovereignOracleModule));
        assertFalse(protocolFactory.isValidSovereignOracleModule(makeAddr('FAKE_MODULE')));
    }

    function test_deploySwapFeeModuleForPool() public {
        address fakePool = makeAddr('FAKE_POOL');
        address fakeModuleFactory = makeAddr('FAKE_MODULE_FACTORY');

        // Check error on invalid Sovereign Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidValantisPool.selector);
        protocolFactory.deploySwapFeeModuleForPool(fakePool, fakeModuleFactory, new bytes(0));

        address pool = test_deploySovereignPool();
        // Check error on invalid Swap Fee Module factory
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidSwapFeeModuleFactory.selector);
        protocolFactory.deploySwapFeeModuleForPool(pool, fakeModuleFactory, new bytes(0));

        // Set Swap Fee Module module factory as this contract
        protocolFactory.addSwapFeeModuleFactory(address(this));

        // Check Swap Fee module is deployed correctly
        setIsDeployment(true);
        address swapFeeModule = protocolFactory.deploySwapFeeModuleForPool(
            pool,
            address(this),
            abi.encode(address(this), 12)
        );
        assertEq(protocolFactory.swapFeeModuleNonce(), 1);
        assertTrue(protocolFactory.isValidSwapFeeModule(swapFeeModule));
        assertFalse(protocolFactory.isValidSwapFeeModule(makeAddr('FAKE_MODULE')));
    }

    function test_deployALMPositionForSovereignPool() public {
        address fakePool = makeAddr('FAKE_POOL');
        address fakeModuleFactory = makeAddr('FAKE_MODULE_FACTORY');

        // Check error on invalid Sovereign Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidSovereignPool.selector);
        protocolFactory.deployALMPositionForSovereignPool(fakePool, fakeModuleFactory, new bytes(0));

        address pool = test_deploySovereignPool();
        // Check error on invalid ALM factory
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidALMFactory.selector);
        protocolFactory.deployALMPositionForSovereignPool(pool, fakeModuleFactory, new bytes(0));

        // Set ALM factory as this contract
        protocolFactory.addSovereignALMFactory(address(this));

        // Check Sovereign ALM is deployed correctly
        setIsDeployment(true);
        address sovereignALM = protocolFactory.deployALMPositionForSovereignPool(
            pool,
            address(this),
            abi.encode(address(this), 12)
        );
        assertEq(protocolFactory.almNonce(), 1);
        assertTrue(protocolFactory.isValidSovereignALMPosition(sovereignALM));
        assertFalse(protocolFactory.isValidSovereignALMPosition(makeAddr('FAKE_MODULE')));
    }

    function test_deployUniversalPool() public returns (address pool) {
        _setUniversalPoolFactory();

        // Check error on invalid token address
        vm.expectRevert(ProtocolFactory.ProtocolFactory__tokenNotContract.selector);
        protocolFactory.deployUniversalPool(ZERO_ADDRESS, ZERO_ADDRESS, address(this), 0);

        vm.expectRevert(ProtocolFactory.ProtocolFactory__tokenNotContract.selector);
        protocolFactory.deployUniversalPool(address(token0), ZERO_ADDRESS, address(this), 0);

        vm.expectRevert(ProtocolFactory.ProtocolFactory__tokenNotContract.selector);
        protocolFactory.deployUniversalPool(ZERO_ADDRESS, address(token1), address(this), 0);

        // Check Universal Pool is deployed correctly
        pool = protocolFactory.deployUniversalPool(address(token0), address(token1), address(this), 0);
        IUniversalPool poolInterface = IUniversalPool(pool);
        PoolState memory poolState = PoolState({
            poolManagerFeeBips: 0,
            feeProtocol0: 0,
            feeProtocol1: 0,
            feePoolManager0: 0,
            feePoolManager1: 0,
            swapFeeModuleUpdateTimestamp: block.timestamp,
            swapFeeModule: address(0),
            poolManager: address(this),
            universalOracle: address(0),
            gauge: address(0)
        });
        poolInterface.initializeTick(2, poolState);
        assertEq(poolInterface.spotPriceTick(), 2);
        assertTrue(protocolFactory.isValidUniversalPool(pool));
        assertFalse(protocolFactory.isValidUniversalPool(makeAddr('FAKE_MODULE')));
    }

    function test_deployUniversalOracleForPool() public {
        address fakePool = makeAddr('FAKE_POOL');
        address fakeModuleFactory = makeAddr('FAKE_MODULE_FACTORY');

        // Check error on invalid Universal Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidUniversalPool.selector);
        protocolFactory.deployUniversalOracleForPool(fakePool, fakeModuleFactory, new bytes(0));

        address pool = test_deployUniversalPool();
        // Check error on invalid Sovereign Oracle Module factory
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidUniversalOracleModuleFactory.selector);
        protocolFactory.deployUniversalOracleForPool(pool, fakeModuleFactory, new bytes(0));

        // Set Universal Oracle module factory as this contract
        protocolFactory.addUniversalOracleModuleFactory(address(this));

        // Check Universal Oracle module is deployed correctly
        setIsDeployment(true);
        address universalOracleModule = protocolFactory.deployUniversalOracleForPool(
            pool,
            address(this),
            abi.encode(address(this), 12)
        );
        assertEq(protocolFactory.universalOracleModuleNonce(), 1);
        assertTrue(protocolFactory.isValidUniversalOracleModule(universalOracleModule));
        assertFalse(protocolFactory.isValidUniversalOracleModule(makeAddr('FAKE_MODULE')));
    }

    function test_deployALMPositionForUniversalPool() public {
        address fakePool = makeAddr('FAKE_POOL');
        address fakeModuleFactory = makeAddr('FAKE_MODULE_FACTORY');

        // Check error on invalid Universal Pool
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidUniversalPool.selector);
        protocolFactory.deployALMPositionForUniversalPool(fakePool, fakeModuleFactory, new bytes(0));

        address pool = test_deployUniversalPool();
        // Check error on invalid ALM factory
        vm.expectRevert(ProtocolFactory.ProtocolFactory__invalidALMFactory.selector);
        protocolFactory.deployALMPositionForUniversalPool(pool, fakeModuleFactory, new bytes(0));

        // Set ALM factory as this contract
        protocolFactory.addUniversalALMFactory(address(this));

        // Check Universal ALM is deployed correctly
        setIsDeployment(true);
        address universalALM = protocolFactory.deployALMPositionForUniversalPool(
            pool,
            address(this),
            abi.encode(address(this), 12)
        );
        assertEq(protocolFactory.almNonce(), 1);
        assertTrue(protocolFactory.isValidUniversalALMPosition(universalALM));
        assertFalse(protocolFactory.isValidUniversalALMPosition(makeAddr('FAKE_MODULE')));
    }

    function test_invalidCreate2Deployment() public {
        // Set Universal Oracle module factory as this contract
        protocolFactory.addUniversalOracleModuleFactory(address(this));

        address pool = test_deployUniversalPool();

        // Check error on address already with contract
        setCreate2AddressWithContract(true);

        vm.expectRevert(ProtocolFactory.ProtocolFactory__addressWithContract.selector);
        protocolFactory.deployUniversalOracleForPool(pool, address(this), abi.encode(address(this), 12));

        setCreate2AddressWithContract(false);

        // Check error on contract not deployed
        vm.expectRevert(ProtocolFactory.ProtocolFactory__noContractDeployed.selector);
        protocolFactory.deployUniversalOracleForPool(pool, address(this), abi.encode(address(this), 12));
    }
}
