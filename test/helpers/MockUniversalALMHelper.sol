// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { MockUniversalALM } from 'src/mocks/MockUniversalALM.sol';

library MockUniversalALMHelper {
    function deployMockALM(address pool, bool isMetaALM) internal returns (address alm) {
        alm = address(new MockUniversalALM(pool, isMetaALM));
    }

    function depositLiquidity(address alm, uint256 amount0, uint256 amoun1) internal {
        MockUniversalALM(alm).depositLiquidity(amount0, amoun1);
    }
}
