// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { UniversalPoolReentrancyGuard } from '../utils/UniversalPoolReentrancyGuard.sol';
import { PoolLocks, Lock } from './structs/ReentrancyGuardStructs.sol';
import { IUniversalPool } from './interfaces/IUniversalPool.sol';
import { IUniversalPoolSwapCallback } from './interfaces/IUniversalPoolSwapCallback.sol';
import { ISwapFeeModule, SwapFeeModuleData } from '../swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { IUniversalOracle } from '../oracles/interfaces/IUniversalOracle.sol';
import { IFlashBorrower } from '../pools/interfaces/IFlashBorrower.sol';

import {
    Slot0,
    ALMPosition,
    ALMStatus,
    UnderlyingALMQuote,
    SwapCache,
    InternalSwapALMState,
    PoolState,
    SwapParams
} from './structs/UniversalPoolStructs.sol';
import { ALMReserves } from '../ALM/structs/UniversalALMStructs.sol';
import { EnumerableALMMap } from '../libraries/EnumerableALMMap.sol';
import { StateLib } from './libraries/StateLib.sol';
import { GM } from './libraries/GM.sol';
import { ALMLib } from './libraries/ALMLib.sol';
import { PriceTickMath } from '../libraries/PriceTickMath.sol';

/**
  @title Valantis Universal Pool
  @notice A Universal Pool contains the following modular components:
          - Algorithmic Liquidity Module (ALM) positions.
            ALM positions can be replaced by `poolManager`.
          - Swap Fee Module instance. (Optional).
            If not provided, this pool will use a constant swap fee.
            `poolManager` can add and replace it.
          - Universal Oracle instance. (Optional).
            If provided, pool will call this external smart contract, which is able to checkpoint
            information at the end of each swap.
 
       Each ALM can be thought as a self-contained DEX design which complies with an interface
       and holds its token reserves and fees in the pool by default (unless it withdraws).
 
       Universal Pools are able to source and aggregate liquidity from multiple ALMs at swap time,
       subject to the condition that said ALMs provide their quote amounts with a discrete price.
 
       Calculating swap fees, deciding on liquidity distribution across price ranges
       and pricing tokenOut in terms of tokenIn, are done by Swap Fee Module, ALMs and Universal Pool, respectively.
       In this way, one can safely make changes in one aspect of the pool without altering the others.
 */
contract UniversalPool is IUniversalPool, UniversalPoolReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableALMMap for EnumerableALMMap.ALMSet;
    using ALMLib for EnumerableALMMap.ALMSet;
    using StateLib for PoolState;
    using GM for SwapCache;
    using GM for SwapParams;
    using GM for InternalSwapALMState[];

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error UniversalPool__onlyPoolManager();
    error UniversalPool__onlyActiveALM();
    error UniversalPool__onlyGauge();
    error UniversalPool__onlyProtocolFactory();
    error UniversalPool__invalidTokenAddresses();
    error UniversalPool__initializeTick();
    error UniversalPool__spotPriceTick_spotPriceTickLocked();
    error UniversalPool__swap_excessiveSwapFee();
    error UniversalPool__swap_expired();
    error UniversalPool__swap_insufficientAmountIn();
    error UniversalPool__swap_amountInCannotBeZero();
    error UniversalPool__swap_minAmountOutNotFilled();
    error UniversalPool__swap_invalidALMOrderingData();
    error UniversalPool__swap_invalidExternalContextArrayLength();
    error UniversalPool__swap_invalidLimitPriceTick();
    error UniversalPool__swap_noActiveALMPositions();
    error UniversalPool__swap_zeroAddressRecipient();
    error UniversalPool__swap_zeroAmountOut();
    error UniversalPool__setGauge_gaugeAlreadySet();
    error UniversalPool__setGauge_invalidAddress();

    /************************************************
     *  CONSTANTS
     ***********************************************/

    /**
        @notice Maximum swap fee is 50% of input amount. 
     */
    uint256 private constant MAX_SWAP_FEE_BIPS = 1e4;

    /**
        @notice Indicates success of flash loan callback according to ERC3156.
     */
    bytes32 private constant CALLBACK_SUCCESS = keccak256('ERC3156FlashBorrower.onFlashLoan');

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    /**
        @notice Address of the protocol factory contract.
     */
    address public immutable protocolFactory;

    /**
        @notice Default pool swap fee in bips.
     */
    uint256 public immutable defaultSwapFeeBips;

    /**
        @notice Address of ERC20 token0 of the pool.
     */
    IERC20 private immutable _token0;

    /**
        @notice Address of ERC20 token1 of the pool.
     */
    IERC20 private immutable _token1;

    /************************************************
     *  STORAGE
     ***********************************************/

    /**
        @notice Current spotPriceTick of the pool (denotes the price of token0 in terms of token1).
     */
    int24 private _spotPriceTick;

    /**
        @notice All pool specific state variables.
            * poolManagerFeeBips
            * feeProtocol0
            * feeProtocol1
            * feePoolManager0
            * feePoolManager1
            * swapFeeModule
            * poolManager
            * universalOracle
            * gauge
     */
    PoolState private _state;

    /**
        @notice Enumerable Map of all ALMPositions in the pool.
     */
    EnumerableALMMap.ALMSet private _ALMPositions;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier onlyPoolManager() {
        _onlyPoolManager();
        _;
    }

    modifier onlyActiveALM() {
        _onlyActiveALM();
        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        address _token0Address,
        address _token1Address,
        address _protocolFactory,
        address _poolManager,
        uint256 _defaultSwapFeeBips
    ) {
        if (_token0Address == _token1Address || _token0Address == address(0) || _token1Address == address(0)) {
            revert UniversalPool__invalidTokenAddresses();
        }

        _token0 = IERC20(_token0Address);
        _token1 = IERC20(_token1Address);

        protocolFactory = _protocolFactory;

        _state.poolManager = _poolManager;
        _state.swapFeeModuleUpdateTimestamp = block.timestamp;

        // Default swap fees cannot be set greater than 10_000 bips
        defaultSwapFeeBips = _defaultSwapFeeBips <= MAX_SWAP_FEE_BIPS ? _defaultSwapFeeBips : MAX_SWAP_FEE_BIPS;
    }

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/

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
        @notice Returns the struct containing the state of the pool.
     */
    function state() external view override returns (PoolState memory) {
        return _state;
    }

    /**
        @notice Returns the current spotPriceTick of the pool.
        @dev The spotPriceTick view function is locked during a swap to prevent read-only reentrancy.
     */
    function spotPriceTick() external view override returns (int24) {
        if (_poolLocks.swap != _NOT_ENTERED) {
            revert UniversalPool__spotPriceTick_spotPriceTickLocked();
        }

        return _spotPriceTick;
    }

    /**
        @notice Exposes the status of all the reentrancy locks in the pool.
        @dev ALMs and other external smart contracts can use pool locks for reentrancy protection. 
             Mainly useful for view-only reentrancy attack vectors on spotPrice, getALMPositions, etc.
     */
    function getPoolLockStatus() external view override returns (PoolLocks memory) {
        return _poolLocks;
    }

    /**
        @notice Returns Slot0 array of ALM positions in the pool. 
        @return Array of all ALMPositions in the pool.
     */
    function getALMPositionsList() external view override returns (ALMPosition[] memory) {
        return _ALMPositions.values();
    }

    /**
        @notice Returns ALM position struct from `_almPositionAddress`.
        @param _almPositionAddress address of ALM position to query. 
     */
    function getALMPositionAtAddress(
        address _almPositionAddress
    ) external view override returns (ALMStatus status, ALMPosition memory) {
        return _ALMPositions.getALM(_almPositionAddress);
    }

    /** 
        @notice Returns reserves of the ALM at `_almPositionAddress`.
        @param _almPositionAddress address of ALM position to query. 
        @param _isZeroToOne direction of the swap.
        @dev Function always returns reserves in the form (tokenInReserves, tokenOutReserves),
             depending on the direction of the swap.
     */
    function getALMReserves(
        address _almPositionAddress,
        bool _isZeroToOne
    ) external view override returns (ALMReserves memory) {
        return _ALMPositions.getALMReserves(_isZeroToOne, _almPositionAddress);
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Initializes the spot price tick of the pool, and unlocks all reentrancy locks.
        @dev Can only be set once by `poolManager`.
        @param _tick initial spot price tick.
     */
    function initializeTick(int24 _tick) external override onlyPoolManager {
        // All locks are initially set to 0
        // @audit initializeTick should only be allowed once
        if (
            _poolLocks.withdrawals != 0 || _tick < PriceTickMath.MIN_PRICE_TICK || _tick > PriceTickMath.MAX_PRICE_TICK
        ) {
            revert UniversalPool__initializeTick();
        }

        _spotPriceTick = _tick;

        _unlock(Lock.WITHDRAWAL);
        _unlock(Lock.DEPOSIT);
        _unlock(Lock.SWAP);

        emit InitializeTick(_tick);
    }

    /**
        @notice Allows anyone to flash loan any amount of tokens from the pool.
        @param _isTokenZero True if token0 is being flash loaned, False otherwise.
        @param _receiver Address of the flash loan receiver.
        @param _amount Amount of tokens to be flash loaned.
        @param _data Bytes encoded data for flash loan callback.
     */
    function flashLoan(
        bool _isTokenZero,
        IFlashBorrower _receiver,
        uint256 _amount,
        bytes calldata _data
    ) external nonReentrantGlobal {
        IERC20 flashToken = _isTokenZero ? _token0 : _token1;
        uint256 poolPreBalance = flashToken.balanceOf(address(this));

        flashToken.safeTransfer(address(_receiver), _amount);
        if (_receiver.onFlashLoan(msg.sender, address(flashToken), _amount, _data) != CALLBACK_SUCCESS) {
            revert ValantisPool__flashloan_callbackFailed();
        }
        flashToken.safeTransferFrom(address(_receiver), address(this), _amount);

        if (flashToken.balanceOf(address(this)) < poolPreBalance) {
            revert ValantisPool__flashLoan_flashLoanNotRepaid();
        }

        emit Flashloan(msg.sender, address(_receiver), _amount, address(flashToken));
    }

    /**
        @notice Sets the gauge contract address for the pool.
        @dev Only callable by `protocolFactory`.
        @dev Once a gauge is set it cannot be changed again.
        @param _gauge address of the gauge.
     */
    function setGauge(address _gauge) external override nonReentrantGlobal {
        if (msg.sender != protocolFactory) {
            revert UniversalPool__onlyProtocolFactory();
        }

        if (_gauge == address(0)) {
            revert UniversalPool__setGauge_invalidAddress();
        }

        if (_state.gauge != address(0)) {
            revert UniversalPool__setGauge_gaugeAlreadySet();
        }

        _state.gauge = _gauge;

        emit GaugeSet(_gauge);
    }

    /**
        @notice Claim share of protocol fees accrued by this pool.
        @dev Can only be claimed by `gauge` of the pool. 
     */
    function claimProtocolFees() external override nonReentrantGlobal returns (uint256, uint256) {
        if (msg.sender != _state.gauge) {
            revert UniversalPool__onlyGauge();
        }

        (uint256 feeProtocol0Claimed, uint256 feeProtocol1Claimed) = _state.claimProtocolFees(_token0, _token1);

        return (feeProtocol0Claimed, feeProtocol1Claimed);
    }

    /**
        @notice Sets the state struct of the pool.
        @dev Can only be set by `poolManager`. Checks are inside the StateLib.
     */
    function setPoolState(PoolState memory _newState) external override nonReentrantGlobal onlyPoolManager {
        if (_newState.poolManager == address(0)) {
            _state.claimPoolManagerFees(_token0, _token1, 0, 0);
            _newState.poolManagerFeeBips = 0;
        }
        _state.setPoolState(_newState);
    }

    /**
        @notice Sets the feeShare in BIPS for a Meta ALM.
        @dev Can only be set by `poolManager`.
        @param _almAddress address of the ALM.
        @param _feeShare in BIPS.
     */
    function setMetaALMFeeShare(
        address _almAddress,
        uint64 _feeShare
    ) external override nonReentrantGlobal onlyPoolManager {
        _ALMPositions.setMetaALMFeeShare(_almAddress, _feeShare);
    }

    /**
        @notice Claim share of fees accrued by this pool
                And optionally share some with the protocol.
        @dev Only callable by `poolManager`.
        @param _feeProtocol0Bips Percent of `token0` fees to be shared with protocol.
        @param _feeProtocol1Bips Percent of `token1` fees to be shared with protocol.
     */
    function claimPoolManagerFees(
        uint256 _feeProtocol0Bips,
        uint256 _feeProtocol1Bips
    )
        external
        override
        nonReentrantGlobal
        onlyPoolManager
        returns (uint256 feePoolManager0Received, uint256 feePoolManager1Received)
    {
        (feePoolManager0Received, feePoolManager1Received) = _state.claimPoolManagerFees(
            _token0,
            _token1,
            _feeProtocol0Bips,
            _feeProtocol1Bips
        );
    }

    /**
        @notice Activate an ALM Position in this pool.
        @dev Can only be called by `poolManager`.
        @param _isMetaALM True if the ALM is of type Meta ALM, False otherwise.
        @param _isCallbackOnSwapEndRequired True if callback is required at the end of each swap, False otherwise.
        @param _shareQuotes (Only relevant for Base ALMs) True if Base ALM wants to share real time quote information
            with Meta ALMs, in return for a share of the fees, False otherwise.
        @param _metaALMFeeShare (Only relevant for Meta ALMs) Percentage of fees to be shared with Base ALMs (in BIPS).
        @param _almAddress Address of the ALM Position to whitelist.
            address should be deployed and registered in Protocol Factory.
     */
    function addALMPosition(
        bool _isMetaALM,
        bool _isCallbackOnSwapEndRequired,
        bool _shareQuotes,
        uint64 _metaALMFeeShare,
        address _almAddress
    ) external override nonReentrantGlobal onlyPoolManager {
        _ALMPositions.add(
            ALMPosition(
                Slot0(_isMetaALM, _isCallbackOnSwapEndRequired, _shareQuotes, _metaALMFeeShare, _almAddress),
                0,
                0,
                0,
                0
            )
        );
    }

    /**
        @notice Remove an ALM Position from this pool.
        @dev Can only be called by `poolManager`.
        @param _almAddress address of the ALM to be removed.
     */
    function removeALMPosition(address _almAddress) external override nonReentrantGlobal onlyPoolManager {
        _ALMPositions.remove(_almAddress);
    }

    /**
        @notice Deposit liquidity into an ALM Position.
        @dev Only callable by its respective active ALM Position.
        @param _amount0 Amount of token0 to deposit.
        @param _amount1 Amount of token1 to deposit. 
        @param _depositData Bytes encoded data for ALM deposit callback.
     */
    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _depositData
    ) external override nonReentrant(Lock.DEPOSIT) onlyActiveALM {
        _ALMPositions.depositLiquidity(_token0, _token1, _amount0, _amount1, _depositData);
    }

    /**
        @notice Withdraw liquidity from this pool to `recipient`.
        @dev Only callable by its respective ALM Position (either active or removed).
        @param _amount0 Amount of `token0` reserves to withdraw (excluding accrued fees).
        @param _amount1 Amount of `token1` reserves to withdraw (excluding accrued fees).
        @param _recipient Withdrawal recipient.
     */
    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _recipient
    ) external override nonReentrant(Lock.WITHDRAWAL) {
        _ALMPositions.withdrawLiquidity(_token0, _token1, _amount0, _amount1, _recipient);
    }

    /**
        @notice Swap against ALM Positions in this pool.
        @param _swapParams Struct containing all swap parameters.
            * isZeroToOne Direction of the swap.
            * isSwapCallback If this swap should claim funds using a callback.
            * limitPriceTick Tick corresponding to limit price chosen by the user.
            * recipient Address of output token recipient.
            * amountIn Input amount to swap.
            * amountOut Min Minimum amount of tokenOut user is willing to receive for amountIn.
            * deadline Block timestamp after which the swap is no longer valid.
            * swapCallbackContext Context for swap callback.
            * swapFeeModuleContext Context for swap fee module.
            * almOrdering Ordering of ALMs during setupSwap.
            * externalContext Array of external contexts for ALMs.
        @return amountInUsed Amount of tokenIn consumed during the swap
        @return amountOut Amount of tokenOut user will receive.
     */
    function swap(SwapParams calldata _swapParams) external override returns (uint256 amountInUsed, uint256 amountOut) {
        if (block.timestamp > _swapParams.deadline) {
            revert UniversalPool__swap_expired();
        }

        // @audit : Check for multi function reentrancy in swap function

        // All withdrawals are paused as soon as swap function starts
        // Deposits are allowed for JIT liquidity
        _lock(Lock.SWAP);
        _lock(Lock.WITHDRAWAL);

        (
            SwapCache memory swapCache,
            InternalSwapALMState[] memory almStates,
            UnderlyingALMQuote[] memory baseALMQuotes
        ) = _processSwapParams(_swapParams);

        SwapFeeModuleData memory swapFeeModuleData = swapCache.swapFeeModule != address(0)
            ? ISwapFeeModule(swapCache.swapFeeModule).getSwapFeeInBips(
                _swapParams.isZeroToOne,
                _swapParams.amountIn,
                msg.sender,
                _swapParams.swapFeeModuleContext
            )
            : SwapFeeModuleData(defaultSwapFeeBips, new bytes(0));

        if (swapFeeModuleData.feeInBips > MAX_SWAP_FEE_BIPS) {
            revert UniversalPool__swap_excessiveSwapFee();
        }

        // Get initial swap amounts
        swapCache.amountInMinusFee = Math.mulDiv(
            _swapParams.amountIn,
            MAX_SWAP_FEE_BIPS,
            MAX_SWAP_FEE_BIPS + swapFeeModuleData.feeInBips
        );
        swapCache.amountInRemaining = swapCache.amountInMinusFee;
        swapCache.feeInBips = swapFeeModuleData.feeInBips;

        // Make initial communication calls to the ALM
        swapCache.spotPriceTick = almStates.setupSwaps(baseALMQuotes, _ALMPositions, _swapParams, swapCache);

        _lock(Lock.DEPOSIT);

        if (swapCache.amountInRemaining != 0 && swapCache.spotPriceTick != swapCache.spotPriceTickStart) {
            // Request for quotes
            swapCache.spotPriceTick = almStates.requestForQuotes(baseALMQuotes, _swapParams, swapCache);
        }

        if (swapCache.amountOutFilled < _swapParams.amountOutMin) {
            revert UniversalPool__swap_minAmountOutNotFilled();
        }

        // Update Spot Price Tick
        // TODO: Check if it costs the same gas without the if statement.
        if (swapCache.spotPriceTick != swapCache.spotPriceTickStart) {
            _spotPriceTick = swapCache.spotPriceTick;
        }

        // Update state for pool
        // We do so before updating ALMs and Swap Fee Module
        // so they can access the ground truth updated state in this pool.

        // Calculate effectiveFee using the fraction of tokenIn that got filled
        swapCache.effectiveFee = Math.mulDiv(
            (swapCache.amountInMinusFee - swapCache.amountInRemaining),
            swapFeeModuleData.feeInBips,
            MAX_SWAP_FEE_BIPS
        );

        almStates.updatePoolState(_ALMPositions, _state, _swapParams, swapCache);

        amountInUsed = (swapCache.amountInMinusFee - swapCache.amountInRemaining) + swapCache.effectiveFee;
        amountOut = swapCache.amountOutFilled;

        if (amountInUsed > 0 && amountOut == 0) {
            revert UniversalPool__swap_zeroAmountOut();
        }

        // Claim amountInFilled + effectiveFee from sender
        if (amountInUsed > 0) {
            IERC20 tokenInInterface = _swapParams.isZeroToOne ? _token0 : _token1;
            uint256 tokenInPreBalance = tokenInInterface.balanceOf(address(this));

            if (_swapParams.isSwapCallback) {
                IUniversalPoolSwapCallback(msg.sender).universalPoolSwapCallback(
                    address(tokenInInterface),
                    amountInUsed,
                    _swapParams.swapCallbackContext
                );
            } else {
                tokenInInterface.safeTransferFrom(msg.sender, address(this), amountInUsed);
            }

            if (tokenInInterface.balanceOf(address(this)) - tokenInPreBalance < amountInUsed) {
                revert UniversalPool__swap_insufficientAmountIn();
            }
        }

        if (amountOut > 0) {
            (_swapParams.isZeroToOne ? _token1 : _token0).safeTransfer(_swapParams.recipient, amountOut);
        }

        // Update state for Swap fee module
        if (swapFeeModuleData.internalContext.length != 0) {
            ISwapFeeModule(swapCache.swapFeeModule).callbackOnSwapEnd(
                swapCache.effectiveFee,
                swapCache.spotPriceTick,
                amountInUsed,
                amountOut,
                swapFeeModuleData
            );
        }

        // Update Oracle Data
        if (amountInUsed > 0 && _state.universalOracle != address(0)) {
            IUniversalOracle(_state.universalOracle).writeOracleUpdate(
                _swapParams.isZeroToOne,
                amountInUsed,
                swapCache.effectiveFee,
                amountOut,
                swapCache.spotPriceTick,
                _swapParams.limitPriceTick
            );
        }

        // After ALM state has been updated, and amounts have been transfered, pool is unlocked
        // ALMs can now withdraw
        _unlock(Lock.WITHDRAWAL);
        _unlock(Lock.DEPOSIT);

        // Update ALM positions internal state
        almStates.updateALMPositionsOnSwapEnd(_swapParams, swapCache);

        emit Swap(msg.sender, amountInUsed, amountOut, _swapParams.isZeroToOne);

        _unlock(Lock.SWAP);
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    /**
        @notice Validates all swap input parameters and creates the SwapCache, almStates and baseALMQuotes arrays.
     */
    function _processSwapParams(
        SwapParams calldata swapParams
    )
        private
        view
        returns (
            SwapCache memory swapCache,
            InternalSwapALMState[] memory almStates,
            UnderlyingALMQuote[] memory baseALMQuotes
        )
    {
        uint256 almPositionsLength = _ALMPositions.length();

        swapCache = SwapCache({
            isMetaALMPool: false,
            spotPriceTick: _spotPriceTick,
            spotPriceTickStart: 0,
            swapFeeModule: _state.swapFeeModule,
            amountInMinusFee: 0,
            amountInRemaining: 0,
            amountOutFilled: 0,
            effectiveFee: 0,
            numBaseALMs: _ALMPositions.getNumBaseALMs(),
            baseShareQuoteLiquidity: 0,
            feeInBips: 0
        });

        // Initialize remaining swap cache variables
        swapCache.spotPriceTickStart = swapCache.spotPriceTick;
        swapCache.isMetaALMPool = (swapCache.numBaseALMs != almPositionsLength);

        // Check amountIn validity
        if (swapParams.amountIn == 0) {
            revert UniversalPool__swap_amountInCannotBeZero();
        }

        if (swapParams.recipient == address(0)) {
            revert UniversalPool__swap_zeroAddressRecipient();
        }

        // Check limit price tick validity
        if (
            swapParams.limitPriceTick < PriceTickMath.MIN_PRICE_TICK ||
            swapParams.limitPriceTick > PriceTickMath.MAX_PRICE_TICK ||
            (swapParams.isZeroToOne && swapParams.limitPriceTick > swapCache.spotPriceTick) ||
            (!swapParams.isZeroToOne && swapParams.limitPriceTick < swapCache.spotPriceTick)
        ) {
            revert UniversalPool__swap_invalidLimitPriceTick();
        }

        // Check validity of external context
        if (almPositionsLength == 0) {
            revert UniversalPool__swap_noActiveALMPositions();
        }
        if (almPositionsLength != swapParams.externalContext.length) {
            revert UniversalPool__swap_invalidExternalContextArrayLength();
        }
        if (swapCache.numBaseALMs != swapParams.almOrdering.length) {
            revert UniversalPool__swap_invalidALMOrderingData();
        }
        // Initiate all ALM related arrays
        almStates = new InternalSwapALMState[](almPositionsLength);

        // If isMetaALMPool is false, then baseALMQuotes array operations are not done
        if (swapCache.isMetaALMPool) {
            baseALMQuotes = new UnderlyingALMQuote[](swapCache.numBaseALMs);
        }
        bool[] memory indexFlags = new bool[](almPositionsLength);

        // Check validity of ALM ordering
        for (uint256 i; i < almPositionsLength; ) {
            if (i < swapCache.numBaseALMs) {
                uint256 almIndex = swapParams.almOrdering[i];
                // Caching base ALMs
                if (almIndex >= swapCache.numBaseALMs || indexFlags[almIndex]) {
                    revert UniversalPool__swap_invalidALMOrderingData();
                }

                almStates[i].almSlot0 = _ALMPositions.getSlot0(almIndex);
                if (swapCache.isMetaALMPool) {
                    baseALMQuotes[i].almAddress = almStates[i].almSlot0.almAddress;
                }

                // Set all new indices to true
                indexFlags[almIndex] = true;
            } else {
                // Caching Meta ALMs
                almStates[i].almSlot0 = _ALMPositions.getSlot0(i);
            }

            almStates[i].almReserves = _ALMPositions.getALMReserves(
                swapParams.isZeroToOne,
                almStates[i].almSlot0.almAddress
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
        @notice Helper function for the onlyPoolManager modifier, to reduce bytecode size.
     */
    function _onlyPoolManager() private view {
        if (msg.sender != _state.poolManager) {
            revert UniversalPool__onlyPoolManager();
        }
    }

    /**
        @notice Helper function for the onlyActiveALM modifier, to reduce bytecode size.
     */
    function _onlyActiveALM() private view {
        if (!_ALMPositions.isALMActive(msg.sender)) {
            revert UniversalPool__onlyActiveALM();
        }
    }
}
