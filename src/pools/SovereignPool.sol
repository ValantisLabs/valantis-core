// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { Constants } from '../utils/Constants.sol';
import { ReentrancyGuard } from '../utils/ReentrancyGuard.sol';
import { ISwapFeeModule, SwapFeeModuleData } from '../swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { ISovereignPool } from './interfaces/ISovereignPool.sol';
import { ISovereignPoolSwapCallback } from './interfaces/ISovereignPoolSwapCallback.sol';
import { IVerifierModule } from './interfaces/IVerifierModule.sol';
import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from '../ALM/structs/SovereignALMStructs.sol';
import { ISovereignVaultMinimal } from './interfaces/ISovereignVaultMinimal.sol';
import { ISovereignALM } from '../ALM/interfaces/ISovereignALM.sol';
import { ISovereignOracle } from '../oracles/interfaces/ISovereignOracle.sol';
import { SovereignPoolConstructorArgs, SwapCache, SovereignPoolSwapParams } from './structs/SovereignPoolStructs.sol';
import { IFlashBorrower } from './interfaces/IFlashBorrower.sol';

/**
    @notice Valantis Sovereign Pool
    @dev Sovereign Pools contain the following Modules:
        - Swap Fee Module (Optional): Calculates swap fees.
        - Algorithmic Liquidity Module (ALM): Contains any kind of DEX logic.
        - Oracle Module (Optional): Can checkpoint swap data in order to
            build time-weighted price and/or volatility estimates.
        - Verifier Module (Optional): Manages custom access conditions for swaps, deposits and withdrawals.
        - Sovereign Vault (Optional): Allows LPs to store the funds in this contract instead of the pool.
            This allows for easier interoperability with other protocols and multi-token pool support.
            If not specified, the pool itself will hold the LPs' reserves.
 */
contract SovereignPool is ISovereignPool, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /************************************************
     *  ENUMS
     ***********************************************/

    /**
        @notice Verifier access types. 
     */
    enum AccessType {
        SWAP,
        DEPOSIT,
        WITHDRAW
    }

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error SovereignPool__ALMAlreadySet();
    error SovereignPool__excessiveToken0AbsErrorTolerance();
    error SovereignPool__excessiveToken1AbsErrorTolerance();
    error SovereignPool__onlyALM();
    error SovereignPool__onlyGauge();
    error SovereignPool__onlyPoolManager();
    error SovereignPool__onlyProtocolFactory();
    error SovereignPool__sameTokenNotAllowed();
    error SovereignPool__ZeroAddress();
    error SovereignPool__depositLiquidity_depositDisabled();
    error SovereignPool__depositLiquidity_excessiveToken0ErrorOnTransfer();
    error SovereignPool__depositLiquidity_excessiveToken1ErrorOnTransfer();
    error SovereignPool__depositLiquidity_incorrectTokenAmount();
    error SovereignPool__depositLiquidity_insufficientToken0Amount();
    error SovereignPool__depositLiquidity_insufficientToken1Amount();
    error SovereignPool__depositLiquidity_zeroTotalDepositAmount();
    error SovereignPool__getReserves_invalidReservesLength();
    error SovereignPool__setGauge_gaugeAlreadySet();
    error SovereignPool__setPoolManagerFeeBips_excessivePoolManagerFee();
    error SovereignPool__setSovereignOracle__sovereignOracleAlreadySet();
    error SovereignPool__swap_excessiveSwapFee();
    error SovereignPool__swap_expired();
    error SovereignPool__swap_invalidLiquidityQuote();
    error SovereignPool__swap_invalidPoolTokenOut();
    error SovereignPool__swap_invalidRecipient();
    error SovereignPool__swap_insufficientAmountIn();
    error SovereignPool__swap_invalidSwapTokenOut();
    error SovereignPool__swap_zeroAmountOut();
    error SovereignPool__setSwapFeeModule_timelock();
    error SovereignPool__withdrawLiquidity_insufficientReserve0();
    error SovereignPool__withdrawLiquidity_insufficientReserve1();
    error SovereignPool__withdrawLiquidity_invalidRecipient();
    error SovereignPool___claimPoolManagerFees_invalidFeeReceived();
    error SovereignPool___claimPoolManagerFees_invalidProtocolFee();
    error SovereignPool___handleTokenInOnSwap_excessiveTokenInErrorOnTransfer();
    error SovereignPool___handleTokenInOnSwap_invalidTokenInAmount();
    error SovereignPool___verifyPermission_onlyPermissionedAccess(address sender, uint8 accessType);

    /************************************************
     *  CONSTANTS
     ***********************************************/

    /**
        @notice Maximum swap fee is 50% of input amount. 
        @dev See docs for a more detailed explanation about how swap fees are applied.
     */
    uint256 private constant _MAX_SWAP_FEE_BIPS = 10_000;

    /**
        @notice `poolManager` can collect up to 50% of swap fees.
     */
    uint256 private constant _MAX_POOL_MANAGER_FEE_BIPS = 5_000;

    /**
        @notice Maximum allowed error tolerance on rebase token transfers.
        @dev    See:  https://github.com/lidofinance/lido-dao/issues/442.
     */
    uint256 private constant _MAX_ABS_ERROR_TOLERANCE = 10;

    /**
        @dev ERC-3156 onFlashLoan callback return data on success. 
     */
    bytes32 private constant _CALLBACK_SUCCESS = keccak256('ERC3156FlashBorrower.onFlashLoan');

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
        @notice Address of Sovereign Vault (Optional), where token reserves will be kept.
        @dev If set as this pool's address, it will work as a typical two token pool.
             Otherwise it can be set as any external vault or singleton. 
        @dev When sovereignVault is not this pool's address:
             - Reserves cannot be kept in the pool, hence `depositLiquidity` and `flashLoan` are disabled.
             - During swaps, input token must be transferred to `sovereignVault`.
             - During swaps, input token can only be token0 or token1.
               But if `sovereignVault != address(this)`, output token can be any other token.
     */
    address public immutable sovereignVault;

    /**
        @notice Address of Protocol Factory. 
     */
    address public immutable protocolFactory;

    /**
        @notice Default pool swap fee in basis-points (bips).
        @dev Can be overriden by whitelisting a Swap Fee Module.
        @dev See docs for a more detailed explanation about how swap fees are applied.
     */
    uint256 public immutable defaultSwapFeeBips;

    /**
        @notice Verifier Module (Optional).
        @dev Verifies custom authentication conditions on deposits, withdrawals and swaps. 
     */
    IVerifierModule private immutable _verifierModule;

    /**
        @notice Tokens supported by this pool.
        @dev These are not necessarily the only tokens
             available to trade against this pool:

             If `sovereignVault` == address(this):
               In this case only `_token0` and `_token1` can be exchanged.
             If `sovereignVault` != address(this):
               In this case `_token0` and `token1` can be the input token for a swap,
               but any other token can be quoted as the output token (given by calling `getTokens`).
     */
    IERC20 private immutable _token0;
    IERC20 private immutable _token1;

    /**
        @notice True if token0 is a rebase token. 
     */
    bool public immutable isToken0Rebase;

    /**
        @notice True if token1 is a rebase token. 
     */
    bool public immutable isToken1Rebase;

    /**
        @notice Maximum absolute error allowed on token0 transfers.
        @dev Only relevant if token0 is a rebase token.
             See: https://github.com/lidofinance/lido-dao/issues/442.
     */
    uint256 public immutable token0AbsErrorTolerance;

    /**
        @notice Maximum absolute error allowed on token1 transfers.
        @dev Only relevant if token1 is a rebase token.
             See: https://github.com/lidofinance/lido-dao/issues/442.
     */
    uint256 public immutable token1AbsErrorTolerance;

    /************************************************
     *  STORAGE
     ***********************************************/

    /**
        @notice Address of Sovereign ALM position bound to this pool.
        @dev Settable by `poolManager` only once. 
     */
    address public alm;

    /**
        @notice Address of Gauge bound to this pool. 
        @dev Settable by `protocolFactory` only once.
     */
    address public gauge;

    /**
        @notice Address of Pool Manager.
        @dev Can optionally set modules and parameters in this pool. 
     */
    address public poolManager;

    /**
        @notice Fraction of swap fees that go into `poolManager`, in bips.
        @dev Remaining fraction goes to LPs.
     */
    uint256 public poolManagerFeeBips;

    /**
        @notice Total token0 and token1 fees accrued by `poolManager`. 
     */
    uint256 public feePoolManager0;
    uint256 public feePoolManager1;

    /**
        @notice token0 and token1 fees donated to Gauges by `poolManager`.
     */
    uint256 public feeProtocol0;
    uint256 public feeProtocol1;

    /**
        @notice Block timestamp at or after which Swap Fee Module can be updated by `poolManager`.
        @dev This is meant to function as a time-lock to prevent `poolManager` from front-run user swaps,
             which could rapidly increase swap fees at arbitrary block times. 
     */
    uint256 public swapFeeModuleUpdateTimestamp;

    /**
        @notice token0 and token1 LP reserves.
     */
    uint256 private _reserve0;
    uint256 private _reserve1;

    /**
        @notice Sovereign Oracle Module (Optional).
        @dev Can accumulate swap data checkpoints and act as an on-chain price or volatility oracle.
     */
    ISovereignOracle private _sovereignOracleModule;

    /**
        @notice Swap Fee Module (Optional).
        @dev Defines custom logic to compute swap fees.
        @dev If not specified, a constant `defaultSwapFeeBips` will be used.
        @dev See docs for a more detailed explanation about how swap fees are applied.
     */
    ISwapFeeModule private _swapFeeModule;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyALM() {
        _onlyALM();
        _;
    }

    modifier onlyProtocolFactory() {
        _onlyProtocolFactory();
        _;
    }

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    modifier onlyGauge() {
        _onlyGauge();
        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(SovereignPoolConstructorArgs memory args) {
        if (args.token0 == args.token1) {
            revert SovereignPool__sameTokenNotAllowed();
        }

        if (args.token0 == address(0) || args.token1 == address(0)) {
            revert SovereignPool__ZeroAddress();
        }

        sovereignVault = args.sovereignVault == address(0) ? address(this) : args.sovereignVault;

        _verifierModule = IVerifierModule(args.verifierModule);

        _token0 = IERC20(args.token0);
        _token1 = IERC20(args.token1);

        protocolFactory = args.protocolFactory;

        poolManager = args.poolManager;

        isToken0Rebase = args.isToken0Rebase;
        isToken1Rebase = args.isToken1Rebase;

        // Irrelevant in case of non-rebase tokens
        if (args.token0AbsErrorTolerance > _MAX_ABS_ERROR_TOLERANCE) {
            revert SovereignPool__excessiveToken0AbsErrorTolerance();
        }

        if (args.token1AbsErrorTolerance > _MAX_ABS_ERROR_TOLERANCE) {
            revert SovereignPool__excessiveToken1AbsErrorTolerance();
        }

        token0AbsErrorTolerance = args.token0AbsErrorTolerance;
        token1AbsErrorTolerance = args.token1AbsErrorTolerance;

        defaultSwapFeeBips = args.defaultSwapFeeBips <= _MAX_SWAP_FEE_BIPS
            ? args.defaultSwapFeeBips
            : _MAX_SWAP_FEE_BIPS;

        // Initialize timestamp at which Swap Fee Module can be set
        swapFeeModuleUpdateTimestamp = block.timestamp;
    }

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/

    /**
        @notice Returns array of tokens available to be swapped against this Sovereign Pool (as tokenOut).
        @dev In case `sovereignVault == address(this)`, only token0 and token1 are available.
             Otherwise, the pool queries `sovereignVault` to retrieve them.
     */
    function getTokens() external view override returns (address[] memory tokens) {
        if (sovereignVault == address(this)) {
            // In this case only token0 and token1 can be swapped
            tokens = new address[](2);

            tokens[0] = address(_token0);
            tokens[1] = address(_token1);
        } else {
            // Data validation should be performed by either caller or `sovereignVault`
            tokens = ISovereignVaultMinimal(sovereignVault).getTokensForPool(address(this));
        }
    }

    /**
        @notice Returns `token0` and `token1` reserves, respectively.
        @dev Reserves are measured differently in case of rebase tokens.
             WARNING: With rebase tokens, balances (hence reserves) can be easily manipulated.
             External contracts MUST be aware and take the right precautions.
        @dev In case `sovereignVault` is not the pool, reserves are queried from `sovereignVault`.
        @dev This function only queries reserves for `token0` and `token1`.
             In case `sovereignVault` supports other tokens, reserves should be queried from it directly.
        @dev This is exposed for convenience. The pool makes no assumptions regarding the way an
             external `sovereignVault` updates reserves internally.
     */
    function getReserves() public view override returns (uint256, uint256) {
        if (sovereignVault == address(this)) {
            return (_getReservesForToken(true), _getReservesForToken(false));
        } else {
            address[] memory tokens = new address[](2);
            tokens[0] = address(_token0);
            tokens[1] = address(_token1);

            uint256[] memory reserves = ISovereignVaultMinimal(sovereignVault).getReservesForPool(
                address(this),
                tokens
            );

            // Only token0 and token1 reserves should be returned
            if (reserves.length != 2) {
                revert SovereignPool__getReserves_invalidReservesLength();
            }

            return (reserves[0], reserves[1]);
        }
    }

    /**
        @notice Returns pool manager fee in amount of token0 and token1.
     */
    function getPoolManagerFees() public view override returns (uint256, uint256) {
        return (feePoolManager0, feePoolManager1);
    }

    /**
        @notice Returns True if this pool contains at least one rebase token. 
     */
    function isRebaseTokenPool() external view override returns (bool) {
        return isToken0Rebase || isToken1Rebase;
    }

    /**
        @notice Returns the address of token0.
     */
    function token0() external view override returns (address) {
        return address(_token0);
    }

    /**
        @notice Returns the address of token1.
     */
    function token1() external view override returns (address) {
        return address(_token1);
    }

    /**
        @notice Returns address of Oracle module in this pool. 
     */
    function sovereignOracleModule() external view override returns (address) {
        return address(_sovereignOracleModule);
    }

    /**
        @notice Returns the address of the swapFeeModule in this pool.
     */
    function swapFeeModule() external view override returns (address) {
        return address(_swapFeeModule);
    }

    /**
        @notice Returns the address of the verifier module in this pool.
     */
    function verifierModule() external view override returns (address) {
        return address(_verifierModule);
    }

    /**
        @notice Exposes the status of reentrancy lock.
        @dev ALMs and other external smart contracts can use it for reentrancy protection. 
             Mainly useful for read-only reentrancy protection.
     */
    function isLocked() external view override returns (bool) {
        return _status == _ENTERED;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Sets address of `poolManager`.
        @dev Settable by `poolManager`.
        @param _manager Address of new pool manager. 
     */
    function setPoolManager(address _manager) external override onlyPoolManager nonReentrant {
        poolManager = _manager;

        if (_manager == address(0)) {
            poolManagerFeeBips = 0;
            // It will be assumed pool is not going to contribute anything to protocol fees.
            _claimPoolManagerFees(0, 0, msg.sender);
            emit PoolManagerFeeSet(0);
        }

        emit PoolManagerSet(_manager);
    }

    /**
        @notice Set fee in BIPS for `poolManager`.
        @dev Must not be greater than MAX_POOL_MANAGER_FEE_BIPS.
        @dev Settable by `poolManager`.
        @param _poolManagerFeeBips fee to set in BIPS.
     */
    function setPoolManagerFeeBips(uint256 _poolManagerFeeBips) external override onlyPoolManager nonReentrant {
        if (_poolManagerFeeBips > _MAX_POOL_MANAGER_FEE_BIPS) {
            revert SovereignPool__setPoolManagerFeeBips_excessivePoolManagerFee();
        }

        poolManagerFeeBips = _poolManagerFeeBips;

        emit PoolManagerFeeSet(_poolManagerFeeBips);
    }

    /**
        @notice Set Sovereign Oracle Module in this pool.
        @dev Can only be set once by `poolManager`.
        @param sovereignOracle Address of Sovereign Oracle Module instance. 
     */
    function setSovereignOracle(address sovereignOracle) external override onlyPoolManager nonReentrant {
        if (sovereignOracle == address(0)) {
            revert SovereignPool__ZeroAddress();
        }

        if (address(_sovereignOracleModule) != address(0)) {
            revert SovereignPool__setSovereignOracle__sovereignOracleAlreadySet();
        }

        _sovereignOracleModule = ISovereignOracle(sovereignOracle);

        emit SovereignOracleSet(sovereignOracle);
    }

    /**
        @notice Set Gauge in this pool.
        @dev Can only be set once by `protocolFactory`. 
        @param _gauge Address of Gauge instance.
     */
    function setGauge(address _gauge) external override onlyProtocolFactory nonReentrant {
        if (gauge != address(0)) {
            revert SovereignPool__setGauge_gaugeAlreadySet();
        }

        gauge = _gauge;

        emit GaugeSet(_gauge);
    }

    /**
        @notice Set Swap Fee Module for this pool.
        @dev Only callable by `poolManager`.
        @dev If set as address(0), a constant default swap fee will be applied.
        @dev It contains a 3 days timelock, to prevent `poolManager` from front-running
             swaps by rapidly increasing swap fees too frequently.
        @param swapFeeModule_ Address of Swap Fee Module to whitelist.
     */
    function setSwapFeeModule(address swapFeeModule_) external override onlyPoolManager nonReentrant {
        // Swap Fee Module cannot be updated too frequently (at most once every 3 days)
        if (block.timestamp < swapFeeModuleUpdateTimestamp) {
            revert SovereignPool__setSwapFeeModule_timelock();
        }

        _swapFeeModule = ISwapFeeModule(swapFeeModule_);
        // Update timestamp at which the next Swap Fee Module update can occur
        swapFeeModuleUpdateTimestamp = block.timestamp + 3 days;

        emit SwapFeeModuleSet(swapFeeModule_);
    }

    /**
        @notice Set ALM for this pool.
        @dev Only callable by `poolManager`.
        @dev Can only be called once.
        @param _alm Address of ALM to whitelist. 
     */
    function setALM(address _alm) external override onlyPoolManager nonReentrant {
        if (_alm == address(0)) {
            revert SovereignPool__ZeroAddress();
        }

        if (alm != address(0)) {
            revert SovereignPool__ALMAlreadySet();
        }

        alm = _alm;

        emit ALMSet(_alm);
    }

    function flashLoan(
        bool _isTokenZero,
        IFlashBorrower _receiver,
        uint256 _amount,
        bytes calldata _data
    ) external nonReentrant {
        // We disable flash-loans,
        // since reserves are not meant to be stored in the pool
        if (sovereignVault != address(this)) revert ValantisPool__flashLoan_flashLoanDisabled();

        IERC20 flashToken = _isTokenZero ? _token0 : _token1;
        bool isRebaseFlashToken = _isTokenZero ? isToken0Rebase : isToken1Rebase;

        // Flash-loans for rebase tokens are disabled.
        // Easy to manipulate token reserves would significantly
        // increase the attack surface for contracts that rely on this pool
        if (isRebaseFlashToken) {
            revert ValantisPool__flashLoan_rebaseTokenNotAllowed();
        }

        uint256 poolPreBalance = flashToken.balanceOf(address(this));

        flashToken.safeTransfer(address(_receiver), _amount);
        if (_receiver.onFlashLoan(msg.sender, address(flashToken), _amount, _data) != _CALLBACK_SUCCESS) {
            revert ValantisPool__flashloan_callbackFailed();
        }
        flashToken.safeTransferFrom(address(_receiver), address(this), _amount);

        if (flashToken.balanceOf(address(this)) != poolPreBalance) {
            revert ValantisPool__flashLoan_flashLoanNotRepaid();
        }

        emit Flashloan(msg.sender, address(_receiver), _amount, address(flashToken));
    }

    /**
        @notice Claim share of fees accrued by this pool
                And optionally share some with the protocol.
        @dev Only callable by `poolManager`.
        @param _feeProtocol0Bips Amount of `token0` fees to be shared with protocol.
        @param _feeProtocol1Bips Amount of `token1` fees to be shared with protocol.
     */
    function claimPoolManagerFees(
        uint256 _feeProtocol0Bips,
        uint256 _feeProtocol1Bips
    )
        external
        override
        nonReentrant
        onlyPoolManager
        returns (uint256 feePoolManager0Received, uint256 feePoolManager1Received)
    {
        (feePoolManager0Received, feePoolManager1Received) = _claimPoolManagerFees(
            _feeProtocol0Bips,
            _feeProtocol1Bips,
            msg.sender
        );
    }

    /**
        @notice Claim accrued protocol fees, if any.
        @dev Only callable by `gauge`. 
     */
    function claimProtocolFees() external override nonReentrant onlyGauge returns (uint256, uint256) {
        uint256 feeProtocol0Cache = feeProtocol0;
        uint256 feeProtocol1Cache = feeProtocol1;

        if (feeProtocol0Cache > 0) {
            feeProtocol0 = 0;
            _token0.safeTransfer(msg.sender, feeProtocol0Cache);
        }

        if (feeProtocol1Cache > 0) {
            feeProtocol1 = 0;
            _token1.safeTransfer(msg.sender, feeProtocol1Cache);
        }

        return (feeProtocol0Cache, feeProtocol1Cache);
    }

    /**
        @notice Swap against the ALM Position in this pool.
        @param _swapParams Struct containing all params.
               * isSwapCallback If this swap should claim funds using a callback.
               * isZeroToOne Direction of the swap.
               * amountIn Input amount to swap.
               * amountOutMin Minimum output token amount required.
               * deadline Block timestamp after which the swap is no longer valid.
               * recipient Recipient address for output token.
               * swapTokenOut Address of output token.
                 If `sovereignVault != address(this)` it can be other tokens apart from token0 or token1.
               * swapContext Struct containing ALM's external, Verifier's and Swap Callback's context data.
        @return amountInUsed Amount of input token filled by this swap.
        @return amountOut Amount of output token provided by this swap.
     */
    function swap(
        SovereignPoolSwapParams calldata _swapParams
    ) external override nonReentrant returns (uint256 amountInUsed, uint256 amountOut) {
        if (block.timestamp > _swapParams.deadline) {
            revert SovereignPool__swap_expired();
        }

        // Cannot swap zero input token amount
        if (_swapParams.amountIn == 0) {
            revert SovereignPool__swap_insufficientAmountIn();
        }

        if (_swapParams.recipient == address(0)) {
            revert SovereignPool__swap_invalidRecipient();
        }

        SwapCache memory swapCache = SwapCache({
            swapFeeModule: _swapFeeModule,
            tokenInPool: _swapParams.isZeroToOne ? _token0 : _token1,
            tokenOutPool: _swapParams.isZeroToOne ? _token1 : _token0,
            amountInWithoutFee: 0
        });

        if (_swapParams.swapTokenOut == address(0) || _swapParams.swapTokenOut == address(swapCache.tokenInPool)) {
            revert SovereignPool__swap_invalidSwapTokenOut();
        }

        // If reserves are kept in the pool, only token0 <-> token1 swaps are allowed
        if (sovereignVault == address(this) && _swapParams.swapTokenOut != address(swapCache.tokenOutPool)) {
            revert SovereignPool__swap_invalidPoolTokenOut();
        }

        bytes memory verifierData;
        if (address(_verifierModule) != address(0)) {
            // Query Verifier Module to authenticate the swap
            verifierData = _verifyPermission(
                msg.sender,
                _swapParams.swapContext.verifierContext,
                uint8(AccessType.SWAP)
            );
        }

        // Calculate swap fee in bips

        SwapFeeModuleData memory swapFeeModuleData;

        if (address(swapCache.swapFeeModule) != address(0)) {
            swapFeeModuleData = swapCache.swapFeeModule.getSwapFeeInBips(
                _swapParams.isZeroToOne,
                _swapParams.amountIn,
                msg.sender,
                _swapParams.swapContext.swapFeeModuleContext
            );
            if (swapFeeModuleData.feeInBips > _MAX_SWAP_FEE_BIPS) {
                revert SovereignPool__swap_excessiveSwapFee();
            }
        } else {
            swapFeeModuleData = SwapFeeModuleData({ feeInBips: defaultSwapFeeBips, internalContext: new bytes(0) });
        }

        // Since we do not yet know how much of `amountIn` will be filled,
        // this quantity is calculated in such a way that `msg.sender`
        // will be charged `feeInBips` of whatever the amount of tokenIn filled
        // ends up being (see docs for more details)
        swapCache.amountInWithoutFee = Math.mulDiv(
            _swapParams.amountIn,
            _MAX_SWAP_FEE_BIPS,
            _MAX_SWAP_FEE_BIPS + swapFeeModuleData.feeInBips
        );

        ALMLiquidityQuote memory liquidityQuote = ISovereignALM(alm).getLiquidityQuote(
            ALMLiquidityQuoteInput({
                isZeroToOne: _swapParams.isZeroToOne,
                amountInMinusFee: swapCache.amountInWithoutFee,
                feeInBips: swapFeeModuleData.feeInBips,
                sender: msg.sender,
                recipient: _swapParams.recipient,
                tokenOutSwap: _swapParams.swapTokenOut
            }),
            _swapParams.swapContext.externalContext,
            verifierData
        );

        amountOut = liquidityQuote.amountOut;

        if (
            !_checkLiquidityQuote(
                _swapParams.isZeroToOne,
                swapCache.amountInWithoutFee,
                liquidityQuote.amountInFilled,
                amountOut,
                _swapParams.amountOutMin
            )
        ) {
            revert SovereignPool__swap_invalidLiquidityQuote();
        }

        // If amountOut is 0, we do not transfer any input token
        if (amountOut == 0) {
            revert SovereignPool__swap_zeroAmountOut();
        }

        // Calculate the actual swap fee to be charged in input token (`effectiveFee`),
        // now that we know the tokenIn amount filled
        uint256 effectiveFee;
        if (liquidityQuote.amountInFilled != swapCache.amountInWithoutFee) {
            effectiveFee = Math.mulDiv(
                liquidityQuote.amountInFilled,
                swapFeeModuleData.feeInBips,
                _MAX_SWAP_FEE_BIPS,
                Math.Rounding.Up
            );
            amountInUsed = liquidityQuote.amountInFilled + effectiveFee;
        } else {
            // Using above formula in case amountInWithoutFee == amountInFilled introduces rounding errors
            effectiveFee = _swapParams.amountIn - swapCache.amountInWithoutFee;
            amountInUsed = _swapParams.amountIn;
        }

        _handleTokenInTransfersOnSwap(
            _swapParams.isZeroToOne,
            _swapParams.isSwapCallback,
            swapCache.tokenInPool,
            amountInUsed,
            effectiveFee,
            _swapParams.swapContext.swapCallbackContext
        );

        // Update internal state and oracle module.
        // In case of rebase tokens, `amountInUsed` and `amountOut` might not match
        // the exact balance deltas due to rounding errors.
        _updatePoolStateOnSwap(_swapParams.isZeroToOne, amountInUsed, amountOut, effectiveFee);

        if (
            address(_sovereignOracleModule) != address(0) &&
            _swapParams.swapTokenOut == address(swapCache.tokenOutPool) &&
            amountInUsed > 0
        ) {
            _sovereignOracleModule.writeOracleUpdate(_swapParams.isZeroToOne, amountInUsed, effectiveFee, amountOut);
        }

        // Transfer `amountOut to recipient
        _handleTokenOutTransferOnSwap(IERC20(_swapParams.swapTokenOut), _swapParams.recipient, amountOut);

        // Update state for Swap fee module,
        // only performed if internalContext is non-empty
        if (
            address(swapCache.swapFeeModule) != address(0) &&
            keccak256(swapFeeModuleData.internalContext) != keccak256(new bytes(0))
        ) {
            swapCache.swapFeeModule.callbackOnSwapEnd(effectiveFee, amountInUsed, amountOut, swapFeeModuleData);
        }

        // Perform post-swap callback to liquidity module if necessary
        if (liquidityQuote.isCallbackOnSwap) {
            ISovereignALM(alm).onSwapCallback(_swapParams.isZeroToOne, amountInUsed, amountOut);
        }

        emit Swap(msg.sender, _swapParams.isZeroToOne, amountInUsed, effectiveFee, amountOut);
    }

    /**
        @notice Deposit liquidity into an ALM Position.
        @dev Only callable by its respective active ALM Position.
        @param _amount0 Amount of token0 to deposit.
        @param _amount1 Amount of token1 to deposit. 
        @param _verificationContext Bytes containing verification data required in case of permissioned pool.
        @param _depositData Bytes encoded data for deposit callback.
        @return amount0Deposited Amount of token0 deposited.
        @return amount1Deposited Amount of token1 deposited.
     */
    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _sender,
        bytes calldata _verificationContext,
        bytes calldata _depositData
    ) external override onlyALM nonReentrant returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        // We disable deposits,
        // since reserves are not meant to be stored in the pool
        if (sovereignVault != address(this)) revert SovereignPool__depositLiquidity_depositDisabled();

        // At least one token amount must be positive
        if (_amount0 | _amount1 == 0) {
            revert SovereignPool__depositLiquidity_zeroTotalDepositAmount();
        }

        if (address(_verifierModule) != address(0)) {
            _verifyPermission(_sender, _verificationContext, uint8(AccessType.DEPOSIT));
        }

        uint256 token0PreBalance = _token0.balanceOf(address(this));
        uint256 token1PreBalance = _token1.balanceOf(address(this));

        ISovereignALM(msg.sender).onDepositLiquidityCallback(_amount0, _amount1, _depositData);

        amount0Deposited = _token0.balanceOf(address(this)) - token0PreBalance;
        amount1Deposited = _token1.balanceOf(address(this)) - token1PreBalance;

        // Post-deposit checks for token0
        // _amount0 == 0 is interpreted as not depositing token0
        if (_amount0 != 0) {
            if (isToken0Rebase) {
                uint256 amount0AbsDiff = amount0Deposited < _amount0
                    ? _amount0 - amount0Deposited
                    : amount0Deposited - _amount0;

                if (amount0AbsDiff > token0AbsErrorTolerance) {
                    revert SovereignPool__depositLiquidity_excessiveToken0ErrorOnTransfer();
                }
            } else {
                if (amount0Deposited != _amount0) revert SovereignPool__depositLiquidity_insufficientToken0Amount();

                _reserve0 += amount0Deposited;
            }
        } else if (amount0Deposited > 0) {
            revert SovereignPool__depositLiquidity_incorrectTokenAmount();
        }

        // Post-deposit checks for token1
        // _amount1 == 0 is interpreted as not depositing token1
        if (_amount1 != 0) {
            if (isToken1Rebase) {
                uint256 amount1AbsDiff = amount1Deposited < _amount1
                    ? _amount1 - amount1Deposited
                    : amount1Deposited - _amount1;

                if (amount1AbsDiff > token1AbsErrorTolerance) {
                    revert SovereignPool__depositLiquidity_excessiveToken1ErrorOnTransfer();
                }
            } else {
                if (amount1Deposited != _amount1) revert SovereignPool__depositLiquidity_insufficientToken1Amount();

                _reserve1 += amount1Deposited;
            }
        } else if (amount1Deposited > 0) {
            revert SovereignPool__depositLiquidity_incorrectTokenAmount();
        }

        emit DepositLiquidity(amount0Deposited, amount1Deposited);
    }

    /**
        @notice Withdraw liquidity from this pool to an ALM Position.
        @dev Only callable by ALM Position.
        @param _amount0 Amount of token0 reserves to withdraw.
        @param _amount1 Amount of token1 reserves to withdraw.
        @param _recipient Address of recipient.
        @param _verificationContext Bytes containing verfication data required in case of permissioned pool.
     */
    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _sender,
        address _recipient,
        bytes calldata _verificationContext
    ) external override nonReentrant onlyALM {
        if (_recipient == address(0)) {
            revert SovereignPool__withdrawLiquidity_invalidRecipient();
        }

        if (address(_verifierModule) != address(0)) {
            _verifyPermission(_sender, _verificationContext, uint8(AccessType.WITHDRAW));
        }

        if (_amount0 > _getReservesForToken(true)) {
            revert SovereignPool__withdrawLiquidity_insufficientReserve0();
        }

        if (_amount1 > _getReservesForToken(false)) {
            revert SovereignPool__withdrawLiquidity_insufficientReserve1();
        }

        // Already checked above
        unchecked {
            if (!isToken0Rebase) _reserve0 -= _amount0;

            if (!isToken1Rebase) _reserve1 -= _amount1;
        }

        if (_amount0 > 0) {
            _token0.safeTransfer(_recipient, _amount0);
        }

        if (_amount1 > 0) {
            _token1.safeTransfer(_recipient, _amount1);
        }

        emit WithdrawLiquidity(_recipient, _amount0, _amount1);
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    function _claimPoolManagerFees(
        uint256 _feeProtocol0Bips,
        uint256 _feeProtocol1Bips,
        address _recipient
    ) private returns (uint256 feePoolManager0Received, uint256 feePoolManager1Received) {
        if (_feeProtocol0Bips > _MAX_SWAP_FEE_BIPS || _feeProtocol1Bips > _MAX_SWAP_FEE_BIPS) {
            revert SovereignPool___claimPoolManagerFees_invalidProtocolFee();
        }

        (feePoolManager0Received, feePoolManager1Received) = getPoolManagerFees();

        // Attempt to claim pool manager fees from `sovereignVault`
        // This is necessary since in this case reserves are not kept in this pool
        if (sovereignVault != address(this)) {
            uint256 token0PreBalance = _token0.balanceOf(address(this));
            uint256 token1PreBalance = _token1.balanceOf(address(this));

            ISovereignVaultMinimal(sovereignVault).claimPoolManagerFees(
                feePoolManager0Received,
                feePoolManager1Received
            );

            uint256 fee0ReceivedCache = _token0.balanceOf(address(this)) - token0PreBalance;
            uint256 fee1ReceivedCache = _token1.balanceOf(address(this)) - token1PreBalance;

            // Cannot transfer in excess, otherwise it would be possible to manipulate this pool's
            // fair share of earned swap fees
            if (fee0ReceivedCache > feePoolManager0Received || fee1ReceivedCache > feePoolManager1Received) {
                revert SovereignPool___claimPoolManagerFees_invalidFeeReceived();
            }

            feePoolManager0Received = fee0ReceivedCache;
            feePoolManager1Received = fee1ReceivedCache;
        }

        uint256 protocolFee0 = Math.mulDiv(_feeProtocol0Bips, feePoolManager0Received, _MAX_SWAP_FEE_BIPS);
        uint256 protocolFee1 = Math.mulDiv(_feeProtocol1Bips, feePoolManager1Received, _MAX_SWAP_FEE_BIPS);

        feeProtocol0 += protocolFee0;
        feeProtocol1 += protocolFee1;

        feePoolManager0 = 0;
        feePoolManager1 = 0;

        feePoolManager0Received -= protocolFee0;
        feePoolManager1Received -= protocolFee1;

        if (feePoolManager0Received > 0) {
            _token0.safeTransfer(_recipient, feePoolManager0Received);
        }

        if (feePoolManager1Received > 0) {
            _token1.safeTransfer(_recipient, feePoolManager1Received);
        }

        emit PoolManagerFeesClaimed(feePoolManager0Received, feePoolManager1Received);
    }

    function _verifyPermission(
        address sender,
        bytes calldata verificationContext,
        uint8 accessType
    ) private returns (bytes memory verifierData) {
        bool success;

        (success, verifierData) = _verifierModule.verify(sender, verificationContext, accessType);

        if (!success) {
            revert SovereignPool___verifyPermission_onlyPermissionedAccess(sender, accessType);
        }
    }

    function _handleTokenInTransfersOnSwap(
        bool isZeroToOne,
        bool isSwapCallback,
        IERC20 token,
        uint256 amountInUsed,
        uint256 effectiveFee,
        bytes calldata _swapCallbackContext
    ) private {
        uint256 preBalance = token.balanceOf(sovereignVault);

        if (isSwapCallback) {
            ISovereignPoolSwapCallback(msg.sender).sovereignPoolSwapCallback(
                address(token),
                amountInUsed,
                _swapCallbackContext
            );
        } else {
            token.safeTransferFrom(msg.sender, sovereignVault, amountInUsed);
        }

        uint256 amountInReceived = token.balanceOf(sovereignVault) - preBalance;

        bool isTokenInRebase = isZeroToOne ? isToken0Rebase : isToken1Rebase;

        if (isTokenInRebase) {
            uint256 tokenInAbsDiff = amountInUsed > amountInReceived
                ? amountInUsed - amountInReceived
                : amountInReceived - amountInUsed;

            uint256 tokenInAbsErrorTolerance = isZeroToOne ? token0AbsErrorTolerance : token1AbsErrorTolerance;
            if (tokenInAbsDiff > tokenInAbsErrorTolerance)
                revert SovereignPool___handleTokenInOnSwap_excessiveTokenInErrorOnTransfer();
        } else {
            if (amountInReceived != amountInUsed) revert SovereignPool___handleTokenInOnSwap_invalidTokenInAmount();
        }

        if (isTokenInRebase && sovereignVault == address(this) && poolManager != address(0)) {
            // We transfer manager fee to `poolManager`
            uint256 poolManagerFee = Math.mulDiv(effectiveFee, poolManagerFeeBips, _MAX_SWAP_FEE_BIPS);
            if (poolManagerFee > 0) {
                token.safeTransfer(poolManager, poolManagerFee);
            }
        }
    }

    function _handleTokenOutTransferOnSwap(IERC20 swapTokenOut, address recipient, uint256 amountOut) private {
        if (sovereignVault == address(this)) {
            // In this case, tokenOut should be transferred from this pool to `recipient`
            swapTokenOut.safeTransfer(recipient, amountOut);
        } else {
            // If `sovereignVault` is not this pool,
            // ALM must have already approved this pool to send `amountOut` to `recipient`
            swapTokenOut.safeTransferFrom(sovereignVault, recipient, amountOut);
        }
    }

    function _updatePoolStateOnSwap(
        bool isZeroToOne,
        uint256 amountInUsed,
        uint256 amountOut,
        uint256 effectiveFee
    ) private {
        if (isZeroToOne) {
            if (!isToken0Rebase) {
                uint256 poolManagerFee = Math.mulDiv(effectiveFee, poolManagerFeeBips, _MAX_SWAP_FEE_BIPS);

                if (sovereignVault == address(this)) _reserve0 += (amountInUsed - poolManagerFee);
                if (poolManagerFee > 0) feePoolManager0 += poolManagerFee;
            }

            if (sovereignVault == address(this) && !isToken1Rebase) {
                _reserve1 -= amountOut;
            }
        } else {
            if (sovereignVault == address(this) && !isToken0Rebase) {
                _reserve0 -= amountOut;
            }

            if (!isToken1Rebase) {
                uint256 poolManagerFee = Math.mulDiv(effectiveFee, poolManagerFeeBips, _MAX_SWAP_FEE_BIPS);

                if (sovereignVault == address(this)) _reserve1 += (amountInUsed - poolManagerFee);
                if (poolManagerFee > 0) feePoolManager1 += poolManagerFee;
            }
        }
    }

    function _onlyALM() private view {
        if (msg.sender != alm) {
            revert SovereignPool__onlyALM();
        }
    }

    function _onlyProtocolFactory() private view {
        if (msg.sender != protocolFactory) {
            revert SovereignPool__onlyProtocolFactory();
        }
    }

    function _onlyPoolManager() private view {
        if (msg.sender != poolManager) {
            revert SovereignPool__onlyPoolManager();
        }
    }

    function _onlyGauge() private view {
        if (msg.sender != gauge) {
            revert SovereignPool__onlyGauge();
        }
    }

    function _getReservesForToken(bool isToken0) private view returns (uint256 reserve) {
        if (isToken0) {
            if (isToken0Rebase) {
                reserve = _token0.balanceOf(address(this));
            } else {
                reserve = _reserve0;
            }
        } else {
            if (isToken1Rebase) {
                reserve = _token1.balanceOf(address(this));
            } else {
                reserve = _reserve1;
            }
        }
    }

    function _checkLiquidityQuote(
        bool isZeroToOne,
        uint256 amountInWithoutFee,
        uint256 amountInFilled,
        uint256 amountOut,
        uint256 amountOutMin
    ) private view returns (bool) {
        // We only compare against pool reserves if they are meant to be stored in it
        if (sovereignVault == address(this)) {
            if (amountOut > _getReservesForToken(!isZeroToOne)) {
                return false;
            }
        }

        if (amountOut < amountOutMin) {
            return false;
        }

        if (amountInFilled > amountInWithoutFee) {
            return false;
        }

        return true;
    }
}
