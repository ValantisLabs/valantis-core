// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ISovereignPoolSwapCallback {
    function sovereignPoolSwapCallback(
        address _tokenIn,
        uint256 _amountInUsed,
        bytes calldata _swapCallbackContext
    ) external;
}
