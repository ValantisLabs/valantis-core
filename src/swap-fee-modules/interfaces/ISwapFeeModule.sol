// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @notice Struct returned by the swapFeeModule during the getSwapFeeInBips call.
    * feeInBips: The swap fee in bips.
    * internalContext: Arbitrary bytes context data.
 */
struct SwapFeeModuleData {
    uint256 feeInBips;
    bytes internalContext;
}

interface ISwapFeeModule {
    /**
        @notice Returns the swap fee in bips for both Universal & Sovereign Pools.
        @param _tokenIn The address of the token that the user wants to swap.
        @param _tokenOut The address of the token that the user wants to receive.
        @param _amountIn The amount of tokenIn being swapped.
        @param _user The address of the user.
        @param _swapFeeModuleContext Arbitrary bytes data which can be sent to the swap fee module.
        @return swapFeeModuleData A struct containing the swap fee in bips, and internal context data.
     */
    function getSwapFeeInBips(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _user,
        bytes memory _swapFeeModuleContext
    ) external returns (SwapFeeModuleData memory swapFeeModuleData);

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
