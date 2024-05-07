// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { ISwapFeeModule, SwapFeeModuleData } from '../swap-fee-modules/interfaces/ISwapFeeModule.sol';

contract MockSwapFeeModule is ISwapFeeModule {
    /************************************************
     *  EVENTS
     ***********************************************/

    event LogSwapFeeCallback();

    /************************************************
     *  STORAGE
     ***********************************************/

    uint256 public swapFeeBips;
    bytes public internalContext;

    constructor(uint256 _swapFeeBips) {
        swapFeeBips = _swapFeeBips;
    }

    function setSwapFeeParams(uint256 _swapFeeBips, bytes memory _internalContext) external {
        swapFeeBips = _swapFeeBips;
        internalContext = _internalContext;
    }

    function getSwapFeeInBips(
        address,
        address,
        uint256,
        address,
        bytes memory
    ) external view override returns (SwapFeeModuleData memory swapFeeModuleData) {
        swapFeeModuleData.feeInBips = swapFeeBips;
        swapFeeModuleData.internalContext = internalContext;
    }

    function callbackOnSwapEnd(uint256, int24, uint256, uint256, SwapFeeModuleData memory) external override {
        emit LogSwapFeeCallback();
        internalContext = new bytes(0);
    }

    function callbackOnSwapEnd(uint256, uint256, uint256, SwapFeeModuleData memory) external override {
        emit LogSwapFeeCallback();
        internalContext = new bytes(0);
    }
}
