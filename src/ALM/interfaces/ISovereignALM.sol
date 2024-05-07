// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from '../structs/SovereignALMStructs.sol';

/**
    @title Sovereign ALM interface
    @notice All ALMs bound to a Sovereign Pool must implement it.
 */
interface ISovereignALM {
    /** 
        @notice Called by the Sovereign pool to request a liquidity quote from the ALM.
        @param _almLiquidityQuoteInput Contains fundamental data about the swap.
        @param _externalContext Data received by the pool from the user.
        @param _verifierData Verification data received by the pool from the verifier module
        @return almLiquidityQuote Liquidity quote containing tokenIn and tokenOut amounts filled.
    */
    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuoteInput,
        bytes calldata _externalContext,
        bytes calldata _verifierData
    ) external returns (ALMLiquidityQuote memory);

    /**
        @notice Callback function for `depositLiquidity` .
        @param _amount0 Amount of token0 being deposited.
        @param _amount1 Amount of token1 being deposited.
        @param _data Context data passed by the ALM, while calling `depositLiquidity`.
    */
    function onDepositLiquidityCallback(uint256 _amount0, uint256 _amount1, bytes memory _data) external;

    /**
        @notice Callback to ALM after swap into liquidity pool.
        @dev Only callable by pool.
        @param _isZeroToOne Direction of swap.
        @param _amountIn Amount of tokenIn in swap.
        @param _amountOut Amount of tokenOut in swap. 
     */
    function onSwapCallback(bool _isZeroToOne, uint256 _amountIn, uint256 _amountOut) external;
}
