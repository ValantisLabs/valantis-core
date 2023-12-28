// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { MockSovereignALMFactory } from 'src/mocks/MockSovereignALMFactory.sol';
import { MockSovereignALM } from 'src/mocks/MockSovereignALM.sol';
import { ALMLiquidityQuote } from 'src/ALM/structs/SovereignALMStructs.sol';

library MockSovereignALMHelper {
    struct MockALMConfiguration {
        bool quoteExcessAmountIn;
        bool quoteExcessAmountOut;
        bool quoteFromPool;
        bool quotePartialFill;
        bool quoteToRecipientInExcess;
        bool swapCallback;
        address recipient;
        ALMLiquidityQuote liquidityQuote;
    }

    function deployAndSetSovereignALMFactory(address protocolFactory) internal returns (address almFactory) {
        almFactory = address(new MockSovereignALMFactory(protocolFactory));
    }

    function addLiquidity(address alm, uint256 amount0, uint256 amoun1) internal {
        MockSovereignALM(alm).depositLiquidity(amount0, amoun1, new bytes(0));
    }
}
