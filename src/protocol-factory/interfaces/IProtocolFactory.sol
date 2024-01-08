// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SovereignPoolConstructorArgs } from '../../pools/structs/SovereignPoolStructs.sol';

interface IProtocolFactory {
    event GovernanceTokenSet(address governanceToken);
    event ProtocolManagerSet(address protocolManager);
    event UniversalPoolFactorySet(address universalPoolFactory);
    event SovereignPoolFactorySet(address sovereignPoolFactory);
    event AuctionControllerSet(address auctionController);
    event EmissionsControllerSet(address emissionsController);
    event UniversalGaugeFactorySet(address universalGaugeFactory);
    event SovereignGaugeFactorySet(address sovereignGaugeFactory);

    event UniversalALMDeployed(address alm, address pool, address factory);
    event SovereignALMDeployed(address alm, address pool, address factory);
    event SwapFeeModuleDeployed(address swapFeeModule, address pool, address factory);
    event UniversalOracleDeployed(address universalOracle, address pool, address factory);
    event SovereignOracleDeployed(address sovereignOracle, address pool, address factory);
    event UniversalPoolDeployed(address indexed token0, address indexed token1, address pool);
    event SovereignPoolDeployed(address indexed token0, address indexed token1, address pool);
    event UniversalGaugeDeployed(address gauge, address pool, address manager);
    event SovereignGaugeDeployed(address gauge, address pool, address manager);

    event UniversalALMFactoryAdded(address factory);
    event UniversalALMFactoryRemoved(address factory);
    event SovereignALMFactoryAdded(address factory);
    event SovereignALMFactoryRemoved(address factory);
    event SwapFeeModuleFactoryAdded(address factory);
    event SwapFeeModuleFactoryRemoved(address factory);
    event UniversalOracleFactoryAdded(address factory);
    event UniversalOracleFactoryRemoved(address factory);
    event SovereignOracleFactoryAdded(address factory);
    event SovereignOracleFactoryRemoved(address factory);

    function protocolDeployer() external view returns (address);

    // solhint-disable-next-line func-name-mixedcase
    function BLOCK_TIME() external view returns (uint256);

    function almFactories(address _almPosition) external view returns (address);

    function swapFeeModules(address _pool) external view returns (address);

    function universalOracleModules(address _pool) external view returns (address);

    function sovereignOracleModules(address _pool) external view returns (address);

    function auctionController() external view returns (address);

    function emissionsController() external view returns (address);

    function almNonce() external view returns (uint256);

    function swapFeeModuleNonce() external view returns (uint256);

    function universalOracleModuleNonce() external view returns (uint256);

    function sovereignOracleModuleNonce() external view returns (uint256);

    function protocolManager() external view returns (address);

    function governanceToken() external view returns (address);

    function universalPoolFactory() external view returns (address);

    function sovereignPoolFactory() external view returns (address);

    function universalGaugeFactory() external view returns (address);

    function sovereignGaugeFactory() external view returns (address);

    function getUniversalALMFactories() external view returns (address[] memory);

    function getSovereignALMFactories() external view returns (address[] memory);

    function getSwapFeeModuleFactories() external view returns (address[] memory);

    function getUniversalOracleModuleFactories() external view returns (address[] memory);

    function getSovereignOracleModuleFactories() external view returns (address[] memory);

    function gaugeByPool(address _pool) external view returns (address);

    function poolByGauge(address _gauge) external view returns (address);

    function isValidUniversalPool(address _pool) external view returns (bool);

    function isValidSovereignPool(address _pool) external view returns (bool);

    function isValidUniversalALMFactory(address _almFactory) external view returns (bool);

    function isValidSovereignALMFactory(address _almFactory) external view returns (bool);

    function isValidSwapFeeModuleFactory(address _swapFeeModuleFactory) external view returns (bool);

    function isValidUniversalOracleModuleFactory(address _universalOracleModuleFactory) external view returns (bool);

    function isValidSovereignOracleModuleFactory(address _sovereignOracleModuleFactory) external view returns (bool);

    function isValidUniversalALMPosition(address _almPosition) external view returns (bool);

    function isValidSovereignALMPosition(address _almPosition) external view returns (bool);

    function isValidSwapFeeModule(address _swapFeeModule) external view returns (bool);

    function isValidUniversalOracleModule(address _universalOracleModule) external view returns (bool);

    function isValidSovereignOracleModule(address _sovereignOracleModule) external view returns (bool);

    function setGovernanceToken(address _governanceToken) external;

    function setProtocolManager(address _protocolManager) external;

    function setUniversalPoolFactory(address _universalPoolFactory) external;

    function setSovereignPoolFactory(address _sovereignPoolFactory) external;

    function setAuctionController(address _auctionController) external;

    function setEmissionsController(address _emissionsController) external;

    function setSovereignGaugeFactory(address _poolGaugeFactory) external;

    function setUniversalGaugeFactory(address _universalGaugeFactory) external;

    function deployUniversalGauge(address _pool, address _manager) external returns (address gauge);

    function deploySovereignGauge(address _pool, address _manager) external returns (address gauge);

    function deployALMPositionForUniversalPool(
        address _pool,
        address _almFactory,
        bytes calldata _constructorArgs
    ) external returns (address alm);

    function deployALMPositionForSovereignPool(
        address _pool,
        address _almFactory,
        bytes calldata _constructorArgs
    ) external returns (address alm);

    function deploySwapFeeModuleForPool(
        address _pool,
        address _swapFeeModuleFactory,
        bytes calldata _constructorArgs
    ) external returns (address swapFeeModule);

    function deployUniversalPool(
        address _token0,
        address _token1,
        address _poolManager,
        uint256 _deploySwapFeeBips
    ) external returns (address pool);

    function deploySovereignPool(SovereignPoolConstructorArgs memory _args) external returns (address pool);

    function deployUniversalOracleForPool(
        address _pool,
        address _universalOracleModuleFactory,
        bytes calldata _constructorArgs
    ) external returns (address universalOracleModule);

    function deploySovereignOracleForPool(
        address _pool,
        address _sovereignOracleModuleFactory,
        bytes calldata _constructorArgs
    ) external returns (address sovereignOracleModule);

    function addUniversalALMFactory(address _almFactory) external;

    function addSovereignALMFactory(address _almFactory) external;

    function addSwapFeeModuleFactory(address _swapFeeModuleFactory) external;

    function addUniversalOracleModuleFactory(address _universalOracleModuleFactory) external;

    function addSovereignOracleModuleFactory(address _sovereignOracleModuleFactory) external;

    function removeUniversalALMFactory(address _almFactory) external;

    function removeSovereignALMFactory(address _almFactory) external;

    function removeSwapFeeModuleFactory(address _swapFeeModuleFactory) external;

    function removeUniversalOracleModuleFactory(address _universalOracleModuleFactory) external;

    function removeSovereignOracleModuleFactory(address _sovereignOracleModuleFactory) external;
}
