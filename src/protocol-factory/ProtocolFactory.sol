// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { EnumerableSet } from 'lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol';
import { Address } from 'lib/openzeppelin-contracts/contracts/utils/Address.sol';

import { IProtocolFactory } from 'src/protocol-factory/interfaces/IProtocolFactory.sol';
import { IValantisDeployer } from 'src/protocol-factory/interfaces/IValantisDeployer.sol';
import { IPoolGaugeDeployer } from 'src/protocol-factory/interfaces/IPoolGaugeDeployer.sol';
import { IPoolDeployer } from 'src/protocol-factory/interfaces/IPoolDeployer.sol';
import { ISovereignPool } from 'src/pools/interfaces/ISovereignPool.sol';
import { IUniversalPool } from 'src/pools/interfaces/IUniversalPool.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';
import { IAuctionController } from 'src/governance/auctions/interfaces/IAuctionController.sol';

contract ProtocolFactory is IProtocolFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error ProtocolFactory__auctionControllerNotSet();
    error ProtocolFactory__deploySovereignPool_alreadySet();
    error ProtocolFactory__deploySovereignGauge_alreadySet();
    error ProtocolFactory__deploySovereignGauge_invalidSovereignPool();
    error ProtocolFactory__deploySovereignGauge_onlyPoolManager();
    error ProtocolFactory__deployUniversalPool_alreadySet();
    error ProtocolFactory__deployUniversalGauge_alreadySet();
    error ProtocolFactory__deployUniversalGauge_invalidUniversalPool();
    error ProtocolFactory__deployUniversalGauge_onlyPoolManager();
    error ProtocolFactory__emissionsControllerNotSet();
    error ProtocolFactory__onlyProtocolDeployer();
    error ProtocolFactory__onlyProtocolManager();
    error ProtocolFactory__invalidALMFactory();
    error ProtocolFactory__invalidBlockTime();
    error ProtocolFactory__invalidBytecode();
    error ProtocolFactory__invalidSovereignOracleModuleFactory();
    error ProtocolFactory__invalidSovereignPool();
    error ProtocolFactory__invalidSwapFeeModuleFactory();
    error ProtocolFactory__invalidUniversalOracleModuleFactory();
    error ProtocolFactory__invalidUniversalPool();
    error ProtocolFactory__zeroAddress();
    error ProtocolFactory__addressWithContract();
    error ProtocolFactory__invalidDeployment();
    error ProtocolFactory__noContractDeployed();
    error ProtocolFactory__poolAlreadyExists();
    error ProtocolFactory__setAuctionController_alreadySet();
    error ProtocolFactory__setEmissionsController_alreadySet();
    error ProtocolFactory__setGovernanceToken_alreadySet();
    error ProtocolFactory__setProtocolManager_alreadySet();
    error ProtocolFactory__setSovereignPoolFactory_alreadySet();
    error ProtocolFactory__setUniversalPoolFactory_alreadySet();
    error ProtocolFactory__setPoolGaugeFactory_alreadySet();
    error ProtocolFactory__setUniversalGaugeFactory_alreadySet();
    error ProtocolFactory__setSovereignGaugeFactory_alreadySet();
    error ProtocolFactory__tokenNotContract();
    error ProtocolFactory__valTokenNotSet();
    error ProtocolFactory___addFactory_alreadyAdded();
    error ProtocolFactory___removeFactory_notWhitelisted();

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    address public immutable protocolDeployer;

    // solhint-disable-next-line var-name-mixedcase
    uint256 public immutable BLOCK_TIME;

    /************************************************
     *  STORAGE
     ***********************************************/

    /**
        @notice Mapping of token pair and ALM to set of Universal pools.
     */
    mapping(address => mapping(address => EnumerableSet.AddressSet)) private _universalPools;

    /**
        @notice Mapping of token pair and ALM to set of Sovereign pools.
     */
    mapping(address => mapping(address => EnumerableSet.AddressSet)) private _sovereignPools;

    /**
        @notice Set of whitelisted Universal ALM factories.
     */
    EnumerableSet.AddressSet private _universalALMFactories;

    /**
        @notice Set of whitelisted Sovereign ALM factories.
     */
    EnumerableSet.AddressSet private _sovereignALMFactories;

    /**
        @notice Set of whitelisted Swap Fee Module factories.
     */
    EnumerableSet.AddressSet private _swapFeeModuleFactories;

    /**
        @notice Set of whitelisted Universal Oracle factories. 
     */
    EnumerableSet.AddressSet private _universalOracleModuleFactories;

    /**
        @notice Set of whitelisted Sovereign Oracle factories. 
     */
    EnumerableSet.AddressSet private _sovereignOracleModuleFactories;

    /**
        @notice Bytecode hash for each ALM.
     */
    mapping(address => bytes32) public universalALMCodeHashes;

    /**
        @notice Bytecode hash for each ALM.
     */
    mapping(address => bytes32) public sovereignALMCodeHashes;

    /**
        @notice Bytecode hash for each Swap Fee Module.
     */
    mapping(address => bytes32) public swapFeeModuleCodeHashes;

    /**
        @notice Bytecode hash for each Universal Oracle module. 
     */
    mapping(address => bytes32) public universalOracleModuleCodeHashes;

    /**
        @notice Bytecode hash for each Sovereign Oracle module. 
     */
    mapping(address => bytes32) public sovereignOracleModuleCodeHashes;

    /**
        @notice Mapping of ALM position and its respective factory.
     */
    mapping(address => address) public almFactories;

    /**
        @notice Mapping of ALM position and its respective pool.
     */
    mapping(address => address) public almPositionPools;

    /**
        @notice Mapping of Swap Fee Module and its respective pool.
     */
    mapping(address => address) public swapFeeModules;

    /**
        @notice Mapping of Universal Oracle module and its respective pool. 
     */
    mapping(address => address) public universalOracleModules;

    /**
        @notice Mapping of Sovereign Oracle module and its respective pool.
        */
    mapping(address => address) public sovereignOracleModules;

    /**
        @notice Mapping of gauge and its respective pool.
     */
    mapping(address => address) public poolByGauge;

    /**
        @notice Mapping of pool and its respective gauge.
     */
    mapping(address => address) public gaugeByPool;

    /**
        @notice Auction Controller.
     */
    address public auctionController;

    /**
        @notice Emissions Controller.
     */
    address public emissionsController;

    /**
        @notice Nonce which gets incremented whenever an ALM gets deployed.
     */
    uint256 public almNonce;

    /**
        @notice Nonce which gets incremented whenever a Swap Fee Module gets deployed. 
     */
    uint256 public swapFeeModuleNonce;

    /**
        @notice Nonce which gets incremented whenever a Universal Oracle Module gets deployed.
     */
    uint256 public universalOracleModuleNonce;

    /**
        @notice Nonce which gets incremented wheneber a Sovereign Oracle Module gets deployed. 
     */
    uint256 public sovereignOracleModuleNonce;

    /**
        @notice Address of Protocol Governor executor.
        @dev Initially set as `protocolDeployer` in case Governance is not ready on the deployed chain. 
     */
    address public protocolManager;

    /**
        @notice Address of Valantis DAO token. 
     */
    address public governanceToken;

    /**
        @notice Factory contract to deploy Universal pools. 
     */
    address public universalPoolFactory;

    /**
        @notice Factory contract to deploy Sovereign pools. 
     */
    address public sovereignPoolFactory;

    /**
        @notice Factory contract to deploy Gauges for Universal pools. 
     */
    address public universalGaugeFactory;

    /**
        @notice Factory contract to deploy Gauges for Sovereign Pools. 
     */
    address public sovereignGaugeFactory;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    function _onlyProtocolDeployer() private view {
        if (msg.sender != protocolDeployer) {
            revert ProtocolFactory__onlyProtocolDeployer();
        }
    }

    function _onlyProtocolManager() private view {
        if (msg.sender != protocolManager) {
            revert ProtocolFactory__onlyProtocolManager();
        }
    }

    modifier onlyProtocolDeployer() {
        _onlyProtocolDeployer();
        _;
    }

    modifier onlyProtocolManager() {
        _onlyProtocolManager();
        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(address _protocolDeployer, uint32 _blockTime) {
        if (_protocolDeployer == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        // Protocol manager initially set as protocol deployer.
        protocolManager = _protocolDeployer;
        protocolDeployer = _protocolDeployer;

        if (_blockTime == 0) {
            revert ProtocolFactory__invalidBlockTime();
        }
        BLOCK_TIME = uint256(_blockTime);
    }

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/

    function getUniversalALMFactories() external view override returns (address[] memory) {
        return _universalALMFactories.values();
    }

    function getSovereignALMFactories() external view override returns (address[] memory) {
        return _sovereignALMFactories.values();
    }

    function getSwapFeeModuleFactories() external view override returns (address[] memory) {
        return _swapFeeModuleFactories.values();
    }

    function getUniversalOracleModuleFactories() external view override returns (address[] memory) {
        return _universalOracleModuleFactories.values();
    }

    function getSovereignOracleModuleFactories() external view override returns (address[] memory) {
        return _sovereignOracleModuleFactories.values();
    }

    function isValidUniversalPool(address _pool) external view override returns (bool) {
        return _isValidUniversalPool(_pool);
    }

    function isValidSovereignPool(address _pool) external view override returns (bool) {
        return _isValidSovereignPool(_pool);
    }

    function isValidUniversalALMPosition(address _almPosition) external view override returns (bool) {
        address almFactory = almFactories[_almPosition];

        if (almFactory == address(0)) {
            return false;
        }

        return _universalALMFactories.contains(almFactory);
    }

    function isValidSovereignALMPosition(address _almPosition) external view override returns (bool) {
        address almFactory = almFactories[_almPosition];

        if (almFactory == address(0)) {
            return false;
        }

        return _sovereignALMFactories.contains(almFactory);
    }

    function isValidSwapFeeModule(address _swapFeeModule) external view override returns (bool) {
        address swapFeeModuleFactory = swapFeeModules[_swapFeeModule];

        if (swapFeeModuleFactory == address(0)) {
            return false;
        }

        return _swapFeeModuleFactories.contains(swapFeeModuleFactory);
    }

    function isValidUniversalOracleModule(address _universalOracleModule) external view override returns (bool) {
        address universalOracleModuleFactory = universalOracleModules[_universalOracleModule];

        if (universalOracleModuleFactory == address(0)) {
            return false;
        }

        return _universalOracleModuleFactories.contains(universalOracleModuleFactory);
    }

    function isValidSovereignOracleModule(address _sovereignOracleModule) external view override returns (bool) {
        address sovereignOracleModuleFactory = sovereignOracleModules[_sovereignOracleModule];

        if (sovereignOracleModuleFactory == address(0)) {
            return false;
        }

        return _sovereignOracleModuleFactories.contains(sovereignOracleModuleFactory);
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Set Valantis DAO Token address.
        @param _governanceToken Address of Valantis DAO Token.
        @dev To be called only once by `protocolDeployer`.
     */
    function setGovernanceToken(address _governanceToken) external override onlyProtocolDeployer {
        if (_governanceToken == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (governanceToken != address(0)) {
            revert ProtocolFactory__setGovernanceToken_alreadySet();
        }

        governanceToken = _governanceToken;

        emit GovernanceTokenSet(_governanceToken);
    }

    /**
        @notice Set `protocolManager`.
        @param _protocolManager Address of protocol manager.
        @dev To be called only once by `protocolDeployer`. 
     */
    function setProtocolManager(address _protocolManager) external override onlyProtocolDeployer {
        if (_protocolManager == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (protocolManager != protocolDeployer) {
            revert ProtocolFactory__setProtocolManager_alreadySet();
        }

        protocolManager = _protocolManager;

        emit ProtocolManagerSet(_protocolManager);
    }

    /**
        @notice Set Universal pool factory.
        @param _universalPoolFactory Address of Universal pool factory.
        @dev To be called only once by `protocolDeployer`. 
     */
    function setUniversalPoolFactory(address _universalPoolFactory) external override onlyProtocolDeployer {
        if (_universalPoolFactory == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (universalPoolFactory != address(0)) {
            revert ProtocolFactory__setUniversalPoolFactory_alreadySet();
        }

        universalPoolFactory = _universalPoolFactory;

        emit UniversalPoolFactorySet(_universalPoolFactory);
    }

    /**
        @notice Set Sovereign pool factory.
        @param _sovereignPoolFactory Address of Sovereign pool factory.
        @dev To be called only once by `protocolDeployer`. 
     */
    function setSovereignPoolFactory(address _sovereignPoolFactory) external override onlyProtocolDeployer {
        if (_sovereignPoolFactory == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (sovereignPoolFactory != address(0)) {
            revert ProtocolFactory__setSovereignPoolFactory_alreadySet();
        }

        sovereignPoolFactory = _sovereignPoolFactory;

        emit SovereignPoolFactorySet(_sovereignPoolFactory);
    }

    /**
        @notice Set and initialize Auction controller.
        @param _auctionController Address of Auction controller.
        @dev To be called only once by `protocolDeployer`. 
     */
    function setAuctionController(address _auctionController) external override onlyProtocolDeployer {
        if (_auctionController == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (address(auctionController) != address(0)) {
            revert ProtocolFactory__setAuctionController_alreadySet();
        }

        auctionController = _auctionController;

        IAuctionController(_auctionController).initiateAuctionController();

        emit AuctionControllerSet(_auctionController);
    }

    /**
        @notice Set Emissions controller.
        @param _emissionsController Address of Emissions controller.
        @dev To be called only once by `protocolDeployer`. 
     */
    function setEmissionsController(address _emissionsController) external override onlyProtocolDeployer {
        if (_emissionsController == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (emissionsController != address(0)) {
            revert ProtocolFactory__setEmissionsController_alreadySet();
        }

        emissionsController = _emissionsController;

        emit EmissionsControllerSet(_emissionsController);
    }

    /**
        @notice Sets Universal Pool Gauge Factory address.
        @param _universalGaugeFactory Address of the Universal Pool Gauge factory.
     */
    function setUniversalGaugeFactory(address _universalGaugeFactory) external override onlyProtocolDeployer {
        if (_universalGaugeFactory == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (universalGaugeFactory != address(0)) {
            revert ProtocolFactory__setUniversalGaugeFactory_alreadySet();
        }

        universalGaugeFactory = _universalGaugeFactory;

        emit UniversalGaugeFactorySet(_universalGaugeFactory);
    }

    /**
        @notice Set Sovereign pool gauge factory address.
        @param _sovereignGaugeFactory Address of Sovereign Pool Gauge factory.
     */
    function setSovereignGaugeFactory(address _sovereignGaugeFactory) external override onlyProtocolDeployer {
        if (_sovereignGaugeFactory == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (sovereignGaugeFactory != address(0)) {
            revert ProtocolFactory__setSovereignGaugeFactory_alreadySet();
        }

        sovereignGaugeFactory = _sovereignGaugeFactory;

        emit SovereignGaugeFactorySet(_sovereignGaugeFactory);
    }

    /**
        @notice Deploy an ALM instance for an existing Universal pool.
        @param _pool Address of existing Universal pool.
        @param _almFactory ALM Factory responsible for deploying ALM position.
        @param _constructorArgs Constructor arguments to initialize deployed ALM position.
               If not required, can be passed as bytes(0).
        @return alm Address of deployed ALM position.
     */
    function deployALMPositionForUniversalPool(
        address _pool,
        address _almFactory,
        bytes calldata _constructorArgs
    ) external override returns (address alm) {
        if (!_isValidUniversalPool(_pool)) {
            revert ProtocolFactory__invalidUniversalPool();
        }

        alm = _deployALMPositionForPool(true, _pool, _almFactory, _constructorArgs);

        emit UniversalALMDeployed(alm, _pool, _almFactory);
    }

    /**
        @notice Deploy an ALM instance for an existing Sovereign pool.
        @param _pool Address of existing Sovereign pool.
        @param _almFactory ALM Factory responsible for deploying ALM position.
        @param _constructorArgs Constructor arguments to initialize deployed ALM position.
               If not required, can be passed as bytes(0).
        @return alm Address of deployed ALM position.
     */
    function deployALMPositionForSovereignPool(
        address _pool,
        address _almFactory,
        bytes calldata _constructorArgs
    ) external override returns (address alm) {
        if (!_isValidSovereignPool(_pool)) {
            revert ProtocolFactory__invalidSovereignPool();
        }

        alm = _deployALMPositionForPool(false, _pool, _almFactory, _constructorArgs);

        emit SovereignALMDeployed(alm, _pool, _almFactory);
    }

    /**
        @notice Deploy a Swap Fee Module instance for an existing pool.
        @param _pool Address of existing pool.
        @param _swapFeeModuleFactory Swap Fee Module Factory responsible for deploying an instance.
        @param _constructorArgs Constructor arguments to initialized deployed Swap Fee Module instance.
               If not required, can be passed as bytes(0).
        @return swapFeeModule Address of deployed Swap Fee Module instance.
     */
    function deploySwapFeeModuleForPool(
        address _pool,
        address _swapFeeModuleFactory,
        bytes calldata _constructorArgs
    ) external override returns (address swapFeeModule) {
        bool isValidUniversalPool_ = _isValidUniversalPool(_pool);
        bool isValidSovereignPool_ = _isValidSovereignPool(_pool);

        if (!isValidUniversalPool_ && !isValidSovereignPool_) {
            if (!isValidUniversalPool_) {
                revert ProtocolFactory__invalidUniversalPool();
            } else {
                revert ProtocolFactory__invalidSovereignPool();
            }
        }

        if (!_swapFeeModuleFactories.contains(_swapFeeModuleFactory)) {
            revert ProtocolFactory__invalidSwapFeeModuleFactory();
        }

        uint256 swapFeeModuleNonceCache = swapFeeModuleNonce;
        bytes32 salt = keccak256(abi.encode(_pool, _swapFeeModuleFactory, swapFeeModuleNonceCache));
        swapFeeModuleNonce = swapFeeModuleNonceCache + 1;

        bytes32 expectedBytecodeHash = swapFeeModuleCodeHashes[_swapFeeModuleFactory];
        swapFeeModule = _deployViaFactory(expectedBytecodeHash, salt, _swapFeeModuleFactory, _constructorArgs);

        // Store mapping for ALM and its factory
        swapFeeModules[swapFeeModule] = _swapFeeModuleFactory;

        emit SwapFeeModuleDeployed(swapFeeModule, _pool, _swapFeeModuleFactory);
    }

    /**
        @notice Deploy a Universal Oracle Module instance for an existing pool.
        @param _pool Address of existing pool.
        @param _universalOracleModuleFactory Universal Oracle Module Factory responsible for deploying an instance.
        @param _constructorArgs Constructor arguments to initialized deployed Universal Oracle Module instance.
               If not required, can be passed as bytes(0).
        @return universalOracleModule Address of deployed Universal Oracle Module instance.
     */
    function deployUniversalOracleForPool(
        address _pool,
        address _universalOracleModuleFactory,
        bytes calldata _constructorArgs
    ) external override returns (address universalOracleModule) {
        if (!_isValidUniversalPool(_pool)) {
            revert ProtocolFactory__invalidUniversalPool();
        }

        if (!_universalOracleModuleFactories.contains(_universalOracleModuleFactory)) {
            revert ProtocolFactory__invalidUniversalOracleModuleFactory();
        }

        uint256 universalOracleModuleNonceCache = universalOracleModuleNonce;
        bytes32 salt = keccak256(abi.encode(_pool, _universalOracleModuleFactory, universalOracleModuleNonceCache));
        universalOracleModuleNonce = universalOracleModuleNonceCache + 1;

        bytes32 expectedBytecodeHash = universalOracleModuleCodeHashes[_universalOracleModuleFactory];
        universalOracleModule = _deployViaFactory(
            expectedBytecodeHash,
            salt,
            _universalOracleModuleFactory,
            _constructorArgs
        );

        universalOracleModules[universalOracleModule] = _universalOracleModuleFactory;

        emit UniversalOracleDeployed(universalOracleModule, _pool, _universalOracleModuleFactory);
    }

    /**
        @notice Deploy a Sovereign Oracle Module instance for an existing pool.
        @param _pool Address of existing pool.
        @param _sovereignOracleModuleFactory Sovereign Oracle Module Factory responsible for deploying an instance.
        @param _constructorArgs Constructor arguments to initialized deployed Sovereign Oracle Module instance.
               If not required, can be passed as bytes(0).
        @return sovereignOracleModule Address of deployed Sovereign Oracle Module instance.
     */
    function deploySovereignOracleForPool(
        address _pool,
        address _sovereignOracleModuleFactory,
        bytes calldata _constructorArgs
    ) external override returns (address sovereignOracleModule) {
        if (!_isValidSovereignPool(_pool)) {
            revert ProtocolFactory__invalidSovereignPool();
        }

        if (!_sovereignOracleModuleFactories.contains(_sovereignOracleModuleFactory)) {
            revert ProtocolFactory__invalidSovereignOracleModuleFactory();
        }

        uint256 sovereignOracleModuleNonceCache = sovereignOracleModuleNonce;
        bytes32 salt = keccak256(abi.encode(_pool, _sovereignOracleModuleFactory, sovereignOracleModuleNonceCache));
        sovereignOracleModuleNonce = sovereignOracleModuleNonceCache + 1;

        bytes32 expectedBytecodeHash = sovereignOracleModuleCodeHashes[_sovereignOracleModuleFactory];
        sovereignOracleModule = _deployViaFactory(
            expectedBytecodeHash,
            salt,
            _sovereignOracleModuleFactory,
            _constructorArgs
        );

        sovereignOracleModules[sovereignOracleModule] = _sovereignOracleModuleFactory;

        emit UniversalOracleDeployed(sovereignOracleModule, _pool, _sovereignOracleModuleFactory);
    }

    /**
        @notice Deploy Universal pool.
        @param _token0 Address of token0.
        @param _token1 Address of token1.
        @param _poolManager Address of pool manager.
        @param _defaultSwapFeeBips Constant swap fee for the pool.
        @dev   Can be overriden later by deploying a custom Swap Fee Module. 
        @return pool Address of deployed Universal Pool.
     */
    function deployUniversalPool(
        address _token0,
        address _token1,
        address _poolManager,
        uint256 _defaultSwapFeeBips
    ) external override returns (address pool) {
        if (!Address.isContract(_token0) || !Address.isContract(_token1)) {
            revert ProtocolFactory__tokenNotContract();
        }

        pool = IPoolDeployer(universalPoolFactory).deploy(
            bytes32(0),
            abi.encode(_token0, _token1, address(this), _poolManager, _defaultSwapFeeBips)
        );

        _universalPools[_token0][_token1].add(pool);
        _universalPools[_token1][_token0].add(pool);

        emit UniversalPoolDeployed(_token0, _token1, pool);
    }

    /**
        @notice Deploy a Gauge for an existing Universal Pool.
        @param _pool Address of Universal pool.
        @param _manager Address of Universal Gauge's manager.
        @return gauge Address of deployed Universal Pool Gauge.
     */
    function deployUniversalGauge(address _pool, address _manager) external override returns (address gauge) {
        if (!_isValidUniversalPool(_pool)) {
            revert ProtocolFactory__invalidUniversalPool();
        }

        // {
        //     address poolManager = IUniversalPool(_pool).state().poolManager;
        //     if (poolManager != address(0) && msg.sender != poolManager) {
        //         revert ProtocolFactory__deployUniversalGauge_onlyPoolManager();
        //     } else if (poolManager == address(0) && msg.sender != protocolManager) {
        //         revert ProtocolFactory__deployUniversalGauge_onlyPoolManager();
        //     }
        // }

        if (gaugeByPool[_pool] != address(0)) {
            revert ProtocolFactory__deployUniversalGauge_alreadySet();
        }

        if (address(auctionController) == address(0)) {
            revert ProtocolFactory__auctionControllerNotSet();
        }

        if (emissionsController == address(0)) {
            revert ProtocolFactory__emissionsControllerNotSet();
        }

        if (address(governanceToken) == address(0)) {
            revert ProtocolFactory__valTokenNotSet();
        }

        bytes memory constructorArgs = abi.encode(
            _pool,
            _manager,
            address(auctionController),
            emissionsController,
            address(governanceToken)
        );
        gauge = IPoolGaugeDeployer(universalGaugeFactory).deploy(bytes32(0), constructorArgs);

        // Update pool state with new gauge
        IUniversalPool(_pool).setGauge(gauge);

        gaugeByPool[_pool] = gauge;
        poolByGauge[gauge] = _pool;

        emit UniversalGaugeDeployed(gauge, _pool, _manager);

        return gauge;
    }

    /**
        @notice Deploy Sovereign Pool.
        @param args Struct containing all required constructor args:
               *token0 Address of token0.
               *token1 Address of token1.
               *protocolFactory Address of Protocol Factory.
                 Will always be overriden as this contract's address.
               *poolManager Address of Sovereign Pool manager.
               *sovereignVault Address which is meant to hold pool's reserves.
                 If passsed as null address, `pool` will hold reserves.
               *isToken0Rebase True if token0 is a rebase token.
               *isToken1Rebase True if token1 is a rebase token.
               *token0AbsErrorTolerance Maximum absolute error allowed on rebase token transfers.
                 Only applicable if isToken0Rebase=True.
               *token1AbsErrorTolerance Maximum absolute error allowed on rebase token transfers.
                 Only applicable if isToken1Rebase=True.
               *token0MinAmount Minimum amount of token0 required for deposits.
               *token1MinAmount Minimum amount of token1 required for deposits.
               *defaultSwapFeeBips Default constant swap fee in basis-points.
        @return pool Address of deployed Sovereign Pool. 
     */
    function deploySovereignPool(SovereignPoolConstructorArgs memory args) external override returns (address pool) {
        if (!Address.isContract(args.token0) || !Address.isContract(args.token1)) {
            revert ProtocolFactory__tokenNotContract();
        }

        args.protocolFactory = address(this);

        pool = IPoolDeployer(sovereignPoolFactory).deploy(bytes32(0), abi.encode(args));

        _sovereignPools[args.token0][args.token1].add(pool);
        _sovereignPools[args.token1][args.token0].add(pool);

        emit SovereignPoolDeployed(args.token0, args.token1, pool);
    }

    /**
        @notice Deploy a Gauge for an existing Sovereign Pool.
        @param _pool Address of deployed Sovereign Pool.
        @param _manager Address of Sovereign Pool Gauge manager.
        @return gauge Address of deployed Sovereing Pool Gauge.
     */
    function deploySovereignGauge(address _pool, address _manager) external override returns (address gauge) {
        if (!_isValidSovereignPool(_pool)) {
            revert ProtocolFactory__invalidSovereignPool();
        }

        {
            address poolManager = ISovereignPool(_pool).poolManager();
            if (poolManager != address(0) && msg.sender != poolManager) {
                revert ProtocolFactory__deploySovereignGauge_onlyPoolManager();
            } else if (poolManager == address(0) && msg.sender != protocolManager) {
                revert ProtocolFactory__deploySovereignGauge_onlyPoolManager();
            }
        }

        if (gaugeByPool[_pool] != address(0)) {
            revert ProtocolFactory__deploySovereignGauge_alreadySet();
        }

        if (address(auctionController) == address(0)) {
            revert ProtocolFactory__auctionControllerNotSet();
        }

        if (emissionsController == address(0)) {
            revert ProtocolFactory__emissionsControllerNotSet();
        }

        if (address(governanceToken) == address(0)) {
            revert ProtocolFactory__valTokenNotSet();
        }

        bytes memory constructorArgs = abi.encode(
            _pool,
            _manager,
            address(auctionController),
            emissionsController,
            address(governanceToken)
        );
        gauge = IPoolGaugeDeployer(sovereignGaugeFactory).deploy(bytes32(0), constructorArgs);

        gaugeByPool[_pool] = gauge;
        poolByGauge[gauge] = _pool;

        emit SovereignGaugeDeployed(gauge, _pool, _manager);

        return gauge;
    }

    /**
        @notice Add Universal ALM factory to the whitelist.
        @param _almFactory Address of Universal ALM factory to add.
     */
    function addUniversalALMFactory(address _almFactory) external override onlyProtocolManager {
        _addFactory(_almFactory, _universalALMFactories, universalALMCodeHashes);

        emit UniversalALMFactoryAdded(_almFactory);
    }

    /**
        @notice Add Sovereign ALM factory to the whitelist.
        @param _almFactory Address of Sovereign ALM factory to add.
     */
    function addSovereignALMFactory(address _almFactory) external override onlyProtocolManager {
        _addFactory(_almFactory, _sovereignALMFactories, sovereignALMCodeHashes);

        emit SovereignALMFactoryAdded(_almFactory);
    }

    /**
        @notice Add Swap Fee Module factory to the whitelist.
        @param _swapFeeModuleFactory Address of Swap Fee Module factory to add.
     */
    function addSwapFeeModuleFactory(address _swapFeeModuleFactory) external override onlyProtocolManager {
        _addFactory(_swapFeeModuleFactory, _swapFeeModuleFactories, swapFeeModuleCodeHashes);

        emit SwapFeeModuleFactoryAdded(_swapFeeModuleFactory);
    }

    /**
        @notice Add Universal Oracle Module factory to the whitelist.
        @param _universalOracleModuleFactory Address of Universal Oracle Module factory to add.
     */
    function addUniversalOracleModuleFactory(
        address _universalOracleModuleFactory
    ) external override onlyProtocolManager {
        _addFactory(_universalOracleModuleFactory, _universalOracleModuleFactories, universalOracleModuleCodeHashes);

        emit UniversalOracleFactoryAdded(_universalOracleModuleFactory);
    }

    /**
        @notice Add Sovereign Oracle Module factory to the whitelist.
        @param _sovereignOracleModuleFactory Address of Sovereign Oracle Module factory to add.
     */
    function addSovereignOracleModuleFactory(
        address _sovereignOracleModuleFactory
    ) external override onlyProtocolManager {
        _addFactory(_sovereignOracleModuleFactory, _sovereignOracleModuleFactories, sovereignOracleModuleCodeHashes);

        emit SovereignOracleFactoryAdded(_sovereignOracleModuleFactory);
    }

    /**
        @notice Remove `_almFactory` from the whitelist.
        @param _almFactory Address of Universal ALM factory to remove. 
     */
    function removeUniversalALMFactory(address _almFactory) external override onlyProtocolManager {
        _removeFactory(_almFactory, _universalALMFactories, universalALMCodeHashes);

        emit UniversalALMFactoryRemoved(_almFactory);
    }

    /**
        @notice Remove `_almFactory` from the whitelist.
        @param _almFactory Address of Sovereign ALM factory to remove. 
     */
    function removeSovereignALMFactory(address _almFactory) external override onlyProtocolManager {
        _removeFactory(_almFactory, _sovereignALMFactories, sovereignALMCodeHashes);

        emit SovereignALMFactoryRemoved(_almFactory);
    }

    /**
        @notice Remove `_almFactory` from the whitelist.
        @param _swapFeeModuleFactory Address of Swap Fee Module factory to remove. 
     */
    function removeSwapFeeModuleFactory(address _swapFeeModuleFactory) external override onlyProtocolManager {
        _removeFactory(_swapFeeModuleFactory, _swapFeeModuleFactories, swapFeeModuleCodeHashes);

        emit SwapFeeModuleFactoryRemoved(_swapFeeModuleFactory);
    }

    /**
        @notice Remove `_universalOracleModuleFactory` from the whitelist.
        @param _universalOracleModuleFactory Address of Universal Oracle Module factory to remove. 
     */
    function removeUniversalOracleModuleFactory(
        address _universalOracleModuleFactory
    ) external override onlyProtocolManager {
        _removeFactory(_universalOracleModuleFactory, _universalOracleModuleFactories, universalOracleModuleCodeHashes);

        emit UniversalOracleFactoryRemoved(_universalOracleModuleFactory);
    }

    /**
        @notice Remove `_sovereignOracleModuleFactory` from the whitelist.
        @param _sovereignOracleModuleFactory Address of Sovereign Oracle Module factory to remove. 
    */
    function removeSovereignOracleModuleFactory(
        address _sovereignOracleModuleFactory
    ) external override onlyProtocolManager {
        _removeFactory(_sovereignOracleModuleFactory, _sovereignOracleModuleFactories, sovereignOracleModuleCodeHashes);

        emit SovereignOracleFactoryRemoved(_sovereignOracleModuleFactory);
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    function _addFactory(
        address factory,
        EnumerableSet.AddressSet storage factories,
        mapping(address => bytes32) storage factoryCodeHashes
    ) private {
        if (factory == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (factories.contains(factory)) {
            revert ProtocolFactory___addFactory_alreadyAdded();
        }

        bytes memory bytecode = IValantisDeployer(factory).getContractBytecode();
        bytes32 bytecodeHash = keccak256(bytecode);

        factoryCodeHashes[factory] = bytecodeHash;

        factories.add(factory);
    }

    function _removeFactory(
        address factory,
        EnumerableSet.AddressSet storage factories,
        mapping(address => bytes32) storage factoryCodeHashes
    ) private {
        if (factory == address(0)) {
            revert ProtocolFactory__zeroAddress();
        }

        if (!factories.contains(factory)) {
            revert ProtocolFactory___removeFactory_notWhitelisted();
        }

        factoryCodeHashes[factory] = 0;

        factories.remove(factory);
    }

    function _deployALMPositionForPool(
        bool isUniversalPool,
        address pool,
        address almFactory,
        bytes calldata constructorArgs
    ) private returns (address alm) {
        if (
            (isUniversalPool && !_universalALMFactories.contains(almFactory)) ||
            (!isUniversalPool && !_sovereignALMFactories.contains(almFactory))
        ) {
            revert ProtocolFactory__invalidALMFactory();
        }

        uint256 almNonceCache = almNonce;
        bytes32 salt = keccak256(abi.encode(pool, almFactory, almNonceCache));
        almNonce = almNonceCache + 1;

        bytes32 expectedBytecodeHash = isUniversalPool
            ? universalALMCodeHashes[almFactory]
            : sovereignALMCodeHashes[almFactory];
        alm = _deployViaFactory(expectedBytecodeHash, salt, almFactory, constructorArgs);

        // Store mapping for ALM and its factory
        almFactories[alm] = almFactory;

        // Store mapping for ALM and its pool
        almPositionPools[alm] = pool;
    }

    function _deployViaFactory(
        bytes32 expectedBytecodeHash,
        bytes32 salt,
        address factory,
        bytes calldata constructorArgs
    ) private returns (address create2Address) {
        // This deployment function has several pre and post conditions
        // to ensure that a factory cannot deploy arbitrary bytecode,
        // only bytecode whose hash is the same set at initialization.
        bytes memory bytecode = IValantisDeployer(factory).getContractBytecode();
        bytes32 bytecodeHash = keccak256(bytecode);

        if (bytecodeHash != expectedBytecodeHash) {
            revert ProtocolFactory__invalidBytecode();
        }

        bool hasConstructorArgs = keccak256(constructorArgs) != keccak256(new bytes(0));
        if (hasConstructorArgs) {
            bytecode = abi.encodePacked(bytecode, constructorArgs);
        }

        bytes32 create2Hash = keccak256(abi.encodePacked(bytes1(0xff), factory, salt, keccak256(bytecode)));

        create2Address = address(uint160(uint256(create2Hash)));

        if (Address.isContract(create2Address)) {
            revert ProtocolFactory__addressWithContract();
        }

        IValantisDeployer(factory).deploy(salt, constructorArgs);

        if (!Address.isContract(create2Address)) {
            revert ProtocolFactory__noContractDeployed();
        }
    }

    function _isValidUniversalPool(address pool) private view returns (bool) {
        IUniversalPool poolInterface = IUniversalPool(pool);

        return _universalPools[poolInterface.token0()][poolInterface.token1()].contains(pool);
    }

    function _isValidSovereignPool(address pool) private view returns (bool) {
        ISovereignPool poolInterface = ISovereignPool(pool);

        return _sovereignPools[poolInterface.token0()][poolInterface.token1()].contains(pool);
    }
}
