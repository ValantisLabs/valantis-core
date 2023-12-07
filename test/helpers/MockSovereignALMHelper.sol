// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { MockSovereignALMFactory } from 'test/mocks/MockSovereignALMFactory.sol';
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

    function deploySovereignALMFactory(address protocolFactory) internal returns (address almFactory) {
        almFactory = address(new MockSovereignALMFactory(protocolFactory));
    }
}
