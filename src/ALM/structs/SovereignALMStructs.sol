// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct ALMLiquidityQuoteInput {
    bool isZeroToOne;
    uint256 amountInMinusFee;
    uint256 fee;
    uint256 feeInBips;
    address sender;
    address recipient;
    address tokenOutSwap;
}

struct ALMLiquidityQuote {
    bool quoteFromPoolReserves;
    bool isCallbackOnSwap;
    uint256 amountOut;
    uint256 amountInFilled;
}
