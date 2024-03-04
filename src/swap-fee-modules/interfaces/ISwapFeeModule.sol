// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct SwapFeeModuleData {
    uint256 feeInBips;
    bytes internalContext;
}

interface ISwapFeeModule {
    // For Sovereign Pool
    function getSwapFeeInBips(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _user,
        bytes memory _swapFeeModuleContext
    ) external returns (SwapFeeModuleData memory swapFeeModuleData);

    function getSwapFeeInBips(
        bool _isZeroToOne,
        uint256 _amountIn,
        address _user,
        bytes memory _swapFeeModuleContext
    ) external returns (SwapFeeModuleData memory swapFeeModuleData);

    function callbackOnSwapEnd(
        uint256 _effectiveFee,
        int24 _spotPriceTick,
        uint256 _amountInUsed,
        uint256 _amountOut,
        SwapFeeModuleData memory _swapFeeModuleData
    ) external;

    function callbackOnSwapEnd(
        uint256 _effectiveFee,
        uint256 _amountInUsed,
        uint256 _amountOut,
        SwapFeeModuleData memory _swapFeeModuleData
    ) external;
}

interface ISovereignSwapFeeModule {
    function callbackOnSwapEnd(
        uint256 _effectiveFee,
        uint256 _amountInUsed,
        uint256 _amountOut,
        SwapFeeModuleData memory _swapFeeModuleData
    ) external;
}
