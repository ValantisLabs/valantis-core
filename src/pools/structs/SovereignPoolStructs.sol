// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { ISwapFeeModule } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

struct SovereignPoolConstructorArgs {
    address token0;
    address token1;
    address protocolFactory;
    address poolManager;
    address sovereignVault;
    address verifierModule;
    bool isToken0Rebase;
    bool isToken1Rebase;
    uint256 token0AbsErrorTolerance;
    uint256 token1AbsErrorTolerance;
    uint256 token0MinAmount;
    uint256 token1MinAmount;
    uint256 defaultSwapFeeBips;
}

struct SovereignPoolSwapContextData {
    bytes externalContext;
    bytes verifierContext;
    bytes swapCallbackContext;
    bytes swapFeeModuleContext;
}

struct SwapCache {
    ISwapFeeModule swapFeeModule;
    IERC20 tokenInPool;
    IERC20 tokenOutPool;
    uint256 amountInWithoutFee;
}

struct SovereignPoolSwapParams {
    bool isSwapCallback;
    bool isZeroToOne;
    uint256 amountIn;
    uint256 amountOutMin;
    address recipient;
    address swapTokenOut;
    SovereignPoolSwapContextData swapContext;
}
