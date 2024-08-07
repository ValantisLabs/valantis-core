// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IUniversalPoolSwapCallback {
    /**
        @notice Function called by Universal Pool during a swap, to transfer the funds.
        @dev This function is only called if isSwapCallback is set to true in swapParams.
        @param _tokenIn The address of the token that the user wants to swap.
        @param _amountInUsed The amount of the tokenIn used for the swap.
        @param _swapCallbackContext Arbitrary bytes data which can be sent to the swap callback.
     */
    function universalPoolSwapCallback(
        address _tokenIn,
        uint256 _amountInUsed,
        bytes calldata _swapCallbackContext
    ) external;
}
