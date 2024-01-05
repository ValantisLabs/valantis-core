// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IUniversalPoolSwapCallback {
    function universalPoolSwapCallback(
        address _tokenIn,
        uint256 _amountInUsed,
        bytes calldata _swapCallbackContext
    ) external;
}
