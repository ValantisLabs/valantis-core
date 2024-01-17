// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { MockUniversalALM } from 'src/mocks/MockUniversalALM.sol';

enum MockALMStates {
    VALID, // For all valid tests
    TOKENOUT_RESERVES, // tokenOutAmount is greater than reserves
    TOKENOUT_POOL_INPUTS, // tokenOutAmount is greater than amoutnOutExpected
    NEXT_TICK_LT_SPOT_PRICE,
    NEXT_TICK_GT_LIMIT_PRICE,
    NEXT_TICK_EQ_SPOT_PRICE,
    JIT_LIQUIDITY
}

struct SwapOutput {
    uint256 amountInUsedWithFee;
    uint256 amountOutWithFee;
    uint256 amountInUsedWithoutFee;
    uint256 amountOutWithoutFee;
}

struct SwapBalances {
    uint256 poolBalanceToken0;
    uint256 poolBalanceToken1;
    uint256 userBalanceToken0;
    uint256 userBalanceToken1;
}

library MockUniversalALMHelper {
    function deployMockALM(address pool, bool isMetaALM) internal returns (address alm) {
        alm = address(new MockUniversalALM(pool, isMetaALM));
    }
}
