// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ISwapFeeModule } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

interface IConstantSwapFeeModule is ISwapFeeModule {
    function MAX_SWAP_FEE_BIPS() external view returns (uint256);

    function pool() external view returns (address);

    function feeModuleManager() external view returns (address);

    function swapFeeBips() external view returns (uint256);

    function setFeeModuleManager(address _feeModuleManager) external;

    function setSwapFeeBips(uint256 _swapFeeBips) external;
}
