// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { MockSwapFeeModule } from 'src/mocks/MockSwapFeeModule.sol';

library MockSwapFeeModuleHelper {
    function deployMockSwapFeeModule() internal returns (address swapFeeModule) {
        swapFeeModule = address(new MockSwapFeeModule(0));
    }

    function setSwapFeeBips(address swapFeeModule, uint256 swapFeeBips) internal {
        MockSwapFeeModule(swapFeeModule).setSwapFeeParams(swapFeeBips, new bytes(0));
    }
}
