// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { PriceTickMath } from 'src/libraries/PriceTickMath.sol';

import {
    ALMLiquidityQuotePoolInputs,
    ALMLiquidityQuote,
    ALMCachedLiquidityQuote,
    IUniversalALM,
    ALMReserves
} from '../ALM/interfaces/IUniversalALM.sol';
import { IUniversalPool } from '../pools/interfaces/IUniversalPool.sol';
import { ALMPosition, SwapParams, MetaALMData } from '../pools/structs/UniversalPoolStructs.sol';
import { UniversalPool } from '../pools/UniversalPool.sol';
import { PoolLocks } from '../pools/structs/ReentrancyGuardStructs.sol';
import { UniversalPoolReentrancyGuard } from '../utils/UniversalPoolReentrancyGuard.sol';
import { IFlashBorrower } from '../pools/interfaces/IFlashBorrower.sol';

interface IRefreshReserve {
    function refreshReserves(uint256 amount0, uint256 amount1) external;
}

contract MockUniversalALM is IUniversalALM {
    using SafeERC20 for IERC20;

    address pool;
    bool metaALM;

    constructor(address _pool, bool _metaALM) {
        pool = _pool;
        metaALM = _metaALM;
    }

    function setupSwap(
        ALMLiquidityQuotePoolInputs memory,
        address,
        uint256,
        ALMReserves memory,
        bytes calldata externalContext
    )
        external
        override
        returns (bool isParticipatingInSwap, bool refreshReserves, ALMLiquidityQuote memory swapSetupQuote)
    {
        if (metaALM) {
            MetaALMData memory metaALMData = abi.decode(externalContext, (MetaALMData));

            uint256 amount0;
            uint256 amount1;
            (isParticipatingInSwap, refreshReserves, amount0, amount1, swapSetupQuote) = abi.decode(
                metaALMData.almContext,
                (bool, bool, uint256, uint256, ALMLiquidityQuote)
            );

            if (refreshReserves) {
                IRefreshReserve(msg.sender).refreshReserves(amount0, amount1);
            }
        } else {
            uint256 amount0;
            uint256 amount1;
            (isParticipatingInSwap, refreshReserves, amount0, amount1, swapSetupQuote) = abi.decode(
                externalContext,
                (bool, bool, uint256, uint256, ALMLiquidityQuote)
            );

            if (refreshReserves) {
                IRefreshReserve(msg.sender).refreshReserves(amount0, amount1);
            }
        }
    }

    function getLiquidityQuote(
        ALMLiquidityQuotePoolInputs memory,
        ALMReserves memory,
        bytes calldata internalContext
    ) external view override returns (ALMLiquidityQuote memory almLiquidityQuote) {
        if (metaALM) {
            MetaALMData memory metaALMData = abi.decode(internalContext, (MetaALMData));

            (almLiquidityQuote) = abi.decode(metaALMData.almContext, (ALMLiquidityQuote));
        } else {
            (almLiquidityQuote) = abi.decode(internalContext, (ALMLiquidityQuote));
        }
    }

    function callbackOnSwapEnd(
        bool _isZeroToOne,
        uint256 _amountInFilled,
        uint256 _amountOutProvided,
        uint256 _feeEarned,
        ALMReserves memory _almReserves,
        int24 _spotPriceTickPreSwap,
        int24 _spotPriceTickPostSwap,
        // necessary to inform ALM about the last price tick it provided liquidity at
        // this price tick can be different from spotPriceTick post swap
        ALMCachedLiquidityQuote calldata latestQuote
    ) external {}

    function depositLiquidity(uint256 amount0, uint256 amount1) external {
        IUniversalPool(pool).depositLiquidity(amount0, amount1, abi.encode(msg.sender));
    }

    function onDepositLiquidityCallback(uint256 _amount0, uint256 _amount1, bytes memory _data) external override {
        IUniversalPool universalPool = IUniversalPool(pool);

        address user = abi.decode(_data, (address));

        IERC20(universalPool.token0()).safeTransferFrom(user, msg.sender, _amount0);
        IERC20(universalPool.token1()).safeTransferFrom(user, msg.sender, _amount1);
    }

    function withdrawLiquidity(uint256 amount0, uint256 amount1, address recepient) external {
        IUniversalPool(pool).withdrawLiquidity(amount0, amount1, recepient);
    }
}
