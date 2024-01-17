// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';
import { Math } from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import {
    Slot0,
    ALMPosition,
    MetaALMData,
    SwapCache,
    InternalSwapALMState,
    UnderlyingALMQuote,
    PoolState,
    SwapParams
} from 'src/pools/structs/UniversalPoolStructs.sol';
import { EnumerableALMMap } from 'src/libraries/EnumerableALMMap.sol';
import { StateLib } from 'src/pools/libraries/StateLib.sol';
import { GM } from 'src/pools/libraries/GM.sol';
import { PriceTickMath } from 'src/libraries/PriceTickMath.sol';
import {
    ALMLiquidityQuotePoolInputs,
    ALMLiquidityQuote,
    ALMCachedLiquidityQuote,
    ALMReserves
} from 'src/ALM/structs/UniversalALMStructs.sol';
import { IUniversalALM } from 'src/ALM/interfaces/IUniversalALM.sol';

import { MockUniversalALMHelper } from 'test/helpers/MockUniversalALMHelper.sol';

contract GMTest is Test {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;

    /************************************************
     *  Structs
     ***********************************************/

    // 1 bit participating in swap
    // 1 bit refresh reserves
    // 1 bit share quotes
    // 1 bit is call back required
    // 4*3 = 12, atleast 16 bit, first 4 bits are used in global config, 1st bit for isZeroToOne
    // one slot of 85 bits can hold upto 1e26, so one uint256 value can be used to determine 3 reserves for 3 ALMs
    // For amountOut, last 85 bits contains amountOut, middle 85 bits are used to calulcate percent of amountOut by each ALM
    struct SetupSwapFuzzParams {
        uint256 reserve0;
        uint256 reserve1;
        uint16 flags;
        uint256 amountIn;
        uint256 amountOut;
        int24 tickStart;
    }

    // fee0 contains 3 uint80 fee0 alreasy stored for each ALM, remaing bits used for
    // fee1 contains 3 uint80 fee1 already stored for each ALM
    // percents packs the 3 uint16 which represent percent of amount out contributed by each ALM, remaining 16 bits used for poolManagerFeeBips
    // poolManagerFees contains uint128 packed for both token0 and token1
    // liquidityProvided contains 3 uint80 representing liquidity provided by each ALM
    //
    struct UpdatePoolStateFuzzParams {
        uint256 reserve0;
        uint256 reserve1;
        uint256 fee0;
        uint256 fee1;
        uint256 effectiveFee;
        uint256 baseShareQuoteLiquidity;
        uint256 percentAndFlags;
        uint256 poolManagerFees;
    }

    // flags => 1st bit : isZeroToOne
    // flags => 2nd - 4th bit : alm's participating
    // flags => 5th bit - 6th bit : alm's share quotes
    // percentData contains 3 percent points about what percent of amountIn to fill
    //
    struct RequestForQuotesFuzzParams {
        uint256 reserve0;
        uint256 reserve1;
        uint8 flags;
        int24 tickStart;
        uint256 amountIn;
        uint256 amountOutFilled;
        uint256 percentData;
    }

    PoolState internal poolState;
    EnumerableALMMap.ALMSet internal ALMPositions;
    address[] internal alms;

    function setUp() public {
        alms.push(MockUniversalALMHelper.deployMockALM(address(this), false));
        alms.push(MockUniversalALMHelper.deployMockALM(address(this), false));
        alms.push(MockUniversalALMHelper.deployMockALM(address(this), true));

        ALMPositions.add(ALMPosition(Slot0(false, false, false, 0, alms[0]), 0, 0, 0, 0));
        ALMPositions.add(ALMPosition(Slot0(false, false, false, 0, alms[1]), 0, 0, 0, 0));
        // 3rd alm is meta alm
        ALMPositions.add(ALMPosition(Slot0(true, false, false, 0, alms[2]), 0, 0, 0, 0));
    }

    /************************************************
     *  Test functions
     ***********************************************/

    function test_setupSwaps(SetupSwapFuzzParams memory args) public {
        // tick will be same throug out all alm calls in setup swap
        args.tickStart = int24(bound(args.tickStart, int24(-720909 + 10), int24(720909 - 10)));
        args.amountIn = bound(args.amountIn, 1, 1e26);

        SwapParams memory swapParams;

        swapParams.isZeroToOne = args.flags >> 15 == 0;

        if (swapParams.isZeroToOne) {
            swapParams.limitPriceTick = args.tickStart - 10;
        } else {
            swapParams.limitPriceTick = args.tickStart + 10;
        }

        swapParams.amountIn = args.amountIn;

        ALMLiquidityQuote[] memory quotes = new ALMLiquidityQuote[](3);
        bool[] memory isParticipatingInSwaps = new bool[](3);
        bool[] memory isRefreshReserves = new bool[](3);

        uint256 amountOut = uint256(args.amountOut & (1 << 85));
        swapParams.externalContext = new bytes[](3);
        // first 2 alms as base and last as meta alm
        for (uint256 i; i < 3; i++) {
            _setReserves(i, args.reserve0, args.reserve1);

            uint8 almFlag = uint8((args.flags >> (4 * i)) & (1 << 4));

            isParticipatingInSwaps[i] = almFlag & (1 << 8) == 0;

            isRefreshReserves[i] = almFlag & (1 << 7) == 0;

            if (!isParticipatingInSwaps[i]) {
                quotes[i] = ALMLiquidityQuote(0, args.tickStart, new bytes(0));
            } else {
                uint256 percent = bound((args.amountOut << 86) >> (170 + i * 16), 0, 10_000);

                quotes[i] = _constructLiquidityQuote(almFlag, amountOut, percent);
            }

            (, ALMPosition memory almPosition) = ALMPositions.getALM(alms[i]);

            console.log(almPosition.reserve0, almPosition.reserve1);
            swapParams.externalContext[i] = abi.encode(
                isParticipatingInSwaps[i],
                isRefreshReserves[i],
                bound(uint256(almPosition.reserve0 * almFlag), 0, 1e26),
                bound(uint256(almPosition.reserve1 * almFlag), 0, 1e26),
                quotes[i]
            );
        }

        SwapCache memory swapCache;
        swapCache.isMetaALMPool = true;
        swapCache.spotPriceTick = args.tickStart;
        swapCache.spotPriceTickStart = args.tickStart;
        swapCache.amountInMinusFee = args.amountIn;
        swapCache.amountInRemaining = args.amountIn;
        swapCache.numBaseALMs = 2;

        UnderlyingALMQuote[] memory baseALMQuotes = new UnderlyingALMQuote[](3);

        InternalSwapALMState[] memory almStates = _getInitialInternalALMStates(swapParams.isZeroToOne);

        bytes memory errorData = _getSetupSwapError(swapParams, args.tickStart);

        if (errorData.length > 0) {
            vm.expectRevert(errorData);
            this.setupSwap(almStates, baseALMQuotes, swapParams, swapCache);
            return;
        }

        (almStates, baseALMQuotes, swapCache) = this.setupSwap(almStates, baseALMQuotes, swapParams, swapCache);

        for (uint i = 0; i < 3; i++) {
            (bool isParticipatingInSwap, , , , ALMLiquidityQuote memory quote) = abi.decode(
                swapParams.externalContext[i],
                (bool, bool, uint256, uint256, ALMLiquidityQuote)
            );

            if (!isParticipatingInSwap) {
                continue;
            }

            assertEq(almStates[i].totalLiquidityProvided, quote.tokenOutAmount);

            swapCache.amountOutFilled += quote.tokenOutAmount;

            if (swapCache.amountOutFilled == 0) {
                break;
            }
        }
    }

    function test_updatePoolState(UpdatePoolStateFuzzParams memory args) public {
        args.effectiveFee = bound(args.effectiveFee, 100, 1e20);

        poolState.feePoolManager0 = args.poolManagerFees >> 128;
        poolState.feePoolManager1 = args.poolManagerFees << 128;
        poolState.poolManagerFeeBips = 1e2;

        for (uint256 i = 0; i < 3; i++) {
            _setReserves(i, args.reserve0, args.reserve1);
            _setFees(i, args.fee0, args.fee1);
        }

        SwapCache memory swapCache;
        SwapParams memory swapParams;

        uint16 flags = uint16((args.percentAndFlags << 240) >> 240);

        swapParams.isZeroToOne = flags >> 15 == 0;

        InternalSwapALMState[] memory almStates = _getInitialInternalALMStates(swapParams.isZeroToOne);

        // first 192 bits for meta alm fee bps for first 2 alms,
        // next 48 bits for percent data and last 16 for flags
        uint256 percentData = uint256(args.percentAndFlags << 192) >> 208;

        swapCache.effectiveFee = args.effectiveFee;

        for (uint256 i = 0; i < 3; i++) {
            uint256 percent = (percentData << (256 - 16 * (3 - i))) >> 240;

            percent = bound(percent, 0, 1e4);

            almStates[i].totalLiquidityProvided = Math.mulDiv(percent, almStates[i].almReserves.tokenOutReserves, 1e4);

            swapCache.amountOutFilled += almStates[i].totalLiquidityProvided;

            almStates[i].almReserves.tokenOutReserves -= almStates[i].totalLiquidityProvided;

            if (i != 2) {
                almStates[i].almSlot0.shareQuotes = flags & (1 << 2) == 0;
            } else {
                almStates[i].almSlot0.metaALMFeeShare = uint64(bound(args.percentAndFlags >> 64, 0, 1e4));
            }
        }

        swapCache.baseShareQuoteLiquidity = bound(args.baseShareQuoteLiquidity, 0, swapCache.amountOutFilled);
        swapCache.isMetaALMPool = true;

        uint256[] memory feesCumulatives = _getCumulativeFees(swapParams.isZeroToOne);

        bytes32 swapCacheHash = keccak256(abi.encode(swapCache));

        (almStates, swapCache) = this.updatePoolState(almStates, swapParams, swapCache);

        // swapCache shouldn't change
        assertEq(keccak256(abi.encode(swapCache)), swapCacheHash, 'Swap Cache should not be updated');

        uint256 totalALMFee = Math.mulDiv(swapCache.effectiveFee, 1e4 - poolState.poolManagerFeeBips, 1e4);

        if (swapParams.isZeroToOne) {
            assertEq(poolState.feePoolManager0, (args.poolManagerFees >> 128) + args.effectiveFee - totalALMFee);
        } else {
            assertEq(poolState.feePoolManager1, (args.poolManagerFees << 128) + args.effectiveFee - totalALMFee);
        }

        uint256 totalMetaALMSharedFee;

        for (uint256 i = 0; i < 3; i++) {
            (, ALMPosition memory almPosition) = ALMPositions.getALM(alms[2 - i]);

            assertEq(
                swapParams.isZeroToOne ? almPosition.reserve1 : almPosition.reserve0,
                almStates[2 - i].almReserves.tokenOutReserves,
                'Token out reserves not updated'
            );

            uint256 fee = swapCache.amountOutFilled == 0
                ? 0
                : Math.mulDiv(almStates[2 - i].totalLiquidityProvided, totalALMFee, swapCache.amountOutFilled);

            if (i == 0) {
                totalMetaALMSharedFee = Math.mulDiv(fee, almStates[2 - i].almSlot0.metaALMFeeShare, 1e4);

                fee = fee - totalMetaALMSharedFee;
            } else {
                if (almStates[2 - i].almSlot0.shareQuotes && swapCache.baseShareQuoteLiquidity > 0) {
                    fee += Math.mulDiv(
                        totalMetaALMSharedFee,
                        almStates[2 - i].totalLiquidityProvided,
                        swapCache.baseShareQuoteLiquidity
                    );
                }
            }

            assertEq(
                swapParams.isZeroToOne ? almPosition.feeCumulative0 : almPosition.feeCumulative1,
                feesCumulatives[2 - i] + fee,
                'Fee not updated correctly'
            );

            assertEq(
                swapParams.isZeroToOne ? almPosition.reserve0 : almPosition.reserve1,
                almStates[2 - i].almReserves.tokenInReserves + fee,
                'Token In reserves not updated'
            );
        }
    }

    function test_requestForQuotes(RequestForQuotesFuzzParams memory args) public {
        args.tickStart = int24(bound(args.tickStart, int24(-720909 + 3), int24(720909 - 3)));
        args.amountIn = bound(args.amountIn, 1, 1e26);

        SwapParams memory swapParams;
        swapParams.isZeroToOne = args.flags & (1 << 1) == 0;

        args.amountOutFilled = bound(
            args.amountOutFilled,
            0,
            PriceTickMath.getTokenOutAmount(swapParams.isZeroToOne, swapParams.amountIn, args.tickStart)
        );

        for (uint256 i; i < 3; i++) {
            _setReserves(i, args.reserve0, args.reserve1);
        }

        InternalSwapALMState[] memory almStates = _getInitialInternalALMStates(swapParams.isZeroToOne);
        UnderlyingALMQuote[] memory baseALMQuotes = new UnderlyingALMQuote[](3);
        SwapCache memory swapCache;
        swapCache.isMetaALMPool = true;
        swapCache.spotPriceTick = args.tickStart;
        swapCache.spotPriceTickStart = args.tickStart;
        swapCache.amountInMinusFee = args.amountIn;
        swapCache.amountInRemaining =
            args.amountIn -
            PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, args.amountOutFilled, args.tickStart);
        swapCache.amountOutFilled = args.amountOutFilled;
        swapCache.numBaseALMs = 2;

        swapParams.limitPriceTick = swapParams.isZeroToOne ? args.tickStart - 3 : args.tickStart + 3;

        for (uint256 i = 0; i < 3; i++) {
            bool isParticipatingInSwap = args.flags & (1 << (2 + i)) == 0;
            if (!isParticipatingInSwap) {
                almStates[i].isParticipatingInSwap = false;
                continue;
            }

            if (i != 2) {
                bool shareQuotes = args.flags & (1 << (5 + i)) == 0;
                almStates[i].almSlot0.shareQuotes = shareQuotes;
            }
        }

        uint256 amountInRemaining = swapCache.amountInRemaining;
        uint256[] memory amountIns = new uint256[](9);
        for (uint256 i = 0; i < 9; i++) {
            uint256 percent = (args.percentData << (28 * i)) >> 228;
            percent = bound(percent, 0, 1e4);
            amountIns[i] = (amountInRemaining * percent) / 1e4;
            amountInRemaining -= amountIns[i];
        }

        for (uint256 i = 0; i < 3; i++) {
            if (!almStates[i].isParticipatingInSwap) {
                continue;
            }

            int24 tick = swapParams.isZeroToOne ? args.tickStart - 2 : args.tickStart + 2;

            uint256 amountOut = PriceTickMath.getTokenOutAmount(swapParams.isZeroToOne, amountIns[3 * i + 2], tick);

            ALMLiquidityQuote memory quote = ALMLiquidityQuote(amountOut, tick, new bytes(0));

            tick = swapParams.isZeroToOne ? tick + 1 : tick - 1;
            amountOut = PriceTickMath.getTokenOutAmount(swapParams.isZeroToOne, amountIns[3 * i + 1], tick);

            quote = ALMLiquidityQuote(amountOut, swapParams.isZeroToOne ? tick - 1 : tick + 1, abi.encode(quote));

            tick = swapParams.isZeroToOne ? tick + 1 : tick - 1;
            amountOut = PriceTickMath.getTokenOutAmount(swapParams.isZeroToOne, amountIns[3 * i], tick);

            quote = ALMLiquidityQuote(amountOut, swapParams.isZeroToOne ? tick - 1 : tick + 1, abi.encode(quote));

            almStates[i].latestLiquidityQuote = ALMCachedLiquidityQuote(0, 0, tick, abi.encode(quote));
        }

        (almStates, baseALMQuotes, swapCache) = this.requestForQuotes(almStates, baseALMQuotes, swapParams, swapCache);

        if (swapParams.isZeroToOne) {
            assertGe(swapCache.spotPriceTick, swapParams.limitPriceTick);
        } else {
            assertLe(swapCache.spotPriceTick, swapParams.limitPriceTick);
        }

        if (
            !almStates[0].isParticipatingInSwap &&
            !almStates[1].isParticipatingInSwap &&
            !almStates[2].isParticipatingInSwap
        ) {
            assertEq(swapCache.spotPriceTick, args.tickStart);
        } else {
            assertEq(swapCache.spotPriceTick, swapParams.isZeroToOne ? args.tickStart - 2 : args.tickStart + 2);
        }
        uint256 totalAmountOut;
        for (uint256 i = 0; i < 3; i++) {
            if (!almStates[i].isParticipatingInSwap) {
                assertEq(almStates[i].totalLiquidityProvided, 0);
            } else {
                uint256 amountOut = PriceTickMath.getTokenOutAmount(
                    swapParams.isZeroToOne,
                    amountIns[3 * i],
                    args.tickStart
                ) +
                    PriceTickMath.getTokenOutAmount(
                        swapParams.isZeroToOne,
                        amountIns[3 * i + 1],
                        swapParams.isZeroToOne ? args.tickStart - 1 : args.tickStart + 1
                    ) +
                    PriceTickMath.getTokenOutAmount(
                        swapParams.isZeroToOne,
                        amountIns[3 * i + 2],
                        swapParams.isZeroToOne ? args.tickStart - 2 : args.tickStart + 2
                    );

                assertEq(almStates[i].totalLiquidityProvided, amountOut);
                totalAmountOut += amountOut;
            }
        }

        assertEq(totalAmountOut, swapCache.amountOutFilled - args.amountOutFilled);
    }

    function test_updateALMPositionsOnSwapEnd(uint8 flags) public {
        SwapParams memory swapParams;
        swapParams.isZeroToOne = flags & (1 << 1) == 0;

        InternalSwapALMState[] memory almStates = _getInitialInternalALMStates(swapParams.isZeroToOne);

        SwapCache memory swapCache;

        swapCache.spotPriceTickStart = -1;
        swapCache.spotPriceTick = 10;

        for (uint256 i; i < 3; i++) {
            almStates[i].isParticipatingInSwap = flags & (1 << (i + 2)) == 0;
            almStates[i].almSlot0.isCallbackOnSwapEndRequired = flags & (1 << (i + 5)) == 0;

            if (!almStates[i].almSlot0.isCallbackOnSwapEndRequired || !almStates[i].isParticipatingInSwap) {
                continue;
            }

            almStates[i].totalLiquidityReceived = 1e18 * (i + 1);
            almStates[i].totalLiquidityProvided = 2e18 * (i + 1);
            almStates[i].feeEarned = 1e12 * (i + 1);
            almStates[i].almReserves = ALMReserves(100e18 * (i + 1), 300e18 * (i + 1));
            almStates[i].latestLiquidityQuote = ALMCachedLiquidityQuote(
                1e16 * (i + 1),
                int24(uint24(5 * (i + 1))),
                int24(uint24(10 * (i + 1))),
                new bytes(0)
            );

            vm.expectCall(
                almStates[i].almSlot0.almAddress,
                abi.encodeWithSelector(
                    IUniversalALM.callbackOnSwapEnd.selector,
                    swapParams.isZeroToOne,
                    almStates[i].totalLiquidityReceived,
                    almStates[i].totalLiquidityProvided,
                    almStates[i].feeEarned,
                    almStates[i].almReserves,
                    swapCache.spotPriceTickStart,
                    swapCache.spotPriceTick,
                    almStates[i].latestLiquidityQuote
                )
            );
        }

        this.updateALMPositionsOnSwapEnd(almStates, swapParams, swapCache);
    }

    /************************************************
     *  External functions
     ***********************************************/

    function updateALMPositionsOnSwapEnd(
        InternalSwapALMState[] memory almStates,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) public {
        GM.updateALMPositionsOnSwapEnd(almStates, swapParams, swapCache);
    }

    function requestForQuotes(
        InternalSwapALMState[] memory almStates,
        UnderlyingALMQuote[] memory baseALMQuotes,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) public returns (InternalSwapALMState[] memory, UnderlyingALMQuote[] memory, SwapCache memory) {
        GM.requestForQuotes(almStates, baseALMQuotes, swapParams, swapCache);
        return (almStates, baseALMQuotes, swapCache);
    }

    function updatePoolState(
        InternalSwapALMState[] memory almStates,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) public returns (InternalSwapALMState[] memory, SwapCache memory) {
        GM.updatePoolState(almStates, ALMPositions, poolState, swapParams, swapCache);
        return (almStates, swapCache);
    }

    function setupSwap(
        InternalSwapALMState[] memory almStates,
        UnderlyingALMQuote[] memory baseALMQuotes,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) public returns (InternalSwapALMState[] memory, UnderlyingALMQuote[] memory, SwapCache memory) {
        GM.setupSwaps(almStates, baseALMQuotes, ALMPositions, swapParams, swapCache);

        return (almStates, baseALMQuotes, swapCache);
    }

    // Called by mock alm during setup swap
    function refreshReserves(uint256 amount0, uint256 amount1) external {
        (, ALMPosition storage almPosition) = ALMPositions.getALM(msg.sender);

        almPosition.reserve0 += amount0;
        almPosition.reserve1 += amount1;
    }

    /************************************************
     *  Internal functions
     ***********************************************/

    function _getSetupSwapError(SwapParams memory swapParams, int24 priceTick) internal view returns (bytes memory) {
        uint256 amountInRemaining = swapParams.amountIn;
        uint256 amountOutExpected = PriceTickMath.getTokenOutAmount(
            swapParams.isZeroToOne,
            amountInRemaining,
            priceTick
        );

        for (uint i = 0; i < 3; i++) {
            bytes memory contextData = swapParams.externalContext[i];
            (
                bool isParticipatingInSwap,
                bool isRefreshReserves,
                uint256 amount0,
                uint256 amount1,
                ALMLiquidityQuote memory quote
            ) = abi.decode(contextData, (bool, bool, uint256, uint256, ALMLiquidityQuote));

            if (!isParticipatingInSwap) {
                continue;
            }

            (, ALMPosition memory almPosition) = ALMPositions.getALM(alms[i]);

            if (isRefreshReserves) {
                almPosition.reserve0 += amount0;
                almPosition.reserve1 += amount1;
            }

            if (quote.tokenOutAmount > amountOutExpected) {
                return abi.encodeWithSelector(GM.GM__verifyLiquidityQuote_quoteGTExpected.selector, alms[i]);
            }

            if (i != 2) {
                if (
                    swapParams.isZeroToOne &&
                    (quote.nextLiquidPriceTick > priceTick || quote.nextLiquidPriceTick < swapParams.limitPriceTick)
                ) {
                    return abi.encodeWithSelector(GM.GM__verifyLiquidityQuote_invalidNLPT.selector, alms[i]);
                } else if (
                    !swapParams.isZeroToOne &&
                    (quote.nextLiquidPriceTick < priceTick || quote.nextLiquidPriceTick > swapParams.limitPriceTick)
                ) {
                    return abi.encodeWithSelector(GM.GM__verifyLiquidityQuote_invalidNLPT.selector, alms[i]);
                }
            }

            if (quote.tokenOutAmount > (swapParams.isZeroToOne ? almPosition.reserve1 : almPosition.reserve0)) {
                return abi.encodeWithSelector(GM.GM__verifyLiquidityQuote_quoteGTReserves.selector, alms[i]);
            }

            if (quote.tokenOutAmount != 0) {
                uint256 tokenInAmount = PriceTickMath.getTokenInAmount(
                    swapParams.isZeroToOne,
                    quote.tokenOutAmount,
                    priceTick
                );

                if (tokenInAmount > amountInRemaining) {
                    amountInRemaining = 0;
                } else {
                    amountInRemaining -= tokenInAmount;
                }

                if (amountInRemaining == 0) {
                    break;
                }
            }

            amountOutExpected = PriceTickMath.getTokenOutAmount(swapParams.isZeroToOne, amountInRemaining, priceTick);
        }

        return new bytes(0);
    }

    function _setReserves(uint256 index, uint256 reserve0, uint256 reserve1) internal {
        uint256 almReserve0 = uint256((reserve0 << (85 * index)) >> 171);
        uint256 almReserve1 = uint256((reserve1 << (85 * index)) >> 171);

        address alm = alms[index];
        (, ALMPosition storage almPosition) = ALMPositions.getALM(alm);

        almPosition.reserve0 = almReserve0;
        almPosition.reserve1 = almReserve1;
    }

    function _setFees(uint256 index, uint256 fee0, uint256 fee1) internal {
        uint256 almFee0 = uint256((fee0 << (80 * index)) >> 176);
        uint256 almFee1 = uint256((fee1 << (80 * index)) >> 176);

        address alm = alms[index];
        (, ALMPosition storage almPosition) = ALMPositions.getALM(alm);

        almPosition.feeCumulative0 = almFee0;
        almPosition.feeCumulative1 = almFee1;
    }

    function _constructLiquidityQuote(
        uint8 flag,
        uint256 amountOut,
        uint256 percent
    ) internal pure returns (ALMLiquidityQuote memory setupQuote) {
        uint24 deltaTick = uint24(bound(uint8(flag << 4), 0, 10));

        int24 nextTick = flag & (1 << 6) == 0 ? int24(deltaTick) : -int24(deltaTick);

        setupQuote = ALMLiquidityQuote(Math.mulDiv(amountOut, percent, 10_000), nextTick, new bytes(0));
    }

    function _getInitialInternalALMStates(
        bool isZeroToOne
    ) internal view returns (InternalSwapALMState[] memory almStates) {
        almStates = new InternalSwapALMState[](3);

        for (uint i; i < 3; i++) {
            (, ALMPosition memory almPosition) = ALMPositions.getALM(alms[i]);

            almStates[i].almSlot0 = almPosition.slot0;
            almStates[i].almReserves = isZeroToOne
                ? ALMReserves(almPosition.reserve0, almPosition.reserve1)
                : ALMReserves(almPosition.reserve1, almPosition.reserve0);
        }
    }

    function _getCumulativeFees(bool isZero) internal view returns (uint256[] memory fees) {
        fees = new uint256[](3);

        for (uint256 i; i < 3; i++) {
            (, ALMPosition memory almPosition) = ALMPositions.getALM(alms[i]);

            fees[i] = isZero ? almPosition.feeCumulative0 : almPosition.feeCumulative1;
        }
    }
}
