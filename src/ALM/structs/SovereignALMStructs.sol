// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

struct ALMLiquidityQuoteInput {
    bool isZeroToOne;
    uint256 amountInMinusFee;
    uint256 feeInBips;
    address sender;
    address recipient;
    address tokenOutSwap;
}

struct ALMLiquidityQuote {
    bool isCallbackOnSwap;
    uint256 amountOut;
    uint256 amountInFilled;
}
