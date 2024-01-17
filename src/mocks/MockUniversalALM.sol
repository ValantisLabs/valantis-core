// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import '../../lib/forge-std/src/Test.sol';
import '../../lib/forge-std/src/console.sol';

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
import { MockALMStates } from '../../test/helpers/MockUniversalALMHelper.sol';
import { UniversalPoolReentrancyGuard } from '../utils/UniversalPoolReentrancyGuard.sol';
import { IFlashBorrower } from '../pools/interfaces/IFlashBorrower.sol';

// contract MockUniversalALM is IUniversalALM, Test {
//     using SafeERC20 for IERC20;

//     error MockUniversalALM__onlyPool();

//     event PoolInput(bool isZeroToOne, int24 currentSpotPriceTick, uint256 amountInRemaining, uint256 amountOutExpected);
//     event SwapCallback(
//         bool isZeroToOne,
//         uint256 amountInFilled,
//         uint256 amountOutProvided,
//         int24 spotPriceTickPreSwap,
//         int24 spotPriceTickPostSwap
//     );
//     event LiquidityQuote(int24 currentSpotPriceTick, uint256 tokenOutAmount, int24 nextLiquidPricetick);

//     address public immutable pool;

//     mapping(int24 => mapping(bool => ALMLiquidityQuote)) liquidityQuotes;
//     mapping(int24 => mapping(bool => ALMLiquidityQuote)) swapSetups;
//     mapping(int24 => mapping(bool => MockALMStates)) quoteTypes;

//     ALMCachedLiquidityQuote latestLiquidityQuoteCache;

//     int24 limitPriceTickForSwap;
//     uint256 feeInBipsForSwap;

//     uint256 preSwapTokenInReserves;
//     uint256 preSwapTokenOutReserves;

//     uint256 totalAmountOutProvided;
//     uint256 totalAmountInExpected;

//     bool swapEnded;
//     bool public shouldBeDeactivated;

//     bool participateInSwap = true;
//     bool isJITGlobal;
//     bool isReentrant;

//     constructor(address _pool) {
//         pool = _pool;
//     }

//     modifier onlyPool() {
//         if (msg.sender != pool) {
//             revert MockUniversalALM__onlyPool();
//         }
//         _;
//     }

//     function setParticipateInSwap(bool value) external {
//         participateInSwap = value;
//     }

//     function setJITGlobal(bool value) external {
//         isJITGlobal = value;
//     }

//     function setReentrant(bool value) external {
//         isReentrant = value;
//     }

//     function setShouldBeDeactivated(bool value) external {
//         shouldBeDeactivated = value;
//     }

//     function setQuoteType(
//         bool _isZeroToOne,
//         int24 _spotPriceTick,
//         MockALMStates _state
//     ) external {
//         quoteTypes[_spotPriceTick][_isZeroToOne] = _state;
//     }

//     function setLiquidityQuote(
//         bool _isZeroToOne,
//         int24 _spotPriceTick,
//         ALMLiquidityQuote memory _almLiquidityQuote
//     ) external {
//         liquidityQuotes[_spotPriceTick][_isZeroToOne] = _almLiquidityQuote;
//     }

//     function setSwapSetupQuote(
//         bool _isZeroToOne,
//         int24 _spotPriceTick,
//         ALMLiquidityQuote memory _almSwapSetupQuote
//     ) external {
//         swapSetups[_spotPriceTick][_isZeroToOne] = _almSwapSetupQuote;
//     }

//     function withdrawLiquidity(
//         uint256 _amount0,
//         uint256 _amount1,
//         address _recipient
//     ) external {
//         IUniversalPool(pool).withdrawLiquidity(_amount0, _amount1, _recipient);
//     }

//     function depositLiquidity(
//         bool isInsufficient,
//         uint256 _amount0,
//         uint256 _amount1
//     ) external {
//         IUniversalPool(pool).depositLiquidity(_amount0, _amount1, abi.encode(isInsufficient, false, msg.sender));
//     }

//     function onDepositLiquidityCallback(
//         uint256 _amount0,
//         uint256 _amount1,
//         bytes memory _data
//     ) external override onlyPool {
//         (bool isInsufficient, bool isJIT, address user) = abi.decode(_data, (bool, bool, address));

//         (address token0, address token1) = (IUniversalPool(pool).token0(), IUniversalPool(pool).token1());

//         uint256 deficitToken0;
//         uint256 deficitToken1;

//         if (isInsufficient) {
//             // Added for randomization of values
//             if (_amount0 % 3 == 0) {
//                 deficitToken1 = 1;
//             } else if (_amount0 % 3 == 1) {
//                 deficitToken0 = 1;
//             } else {
//                 deficitToken0 = 1;
//                 deficitToken1 = 1;
//             }
//         }

//         if (isJIT) {
//             if (_amount0 > 0) {
//                 IERC20(token0).safeTransfer(msg.sender, _amount0 - deficitToken0);
//             }

//             if (_amount1 > 0) {
//                 IERC20(token1).safeTransfer(msg.sender, _amount1 - deficitToken1);
//             }
//         } else {
//             if (_amount0 > 0) {
//                 IERC20(token0).safeTransferFrom(user, msg.sender, _amount0 - deficitToken0);
//             }

//             if (_amount1 > 0) {
//                 IERC20(token1).safeTransferFrom(user, msg.sender, _amount1 - deficitToken1);
//             }
//         }
//     }

//     function processOutgoingQuote(
//         bool isSetupQuote,
//         ALMLiquidityQuotePoolInputs memory poolInputs,
//         ALMLiquidityQuote memory quote,
//         MockALMStates quoteType,
//         uint256,
//         uint256 _almReservesTokenOut
//     ) internal returns (bool refreshReserves) {
//         // To prevent valid ALM calls from accidentally quoting over the limitPriceTick
//         if (
//             (poolInputs.isZeroToOne && quote.nextLiquidPriceTick < poolInputs.limitPriceTick) ||
//             (!poolInputs.isZeroToOne && quote.nextLiquidPriceTick > poolInputs.limitPriceTick)
//         ) {
//             quote.nextLiquidPriceTick = poolInputs.currentSpotPriceTick;
//         }

//         if (quote.nextLiquidPriceTick == poolInputs.currentSpotPriceTick) {
//             swapEnded = true;
//         }

//         // Setting Invariants
//         if (quoteType == MockALMStates.TOKENOUT_RESERVES) {
//             quote.tokenOutAmount = _almReservesTokenOut + 1;
//             shouldBeDeactivated = true;
//             swapEnded = true;
//         } else if (quoteType == MockALMStates.TOKENOUT_POOL_INPUTS) {
//             quote.tokenOutAmount = poolInputs.amountOutExpected + 1;
//             shouldBeDeactivated = true;
//             swapEnded = true;
//         } else if (quoteType == MockALMStates.NEXT_TICK_GT_LIMIT_PRICE) {
//             quote.nextLiquidPriceTick = limitPriceTickForSwap + int24(poolInputs.isZeroToOne ? -1 : int8(1));

//             if (!(isSetupQuote && quote.tokenOutAmount == 0)) {
//                 shouldBeDeactivated = true;
//                 swapEnded = true;
//             }
//         } else if (quoteType == MockALMStates.NEXT_TICK_LT_SPOT_PRICE) {
//             quote.nextLiquidPriceTick =
//                 poolInputs.currentSpotPriceTick +
//                 int24(poolInputs.isZeroToOne ? int8(1) : int8(-1));
//             if (!(isSetupQuote && quote.tokenOutAmount == 0)) {
//                 shouldBeDeactivated = true;
//                 swapEnded = true;
//             }
//         } else if (quoteType == MockALMStates.NEXT_TICK_EQ_SPOT_PRICE) {
//             quote.nextLiquidPriceTick = poolInputs.currentSpotPriceTick;
//             swapEnded = true;
//         } else if (quoteType == MockALMStates.JIT_LIQUIDITY) {
//             preSwapTokenOutReserves += quote.tokenOutAmount;
//             IUniversalPool(pool).depositLiquidity(
//                 poolInputs.isZeroToOne ? 0 : quote.tokenOutAmount,
//                 poolInputs.isZeroToOne ? quote.tokenOutAmount : 0,
//                 abi.encode(false, true, address(this))
//             );
//             refreshReserves = true;
//         }

//         latestLiquidityQuoteCache = ALMCachedLiquidityQuote(
//             quote.tokenOutAmount,
//             poolInputs.currentSpotPriceTick,
//             quote.nextLiquidPriceTick,
//             quote.internalContext
//         );

//         totalAmountOutProvided += quote.tokenOutAmount;

//         totalAmountInExpected += PriceTickMath.getTokenInAmount(
//             poolInputs.isZeroToOne,
//             quote.tokenOutAmount,
//             poolInputs.currentSpotPriceTick
//         );

//         emit LiquidityQuote(poolInputs.currentSpotPriceTick, quote.tokenOutAmount, quote.nextLiquidPriceTick);
//     }

//     function _resetALMFlags() private {
//         totalAmountOutProvided = 0;
//         totalAmountInExpected = 0;
//         participateInSwap = true;
//         swapEnded = false;
//         shouldBeDeactivated = false;
//     }

//     function _checkReentrancy(bool isDepositClosed, bool isWithdrawalClosed) private {
//         if (isReentrant) {
//             if (isDepositClosed) {
//                 // Reenter Deposit
//                 vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
//                 IUniversalPool(pool).depositLiquidity(0, 0, new bytes(0));
//             }

//             if (isWithdrawalClosed) {
//                 // Reenter Withdraw
//                 vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
//                 IUniversalPool(pool).withdrawLiquidity(0, 0, address(1));

//                 // Reenter Withdraw
//                 vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
//                 IUniversalPool(pool).withdrawLiquidity(0, 0, address(1));
//             }

//             // Reenter Spot Price Tick
//             vm.expectRevert(UniversalPool.UniversalPool__spotPriceTick_spotPriceTickLocked.selector);
//             IUniversalPool(pool).spotPriceTick();

//             // Reenter flash loan
//             vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
//             IUniversalPool(pool).flashLoan(false, IFlashBorrower(address(1)), 0, new bytes(0));

//             // Reenter Swap
//             vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
//             IUniversalPool(pool).swap(
//                 SwapParams({
//                     isZeroToOne: false,
//                     isSwapCallback: false,
//                     limitPriceTick: -1,
//                     recipient: address(this),
//                     amountIn: 10e18,
//                     amountOutMin: 0,
//                     swapCallbackContext: new bytes(0),
//                     swapFeeModuleContext: new bytes(0),
//                     almOrdering: new uint8[](1),
//                     externalContext: new bytes[](1)
//                 })
//             );
//         }
//     }

//     function setupSwap(
//         ALMLiquidityQuotePoolInputs memory _almLiquidityQuotePoolInputs,
//         address,
//         uint256 _feeInBips,
//         ALMReserves memory _almReserves,
//         bytes calldata externalContext
//     )
//         external
//         override
//         returns (
//             bool isParticipatingInSwap,
//             bool refreshReserves,
//             ALMLiquidityQuote memory swapSetupQuote
//         )
//     {
//         // Reset all invariant flags, for the case when same ALM is reused in tests
//         _resetALMFlags();

//         assertEq(shouldBeDeactivated, false);

//         isParticipatingInSwap = participateInSwap;

//         {
//             (, ALMPosition memory almPosition) = IUniversalPool(pool).getALMPositionAtAddress(address(this));

//             // Assert that the initial reserves are correct
//             preSwapTokenInReserves = _almLiquidityQuotePoolInputs.isZeroToOne
//                 ? almPosition.reserve0
//                 : almPosition.reserve1;
//             preSwapTokenOutReserves = _almLiquidityQuotePoolInputs.isZeroToOne
//                 ? almPosition.reserve1
//                 : almPosition.reserve0;
//         }

//         assertEq(_almReserves.tokenInReserves, preSwapTokenInReserves);
//         assertEq(_almReserves.tokenOutReserves, preSwapTokenOutReserves);

//         PoolLocks memory state = IUniversalPool(pool).getPoolLockStatus();
//         assertEq(state.withdrawals.value, 2, 'Invariant_setupSwap: withdrawals must be locked');
//         assertEq(state.deposit.value, 1, 'Invariant_setupSwap: deposits must be open');
//         assertEq(state.swap.value, 2, 'Invariant_setupSwap: swaps must be locked');

//         swapSetupQuote = swapSetups[_almLiquidityQuotePoolInputs.currentSpotPriceTick][
//             _almLiquidityQuotePoolInputs.isZeroToOne
//         ];

//         swapSetupQuote.tokenOutAmount = swapSetupQuote.tokenOutAmount > _almLiquidityQuotePoolInputs.amountOutExpected
//             ? _almLiquidityQuotePoolInputs.amountOutExpected
//             : swapSetupQuote.tokenOutAmount;

//         swapSetupQuote.internalContext = externalContext;

//         if (
//             quoteTypes[_almLiquidityQuotePoolInputs.currentSpotPriceTick][_almLiquidityQuotePoolInputs.isZeroToOne] !=
//             MockALMStates.JIT_LIQUIDITY &&
//             swapSetupQuote.tokenOutAmount > preSwapTokenOutReserves
//         ) {
//             swapSetupQuote.tokenOutAmount = preSwapTokenOutReserves;
//         }

//         swapSetups[_almLiquidityQuotePoolInputs.currentSpotPriceTick][_almLiquidityQuotePoolInputs.isZeroToOne]
//             .tokenOutAmount = swapSetupQuote.tokenOutAmount;

//         limitPriceTickForSwap = _almLiquidityQuotePoolInputs.limitPriceTick;
//         feeInBipsForSwap = _feeInBips;

//         assertEq(
//             _almLiquidityQuotePoolInputs.isZeroToOne
//                 ? _almLiquidityQuotePoolInputs.currentSpotPriceTick >= limitPriceTickForSwap
//                 : _almLiquidityQuotePoolInputs.currentSpotPriceTick <= limitPriceTickForSwap,
//             true,
//             'Invariant_setupSwap: spot price tick can never be out of limit price tick bounds'
//         );

//         _checkReentrancy(false, true);

//         refreshReserves = processOutgoingQuote(
//             true,
//             _almLiquidityQuotePoolInputs,
//             swapSetupQuote,
//             quoteTypes[_almLiquidityQuotePoolInputs.currentSpotPriceTick][_almLiquidityQuotePoolInputs.isZeroToOne],
//             _almReserves.tokenInReserves,
//             _almReserves.tokenOutReserves
//         );

//         emit PoolInput(
//             _almLiquidityQuotePoolInputs.isZeroToOne,
//             _almLiquidityQuotePoolInputs.currentSpotPriceTick,
//             _almLiquidityQuotePoolInputs.amountInRemaining,
//             _almLiquidityQuotePoolInputs.amountOutExpected
//         );

//         // console.logInt(_almLiquidityQuotePoolInputs.currentSpotPriceTick);
//         // console.log('MockALM: Setup Swap called, tokenOutAmount: ', swapSetupQuote.tokenOutAmount);
//     }

//     function getLiquidityQuote(
//         ALMLiquidityQuotePoolInputs memory _almLiquidityQuotePoolInputs,
//         ALMReserves memory _almReserves,
//         bytes calldata internalContext
//     ) external override onlyPool returns (ALMLiquidityQuote memory almLiquidityQuote) {
//         assertEq(shouldBeDeactivated, false, 'getLiquidityQuote__shouldBeDeactivated');
//         // getLiquidityQuote can never be called if ALM isn't participating in swap
//         assertEq(participateInSwap, true, 'getLiquidityQuote__participatingInSwap');
//         assertEq(
//             _almLiquidityQuotePoolInputs.currentSpotPriceTick,
//             latestLiquidityQuoteCache.nextLiquidPriceTick,
//             'getLiquidityQuote__priceTickMismatch'
//         );

//         if (_almLiquidityQuotePoolInputs.isZeroToOne) {
//             assertEq(
//                 _almLiquidityQuotePoolInputs.currentSpotPriceTick < latestLiquidityQuoteCache.priceTick,
//                 true,
//                 'getLiquidityQuote__spotPriceConsistency'
//             );
//         } else {
//             assertEq(
//                 _almLiquidityQuotePoolInputs.currentSpotPriceTick > latestLiquidityQuoteCache.priceTick,
//                 true,
//                 'getLiquidityQuote__spotPriceConsistency'
//             );
//         }

//         assertEq(
//             internalContext,
//             latestLiquidityQuoteCache.internalContext,
//             'getLiquidityQuote__internalContextConsistency'
//         );

//         assertEq(swapEnded, false, 'getLiquidityQuote__swapEnded');

//         assertEq(
//             _almReserves.tokenInReserves,
//             preSwapTokenInReserves + totalAmountInExpected,
//             'getLiquidityQuote__tokenInReserves'
//         );

//         assertEq(
//             _almReserves.tokenOutReserves,
//             preSwapTokenOutReserves - totalAmountOutProvided,
//             'getLiquidityQuote__tokenOutReserves'
//         );

//         assertEq(
//             _almLiquidityQuotePoolInputs.isZeroToOne
//                 ? _almLiquidityQuotePoolInputs.currentSpotPriceTick >= limitPriceTickForSwap
//                 : _almLiquidityQuotePoolInputs.currentSpotPriceTick <= limitPriceTickForSwap,
//             true,
//             'Invariant_getLiquidityQuote: spot price tick can never be out of limit price tick bounds'
//         );

//         PoolLocks memory state = IUniversalPool(pool).getPoolLockStatus();
//         assertEq(state.withdrawals.value, 2, 'Invariant_getLiquidityQuote: withdrawals must be locked');
//         assertEq(state.deposit.value, 2, 'Invariant_getLiquidityQuote: deposits must be locked');
//         assertEq(state.swap.value, 2, 'Invariant_getLiquidityQuote: swaps must be locked');

//         (, ALMPosition memory almPosition) = IUniversalPool(pool).getALMPositionAtAddress(address(this));
//         uint256 reserve = _almLiquidityQuotePoolInputs.isZeroToOne ? almPosition.reserve1 : almPosition.reserve0;

//         almLiquidityQuote = liquidityQuotes[_almLiquidityQuotePoolInputs.currentSpotPriceTick][
//             _almLiquidityQuotePoolInputs.isZeroToOne
//         ];

//         if (almLiquidityQuote.tokenOutAmount > _almLiquidityQuotePoolInputs.amountOutExpected) {
//             almLiquidityQuote.tokenOutAmount = _almLiquidityQuotePoolInputs.amountOutExpected;
//         }
//         if (almLiquidityQuote.tokenOutAmount > reserve) {
//             almLiquidityQuote.tokenOutAmount = reserve;
//         }

//         _checkReentrancy(true, true);

//         processOutgoingQuote(
//             false,
//             _almLiquidityQuotePoolInputs,
//             almLiquidityQuote,
//             quoteTypes[_almLiquidityQuotePoolInputs.currentSpotPriceTick][_almLiquidityQuotePoolInputs.isZeroToOne],
//             _almReserves.tokenInReserves,
//             _almReserves.tokenOutReserves
//         );

//         emit PoolInput(
//             _almLiquidityQuotePoolInputs.isZeroToOne,
//             _almLiquidityQuotePoolInputs.currentSpotPriceTick,
//             _almLiquidityQuotePoolInputs.amountInRemaining,
//             _almLiquidityQuotePoolInputs.amountOutExpected
//         );

//         // console.logInt(_almLiquidityQuotePoolInputs.currentSpotPriceTick);
//         // console.log('MockALM: ALM Liquidity Quote called, tokenOutAmount: ', almLiquidityQuote.tokenOutAmount);
//     }

//     function callbackOnSwapEnd(
//         bool _isZeroToOne,
//         uint256 _amountInFilled,
//         uint256 _amountOutProvided,
//         uint256 _feeEarned,
//         ALMReserves memory _almReserves,
//         int24 _spotPriceTickPreSwap,
//         int24 _spotPriceTickPostSwap,
//         // necessary to inform ALM about the last price tick it provided liquidity at
//         // this price tick can be different from spotPriceTick post swap
//         ALMCachedLiquidityQuote calldata latestQuote
//     ) external {
//         assertEq(shouldBeDeactivated, false);

//         // Callback is only made if ALM is participating in swap.
//         assertEq(participateInSwap, true);

//         assertEq(_amountOutProvided, totalAmountOutProvided, 'Invariant_swapEnd: amountOutProvided');
//         assertEq(
//             _almReserves.tokenOutReserves,
//             preSwapTokenOutReserves - totalAmountOutProvided,
//             'Invariant_swapEnd: tokenOutReserves'
//         );

//         // uint256 amountInFilledLoss = (uint256(
//         //     _isZeroToOne
//         //         ? uint24(_spotPriceTickPreSwap - _spotPriceTickPostSwap)
//         //         : uint24(_spotPriceTickPostSwap - _spotPriceTickPreSwap)
//         // ) + 1)* 257;

//         // assertApproxEqAbs(_amountInFilled, totalAmountInExpected, amountInFilledLoss);
//         // assertApproxEqAbs(
//         //     _almReserves.tokenInReserves,
//         //     preSwapTokenInReserves + totalAmountInExpected,
//         //     amountInFilledLoss
//         // );

//         // both structs should be the same
//         assertEq(abi.encode(latestLiquidityQuoteCache), abi.encode(latestQuote));

//         // values are stored correctly in storage
//         (, ALMPosition memory almPosition) = IUniversalPool(pool).getALMPositionAtAddress(address(this));

//         assertEq(
//             _almReserves.tokenInReserves + _feeEarned,
//             _isZeroToOne ? almPosition.reserve0 : almPosition.reserve1,
//             'Invariant_swapEnd: tokenInReserves'
//         );
//         assertEq(
//             _almReserves.tokenOutReserves,
//             _isZeroToOne ? almPosition.reserve1 : almPosition.reserve0,
//             'Invariant_swapEnd: tokenOutReserves'
//         );

//         PoolLocks memory state = IUniversalPool(pool).getPoolLockStatus();
//         assertEq(state.withdrawals.value, 1, 'Invariant_swapEnd: withdrawals must be open');
//         assertEq(state.deposit.value, 1, 'Invariant_swapEnd: deposits must be open');
//         assertEq(state.swap.value, 2, 'Invariant_swapEnd: swaps must be locked');

//         _checkReentrancy(false, false);

//         if (isJITGlobal) {
//             IUniversalPool(pool).withdrawLiquidity(almPosition.reserve0, almPosition.reserve1, address(1));
//         }

//         emit SwapCallback(
//             _isZeroToOne,
//             _amountInFilled,
//             _amountOutProvided,
//             _spotPriceTickPreSwap,
//             _spotPriceTickPostSwap
//         );
//     }
// }

interface IRefreshReserve {
    function refreshReserves(uint256 amount0, uint256 amount1) external;
}

contract MockUniversalALM is IUniversalALM {
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

    function onDepositLiquidityCallback(uint256 _amount0, uint256 _amount1, bytes memory _data) external override {}
}
