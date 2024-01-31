// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ALMCachedLiquidityQuote, ALMReserves } from '../../ALM/structs/UniversalALMStructs.sol';
import { IUniversalOracle } from '../../oracles/interfaces/IUniversalOracle.sol';
import { SwapFeeModuleData } from '../../swap-fee-modules/interfaces/ISwapFeeModule.sol';

struct Slot0 {
    bool isMetaALM;
    bool isCallbackOnSwapEndRequired;
    bool shareQuotes;
    uint64 metaALMFeeShare;
    address almAddress;
}

struct ALMPosition {
    Slot0 slot0;
    uint256 reserve0;
    uint256 reserve1;
    uint256 feeCumulative0;
    uint256 feeCumulative1;
}

struct UnderlyingALMQuote {
    bool isValidQuote;
    address almAddress;
    uint256 tokenOutAmount;
}

struct MetaALMData {
    UnderlyingALMQuote[] almQuotes;
    bytes almContext;
}

struct SwapParams {
    bool isZeroToOne;
    bool isSwapCallback;
    int24 limitPriceTick;
    address recipient;
    uint256 amountIn;
    uint256 amountOutMin;
    uint256 deadline;
    bytes swapCallbackContext;
    bytes swapFeeModuleContext;
    uint8[] almOrdering;
    bytes[] externalContext;
}

/************************************************
 *  CACHE STRUCTS
 ***********************************************/

struct SwapCache {
    bool isMetaALMPool;
    int24 spotPriceTick;
    int24 spotPriceTickStart;
    address swapFeeModule;
    uint256 amountInMinusFee;
    uint256 amountInRemaining;
    uint256 amountOutFilled;
    uint256 effectiveFee;
    uint256 numBaseALMs;
    uint256 baseShareQuoteLiquidity;
    uint256 feeInBips;
}

struct InternalSwapALMState {
    bool isParticipatingInSwap;
    bool refreshReserves;
    Slot0 almSlot0;
    uint256 totalLiquidityProvided;
    uint256 totalLiquidityReceived;
    ALMReserves almReserves;
    uint256 feeEarned;
    ALMCachedLiquidityQuote latestLiquidityQuote;
}

struct PoolState {
    uint256 poolManagerFeeBips;
    uint256 feeProtocol0;
    uint256 feeProtocol1;
    uint256 feePoolManager0;
    uint256 feePoolManager1;
    address swapFeeModule;
    address poolManager;
    address universalOracle;
    address gauge;
}

enum ALMStatus {
    NULL, // ALM was never added to the pool
    ACTIVE, // ALM was added to the pool, and is in operation
    REMOVED // ALM was added to the pool, and then removed, not in operation
}
