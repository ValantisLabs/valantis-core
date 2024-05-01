// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SwapFeeModuleData, ISwapFeeModuleMinimal } from 'src/swap-fee-modules/interfaces/ISwapFeeModuleMinimal.sol';

interface ISwapFeeModule is ISwapFeeModuleMinimal {
    /**
        @notice Callback function called by the pool after the swap has finished. ( Universal Pools )
        @param _effectiveFee The effective fee charged for the swap.
        @param _spotPriceTick The spot price tick after the swap.
        @param _amountInUsed The amount of tokenIn used for the swap.
        @param _amountOut The amount of the tokenOut transferred to the user.
        @param _swapFeeModuleData The context data returned by getSwapFeeInBips.
     */
    function callbackOnSwapEnd(
        uint256 _effectiveFee,
        int24 _spotPriceTick,
        uint256 _amountInUsed,
        uint256 _amountOut,
        SwapFeeModuleData memory _swapFeeModuleData
    ) external;

    /**
        @notice Callback function called by the pool after the swap has finished. ( Sovereign Pools )
        @param _effectiveFee The effective fee charged for the swap.
        @param _amountInUsed The amount of tokenIn used for the swap.
        @param _amountOut The amount of the tokenOut transferred to the user.
        @param _swapFeeModuleData The context data returned by getSwapFeeInBips.
     */
    function callbackOnSwapEnd(
        uint256 _effectiveFee,
        uint256 _amountInUsed,
        uint256 _amountOut,
        SwapFeeModuleData memory _swapFeeModuleData
    ) external;
}
