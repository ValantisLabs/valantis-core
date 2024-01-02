// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct ALMLiquidityQuotePoolInputs {
    bool isZeroToOne;
    int24 limitPriceTick;
    int24 currentSpotPriceTick;
    uint256 amountInRemaining;
    uint256 amountOutExpected;
}

struct ALMLiquidityQuote {
    uint256 tokenOutAmount;
    int24 nextLiquidPriceTick;
    bytes internalContext;
}

struct ALMCachedLiquidityQuote {
    uint256 tokenOutAmount;
    int24 priceTick;
    int24 nextLiquidPriceTick;
    bytes internalContext;
}

struct ALMReserves {
    uint256 tokenInReserves;
    uint256 tokenOutReserves;
}
