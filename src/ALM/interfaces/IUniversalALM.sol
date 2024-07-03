// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {
    ALMLiquidityQuotePoolInputs,
    ALMCachedLiquidityQuote,
    ALMLiquidityQuote,
    ALMReserves
} from '../structs/UniversalALMStructs.sol';

/**
    @notice Universal ALM Interface.
    @notice All ALMs bound to a Universal Pool must implement it.
 */
interface IUniversalALM {
    /**
        @notice Called at the beginning of the swap to setup communication between pool and ALM.
                Can also send `liquidityQuote` at `spotPriceTick` if needed.
        @param _almLiquidityQuotePoolInputs Contains fundamental data about the swap.
        @param _user Address of the account initiating the swap.
        @param _feeInBips Fee being charged by the pool for this swap ( in BIPS ).
        @param _almReserves Reserves of the ALM.
        @param _externalContext Complete externalContext received, this is sent only once to all ALMs
                after which external context is destroyed. ALMs that wish to retain this data, can do 
                so via `internalContext`.
        @return isParticipatingInSwap True if the ALM plans to provide any quotes for this swap.
        @return refreshReserves The ALMs that wish to provide JIT liquidity during setupSwap period,
                can set this value to `True`.
        @return setupQuote Liquidity quote to the swap at the starting price tick.
    */
    function setupSwap(
        ALMLiquidityQuotePoolInputs memory _almLiquidityQuotePoolInputs,
        address _user,
        uint256 _feeInBips,
        ALMReserves memory _almReserves,
        bytes calldata _externalContext
    ) external returns (bool isParticipatingInSwap, bool refreshReserves, ALMLiquidityQuote memory setupQuote);

    /** 
        @notice Called after `setupSwap` to (optionally) provide a quote.
        @dev Internal Context can be used to maintain state between price ticks, without querying storage
        @param _almLiquidityQuotePoolInputs Contains fundamental data about the swap.
        @param _internalContext Can optionally be passed from `setupSwap` return data,
               or previous calls to this function.
        @param _almReserves Reserves of the ALM.
        @return almLiquidityQuote Liquidity quote to the swap at the current price tick.

    */
    function getLiquidityQuote(
        ALMLiquidityQuotePoolInputs memory _almLiquidityQuotePoolInputs,
        ALMReserves memory _almReserves,
        bytes calldata _internalContext
    ) external returns (ALMLiquidityQuote memory almLiquidityQuote);

    /**
        @notice Called at the end of the swap to inform the ALM about any state updates.
        @param _isZeroToOne Direction of the swap.
        @param _amountInFilled Total amount which the swap caller has provided to the pool.
        @param _amountOutProvided Total amount which this ALM position has provided to swap caller.
        @param _almFeeEarned Amount of fees earned by the ALM post swap ( in tokenIn ).
        @param _almReserves Final reserves of the ALM post swap.
        @param _spotPriceTickPreSwap Spot price tick before the swap has started.
        @param _spotPriceTickPostSwap Spot price tick after the swap has been completed.
        @param _lastLiquidQuote Necessary to inform the ALM about the last price tick at
               which it provided non-zero liquidity. It can be different from `spotPriceTick`.
     */
    function callbackOnSwapEnd(
        bool _isZeroToOne,
        uint256 _amountInFilled,
        uint256 _amountOutProvided,
        uint256 _almFeeEarned,
        ALMReserves memory _almReserves,
        int24 _spotPriceTickPreSwap,
        int24 _spotPriceTickPostSwap,
        ALMCachedLiquidityQuote calldata _lastLiquidQuote
    ) external;

    /**
        @notice Callback function for `depositLiquidity` .
        @param _amount0 Amount of token0 being deposited.
        @param _amount1 Amount of token1 being deposited.
        @param _data Context data passed by the ALM, while calling `depositLiquidity`.
    */
    function onDepositLiquidityCallback(uint256 _amount0, uint256 _amount1, bytes memory _data) external;
}
