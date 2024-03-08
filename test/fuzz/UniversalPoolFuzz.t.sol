// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import {
    Slot0,
    ALMPosition,
    ALMStatus,
    UnderlyingALMQuote,
    SwapCache,
    InternalSwapALMState,
    PoolState,
    SwapParams
} from 'src/pools/structs/UniversalPoolStructs.sol';
import { ALMLib } from 'src/pools/libraries/ALMLib.sol';
import { IFlashBorrower } from 'src/pools/interfaces/IFlashBorrower.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';
import { UniversalPool } from 'src/pools/UniversalPool.sol';
import { ALMLiquidityQuote, ALMCachedLiquidityQuote } from 'src/ALM/structs/UniversalALMStructs.sol';
import { PriceTickMath } from 'src/libraries/PriceTickMath.sol';
import { GM } from 'src/pools/libraries/GM.sol';

import { UniversalPoolBase } from 'test/base/UniversalPoolBase.t.sol';
import { MockUniversalALMHelper } from 'test/helpers/MockUniversalALMHelper.sol';
import { MockSwapFeeModuleHelper } from 'test/helpers/MockSwapFeeModuleHelper.sol';

contract UniversalPoolFuzz is UniversalPoolBase {
    /************************************************
     *  STRUCTS
     ***********************************************/

    struct DepositFuzzParams {
        uint8 almNum;
        uint256 amount0;
        uint256 amount1;
        uint256 reserve0;
        uint256 reserve1;
    }

    struct WithdrawFuzzParams {
        uint8 almNum;
        uint256 amount0;
        uint256 amount1;
        uint256 reserve0;
        uint256 reserve1;
    }

    struct FlashloanFuzzParams {
        uint256 amount;
        bool isTokenZero;
        uint256 op;
        uint256 reserve0;
        uint256 reserve1;
    }

    // flags 8 bit
    // 1 bit -> isZeroToOne
    // 2 bit -> SwapCallback
    // 3 bit -> External Swap Fee Module
    // 4 bit -> alm1 participating in swap
    // 5 bit -> alm2 participating in swap
    // 6 bit -> alm3 participating in swap
    // reserves0 -> break into 3 85 bit values and use as ALM reserves
    // reserves1 -> break into 3 85 bit values and use as ALM reserves
    // amountInAndOut -> break into 2 128 values, 1 being amountIn and 2nd being amountOut
    // amountOutMin -> Minimum amountMin first 128 bit. Next 128 bits used in calculating ALMLiquidityQuote for ALMs
    struct SwapFuzzParams {
        uint8 flags;
        uint256 reserves0;
        uint256 reserves1;
        uint256 amountInAndOut;
        uint256 amountOutMin;
        uint256 deadline;
        int24 tick;
        int24 limitPriceTick;
    }

    address[] internal alms;

    function setUp() public virtual override {
        super.setUp();

        alms.push(MockUniversalALMHelper.deployMockALM(address(pool), false));
        alms.push(MockUniversalALMHelper.deployMockALM(address(pool), false));
        alms.push(MockUniversalALMHelper.deployMockALM(address(pool), true));

        vm.startPrank(POOL_MANAGER);
        pool.initializeTick(0);

        pool.addALMPosition(false, false, true, 0, alms[0]);
        pool.addALMPosition(false, true, false, 0, alms[1]);
        pool.addALMPosition(true, true, false, 100, alms[2]);

        _addToContractsToApprove(alms[0]);
        _addToContractsToApprove(alms[1]);
        _addToContractsToApprove(alms[2]);

        vm.stopPrank();
    }

    /************************************************
     *  Test public functions
     ***********************************************/

    function test_deposit(DepositFuzzParams memory fuzzParams) public {
        fuzzParams.almNum = uint8(bound(fuzzParams.almNum, 0, 2));
        fuzzParams.reserve0 = bound(fuzzParams.reserve0, 0, 1e26);
        fuzzParams.reserve1 = bound(fuzzParams.reserve1, 0, 1e26);
        fuzzParams.amount0 = bound(fuzzParams.amount0, 0, 1e26);
        fuzzParams.amount1 = bound(fuzzParams.amount1, 0, 1e26);

        _setALMReserves(fuzzParams.almNum, fuzzParams.reserve0, fuzzParams.reserve1);

        _setupBalanceForUser(address(pool), address(token0), fuzzParams.reserve0);
        _setupBalanceForUser(address(pool), address(token1), fuzzParams.reserve1);

        _setupBalanceForUser(address(this), address(token0), fuzzParams.amount0);
        _setupBalanceForUser(address(this), address(token1), fuzzParams.amount1);

        if (fuzzParams.amount0 == 0 && fuzzParams.amount1 == 0) {
            vm.expectRevert(ALMLib.ALMLib__depositLiquidity_zeroAmounts.selector);
            MockUniversalALMHelper.depositLiquidity(alms[fuzzParams.almNum], fuzzParams.amount0, fuzzParams.amount1);
            return;
        }

        MockUniversalALMHelper.depositLiquidity(alms[fuzzParams.almNum], fuzzParams.amount0, fuzzParams.amount1);

        (, ALMPosition memory almPosition) = pool.getALMPositionAtAddress(alms[fuzzParams.almNum]);

        assertEq(almPosition.reserve0, fuzzParams.amount0 + fuzzParams.reserve0);
        assertEq(almPosition.reserve1, fuzzParams.amount1 + fuzzParams.reserve1);

        // check no other alm is updated
        for (uint256 i; i < 3; i++) {
            if (i == fuzzParams.almNum) {
                continue;
            }
            (, almPosition) = pool.getALMPositionAtAddress(alms[i]);
            assertEq(almPosition.reserve0, 0);
            assertEq(almPosition.reserve1, 0);
        }
    }

    function test_withdraw(WithdrawFuzzParams memory fuzzParams) public {
        fuzzParams.almNum = uint8(bound(fuzzParams.almNum, 0, 2));
        fuzzParams.reserve0 = bound(fuzzParams.reserve0, 0, 1e26);
        fuzzParams.reserve1 = bound(fuzzParams.reserve1, 0, 1e26);
        fuzzParams.amount0 = bound(fuzzParams.amount0, 0, 1e26);
        fuzzParams.amount1 = bound(fuzzParams.amount1, 0, 1e26);

        _setALMReserves(fuzzParams.almNum, fuzzParams.reserve0, fuzzParams.reserve1);

        address RECIPIENT = _randomUser();

        _setupBalanceForUser(address(pool), address(token0), fuzzParams.reserve0);
        _setupBalanceForUser(address(pool), address(token1), fuzzParams.reserve1);

        vm.prank(alms[fuzzParams.almNum]);

        if (fuzzParams.reserve0 < fuzzParams.amount0 || fuzzParams.reserve1 < fuzzParams.amount1) {
            vm.expectRevert(ALMLib.ALMLib__withdrawLiquidity_insufficientReserves.selector);
            pool.withdrawLiquidity(fuzzParams.amount0, fuzzParams.amount1, RECIPIENT);
            return;
        }

        if (fuzzParams.amount0 > 0)
            vm.expectCall(
                address(token0),
                abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, fuzzParams.amount0)
            );
        if (fuzzParams.amount1 > 0)
            vm.expectCall(
                address(token1),
                abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, fuzzParams.amount1)
            );

        pool.withdrawLiquidity(fuzzParams.amount0, fuzzParams.amount1, RECIPIENT);

        (, ALMPosition memory almPosition) = pool.getALMPositionAtAddress(alms[fuzzParams.almNum]);

        assertEq(almPosition.reserve0, fuzzParams.reserve0 - fuzzParams.amount0);
        assertEq(almPosition.reserve1, fuzzParams.reserve1 - fuzzParams.amount1);

        // check no other alm is updated
        for (uint256 i; i < 3; i++) {
            if (i == fuzzParams.almNum) {
                continue;
            }
            (, almPosition) = pool.getALMPositionAtAddress(alms[i]);
            assertEq(almPosition.reserve0, 0);
            assertEq(almPosition.reserve1, 0);
        }
    }

    function test_flashloan(FlashloanFuzzParams memory fuzzParams) public {
        fuzzParams.amount = bound(fuzzParams.amount, 1, 1e26);
        IFlashBorrower FLASH_BORROWER = IFlashBorrower(address(this));

        _setupBalanceForUser(address(pool), address(token0), fuzzParams.reserve0);
        _setupBalanceForUser(address(pool), address(token1), fuzzParams.reserve1);

        uint256 tokenReserve = fuzzParams.isTokenZero ? fuzzParams.reserve0 : fuzzParams.reserve1;

        if (fuzzParams.amount > tokenReserve) {
            vm.expectRevert('ERC20: transfer amount exceeds balance');
        } else if (fuzzParams.op == 0) {
            vm.expectRevert(IValantisPool.ValantisPool__flashloan_callbackFailed.selector);
        } else if (fuzzParams.op == 3) {
            if (fuzzParams.amount < (fuzzParams.isTokenZero ? fuzzParams.reserve0 : fuzzParams.reserve1)) {
                vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanNotRepaid.selector);
            }
        } else if (fuzzParams.op == 2) {
            /// Passing condition
        } else {
            vm.expectRevert('ERC20: insufficient allowance');
        }

        pool.flashLoan(
            fuzzParams.isTokenZero,
            FLASH_BORROWER,
            fuzzParams.amount,
            abi.encode(fuzzParams.op, address(this))
        );

        _assertTokenBalance(token0, address(pool), fuzzParams.reserve0);
        _assertTokenBalance(token1, address(pool), fuzzParams.reserve1);
    }

    function test_swap(SwapFuzzParams memory fuzzParams) public {
        SwapParams memory swapParams;

        swapParams.isZeroToOne = fuzzParams.flags & (1 << 1) == 0;
        swapParams.isSwapCallback = fuzzParams.flags & (1 << 2) == 0;

        fuzzParams.tick = int24(bound(fuzzParams.tick, PriceTickMath.MIN_PRICE_TICK, PriceTickMath.MAX_PRICE_TICK));
        fuzzParams.limitPriceTick = int24(
            bound(fuzzParams.limitPriceTick, PriceTickMath.MIN_PRICE_TICK, PriceTickMath.MAX_PRICE_TICK)
        );
        fuzzParams.amountOutMin = bound(fuzzParams.amountOutMin, 0, 1e26);

        swapParams.limitPriceTick = fuzzParams.limitPriceTick;

        uint256 amountOut = bound(fuzzParams.amountInAndOut >> 128, 0, 1e26);
        uint256 swapFeeBips;

        swapParams.amountIn = bound((fuzzParams.amountInAndOut << 128) >> 128, 0, 1e26);
        swapParams.amountOutMin = fuzzParams.amountOutMin >> 128;
        swapParams.recipient = _randomUser();
        swapParams.deadline = bound(fuzzParams.deadline >> 128, 0, block.timestamp + 100);

        _setupReserves(fuzzParams.reserves0, fuzzParams.reserves1);

        _setPriceTick(fuzzParams.tick);

        // set swap fee module
        if (fuzzParams.flags & (1 << 3) == 1) {
            address swapFeeModule = MockSwapFeeModuleHelper.deployMockSwapFeeModule();
            PoolState memory poolState = _defaultPoolState();
            poolState.swapFeeModule = swapFeeModule;
            vm.prank(POOL_MANAGER);
            pool.setPoolState(poolState);

            swapFeeBips = bound((fuzzParams.deadline << 128) >> 128, 0, 1e4);
            vm.prank(POOL_MANAGER);
            MockSwapFeeModuleHelper.setSwapFeeBips(swapFeeModule, swapFeeBips);
        }

        // Pool Setup complete

        swapParams.externalContext = new bytes[](3);

        for (uint256 i; i < 3; i++) {
            uint256 almQuoteHelper = (fuzzParams.amountOutMin << 128) >> 128;

            uint256 almData = (almQuoteHelper << (256 - 42 * (1 + i))) >> 214;

            if (fuzzParams.flags & (1 << (4 + i)) == 0) {
                ALMLiquidityQuote memory dummyQuote;
                dummyQuote.nextLiquidPriceTick = fuzzParams.tick;
                swapParams.externalContext[i] = abi.encode(false, false, 0, 0, dummyQuote);
                continue;
            }
            swapParams.externalContext[i] = _prepareExternalContext(
                amountOut,
                almData,
                fuzzParams.tick,
                swapParams.isZeroToOne
            );
        }

        swapParams.almOrdering = new uint8[](2);
        swapParams.almOrdering[1] = 1;

        if (swapParams.deadline < block.timestamp) {
            vm.expectRevert(UniversalPool.UniversalPool__swap_expired.selector);
            pool.swap(swapParams);
            return;
        }

        if (swapParams.amountIn == 0) {
            vm.expectRevert(UniversalPool.UniversalPool__swap_amountInCannotBeZero.selector);
            pool.swap(swapParams);
            return;
        }

        if (
            swapParams.limitPriceTick < PriceTickMath.MIN_PRICE_TICK ||
            swapParams.limitPriceTick > PriceTickMath.MAX_PRICE_TICK ||
            (swapParams.isZeroToOne && swapParams.limitPriceTick > fuzzParams.tick) ||
            (!swapParams.isZeroToOne && swapParams.limitPriceTick < fuzzParams.tick)
        ) {
            vm.expectRevert(UniversalPool.UniversalPool__swap_invalidLimitPriceTick.selector);
            pool.swap(swapParams);
            return;
        }

        (uint256 amountOutExpected, bytes memory errorData) = _getSwapInfo(swapParams, swapFeeBips, fuzzParams.tick);

        if (errorData.length > 0) {
            vm.expectRevert(errorData);
            pool.swap(swapParams);
            return;
        }

        if (!swapParams.isSwapCallback) {
            _setupBalanceForUser(
                address(this),
                swapParams.isZeroToOne ? address(token0) : address(token1),
                swapParams.amountIn
            );
        } else {
            swapParams.swapCallbackContext = abi.encode(true, swapParams.amountIn);
        }

        (uint256 amountInUsed, uint256 amountOutActual) = pool.swap(swapParams);

        assertLe(amountInUsed, swapParams.amountIn);
        assertEq(amountOutActual, amountOutExpected);
    }

    // 10 bits for percent, 32 bit remaining, 10 bits each used for 3 quote
    function _prepareExternalContext(
        uint256 amountOut,
        uint256 almData,
        int24 startTick,
        bool isZeroToOne
    ) internal pure returns (bytes memory externalContext) {
        uint256 almAmountOut = (amountOut * bound(almData >> 32, 0, 1e4)) / 1e4;

        // 10 bit, 1-4 bit diff tick, 5-10 part of almAmountOut/10
        uint256 quoteData = (almData << 226) >> 246;

        int24[] memory ticks = new int24[](3);

        ALMLiquidityQuote memory firstQuote;
        int24 currentTick = startTick;
        uint256 quotePart = bound(quoteData & 0x3C0, 0, 10);
        uint256 tickAmountOut = (quotePart * almAmountOut) / 10;
        if (isZeroToOne) {
            currentTick = currentTick - int24(uint24(quoteData & 0x3F));
        } else {
            currentTick = currentTick + int24(uint24(quoteData & 0x3F));
        }

        ticks[0] = currentTick;
        firstQuote.tokenOutAmount = tickAmountOut;

        almAmountOut -= tickAmountOut;

        ALMLiquidityQuote memory secondQuote;
        quoteData = (almData << 236) >> 246;
        quotePart = bound(quoteData & 0x3C0, 0, 10);
        tickAmountOut = (quotePart * almAmountOut) / 10;

        if (isZeroToOne) {
            currentTick = currentTick - int24(uint24(quoteData & 0x3F));
        } else {
            currentTick = currentTick + int24(uint24(quoteData & 0x3F));
        }

        secondQuote.tokenOutAmount = tickAmountOut;
        ticks[1] = currentTick;

        almAmountOut -= tickAmountOut;

        ALMLiquidityQuote memory thirdQuote;
        quoteData = (almData << 246) >> 246;
        quotePart = bound(quoteData & 0x3C0, 0, 10);
        tickAmountOut = almAmountOut;

        if (isZeroToOne) {
            currentTick = currentTick - int24(uint24(quoteData & 0x3F));
        } else {
            currentTick = currentTick + int24(uint24(quoteData & 0x3F));
        }

        thirdQuote.tokenOutAmount = tickAmountOut;
        ticks[2] = currentTick;

        if (ticks[2] != ticks[1] && thirdQuote.tokenOutAmount > 0) {
            thirdQuote.nextLiquidPriceTick = ticks[2];
            secondQuote.nextLiquidPriceTick = ticks[2];
            secondQuote.internalContext = abi.encode(thirdQuote);
        } else {
            secondQuote.nextLiquidPriceTick = ticks[1];
        }

        if (ticks[1] != ticks[0] && secondQuote.tokenOutAmount > 0) {
            if (secondQuote.internalContext.length == 0) {
                secondQuote.nextLiquidPriceTick = ticks[1];
            }

            firstQuote.nextLiquidPriceTick = ticks[1];
            firstQuote.internalContext = abi.encode(secondQuote);
        } else if (secondQuote.internalContext.length > 0) {
            firstQuote.nextLiquidPriceTick = ticks[2];
            firstQuote.internalContext = secondQuote.internalContext;
        } else {
            firstQuote.nextLiquidPriceTick = ticks[0];
        }

        ALMLiquidityQuote memory setupQuote;
        if (ticks[0] == startTick) {
            setupQuote = firstQuote;
        } else if (firstQuote.tokenOutAmount > 0) {
            setupQuote.nextLiquidPriceTick = ticks[0];
            setupQuote.internalContext = abi.encode(firstQuote);
        } else if (firstQuote.internalContext.length > 0) {
            setupQuote.nextLiquidPriceTick = firstQuote.nextLiquidPriceTick;
            setupQuote.internalContext = firstQuote.internalContext;
        } else {
            setupQuote.nextLiquidPriceTick = startTick;
        }

        externalContext = abi.encode(true, false, 0, 0, setupQuote);
    }

    function _setupReserves(uint256 reserves0, uint256 reserves1) internal {
        uint256 totalReserve0 = 0;
        uint256 totalReserve1 = 0;

        for (uint256 i; i < 3; i++) {
            uint256 reserve0 = (reserves0 << (256 - 85 * (1 + i))) >> 171;
            uint256 reserve1 = (reserves1 << (256 - 85 * (1 + i))) >> 171;
            _setALMReserves(i, reserve0, reserve1);

            totalReserve0 += reserve0;
            totalReserve1 += reserve1;
        }

        _setupBalanceForUser(address(pool), address(token0), totalReserve0);
        _setupBalanceForUser(address(pool), address(token1), totalReserve1);
    }

    function _getSwapInfo(
        SwapParams memory swapParams,
        uint256 swapFeeBips,
        int24 priceTick
    ) internal view returns (uint256, bytes memory) {
        uint256 amountInRemaining = (swapParams.amountIn * 1e4) / (1e4 + swapFeeBips);

        InternalSwapALMState[] memory almStates = new InternalSwapALMState[](3);

        uint256 amountOutExpected = PriceTickMath.getTokenOutAmount(
            swapParams.isZeroToOne,
            amountInRemaining,
            priceTick
        );

        for (uint i = 0; i < 3; i++) {
            if (amountInRemaining == 0) {
                break;
            }
            bytes memory contextData = swapParams.externalContext[i];
            (bool isParticipatingInSwap, , , , ALMLiquidityQuote memory quote) = abi.decode(
                contextData,
                (bool, bool, uint256, uint256, ALMLiquidityQuote)
            );

            if (!isParticipatingInSwap) {
                continue;
            }
            almStates[i].isParticipatingInSwap = true;

            {
                (, ALMPosition memory almPosition) = pool.getALMPositionAtAddress(alms[i]);

                almStates[i].almSlot0 = almPosition.slot0;

                almStates[i].almReserves.tokenInReserves = swapParams.isZeroToOne
                    ? almPosition.reserve0
                    : almPosition.reserve1;
                almStates[i].almReserves.tokenOutReserves = swapParams.isZeroToOne
                    ? almPosition.reserve1
                    : almPosition.reserve0;
            }

            if (quote.tokenOutAmount > amountOutExpected) {
                return (
                    0,
                    abi.encodeWithSelector(
                        GM.GM__verifyLiquidityQuote_quoteGTExpected.selector,
                        almStates[i].almSlot0.almAddress
                    )
                );
            }

            if (i != 2) {
                if (
                    swapParams.isZeroToOne &&
                    (quote.nextLiquidPriceTick > priceTick || quote.nextLiquidPriceTick < swapParams.limitPriceTick)
                ) {
                    return (
                        0,
                        abi.encodeWithSelector(
                            GM.GM__verifyLiquidityQuote_invalidNLPT.selector,
                            almStates[i].almSlot0.almAddress
                        )
                    );
                } else if (
                    !swapParams.isZeroToOne &&
                    (quote.nextLiquidPriceTick < priceTick || quote.nextLiquidPriceTick > swapParams.limitPriceTick)
                ) {
                    return (
                        0,
                        abi.encodeWithSelector(
                            GM.GM__verifyLiquidityQuote_invalidNLPT.selector,
                            almStates[i].almSlot0.almAddress
                        )
                    );
                }
            }

            if (quote.tokenOutAmount > almStates[i].almReserves.tokenOutReserves) {
                return (
                    0,
                    abi.encodeWithSelector(
                        GM.GM__verifyLiquidityQuote_quoteGTReserves.selector,
                        almStates[i].almSlot0.almAddress
                    )
                );
            }

            if (quote.tokenOutAmount != 0) {
                (amountInRemaining, almStates[i]) = _updateALMState(
                    quote,
                    almStates[i],
                    amountInRemaining,
                    swapParams.isZeroToOne,
                    priceTick
                );

                if (amountInRemaining == 0) {
                    break;
                }
            }

            almStates[i].latestLiquidityQuote = ALMCachedLiquidityQuote(
                quote.tokenOutAmount,
                priceTick,
                quote.nextLiquidPriceTick,
                quote.internalContext
            );

            amountOutExpected = PriceTickMath.getTokenOutAmount(swapParams.isZeroToOne, amountInRemaining, priceTick);
            if (almStates[i].latestLiquidityQuote.nextLiquidPriceTick == priceTick) {
                almStates[i].isParticipatingInSwap = false;
            }
        }

        if (amountInRemaining == 0 && amountOutExpected < swapParams.amountOutMin) {
            return (0, abi.encode(UniversalPool.UniversalPool__swap_minAmountOutNotFilled.selector));
        }

        if (amountInRemaining == 0) {
            return (0, new bytes(0));
        }

        int24 nextTick = _getNextTick(almStates, swapParams.isZeroToOne);

        if (
            (swapParams.isZeroToOne && nextTick == PriceTickMath.MIN_PRICE_TICK) ||
            (!swapParams.isZeroToOne && nextTick == PriceTickMath.MAX_PRICE_TICK)
        ) {
            return (
                almStates[0].totalLiquidityProvided +
                    almStates[1].totalLiquidityProvided +
                    almStates[2].totalLiquidityProvided,
                new bytes(0)
            );
        }

        if (nextTick != priceTick) {
            bytes memory rfqError = _getRFQError(
                almStates,
                amountInRemaining,
                swapParams.isZeroToOne,
                nextTick,
                swapParams.limitPriceTick
            );

            if (rfqError.length > 0) {
                return (0, rfqError);
            }
        }

        uint256 amountOutTotal;

        for (uint256 i; i < 3; i++) {
            amountOutTotal += almStates[i].totalLiquidityProvided;
        }

        if (amountOutTotal < swapParams.amountOutMin) {
            return (amountOutTotal, abi.encode(UniversalPool.UniversalPool__swap_minAmountOutNotFilled.selector));
        }

        return (amountOutTotal, new bytes(0));
    }

    function _getRFQError(
        InternalSwapALMState[] memory almStates,
        uint256 amountInRemaining,
        bool isZeroToOne,
        int24 tickStart,
        int24 limitPriceTick
    ) internal pure returns (bytes memory) {
        int24 currentTick = tickStart;
        uint j = 0;
        while (true) {
            uint256 amountOutExpected = PriceTickMath.getTokenOutAmount(isZeroToOne, amountInRemaining, currentTick);

            for (uint i; i < 3; i++) {
                if (
                    !almStates[i].isParticipatingInSwap ||
                    almStates[i].latestLiquidityQuote.nextLiquidPriceTick != currentTick
                ) {
                    continue;
                }

                ALMLiquidityQuote memory quote = abi.decode(
                    almStates[i].latestLiquidityQuote.internalContext,
                    (ALMLiquidityQuote)
                );

                if (quote.tokenOutAmount > amountOutExpected) {
                    return
                        abi.encodeWithSelector(
                            GM.GM__verifyLiquidityQuote_quoteGTExpected.selector,
                            almStates[i].almSlot0.almAddress
                        );
                }

                if (i != 2) {
                    if (
                        isZeroToOne &&
                        (quote.nextLiquidPriceTick > currentTick || quote.nextLiquidPriceTick < limitPriceTick)
                    ) {
                        return
                            abi.encodeWithSelector(
                                GM.GM__verifyLiquidityQuote_invalidNLPT.selector,
                                almStates[i].almSlot0.almAddress
                            );
                    } else if (
                        !isZeroToOne &&
                        (quote.nextLiquidPriceTick < currentTick || quote.nextLiquidPriceTick > limitPriceTick)
                    ) {
                        return
                            abi.encodeWithSelector(
                                GM.GM__verifyLiquidityQuote_invalidNLPT.selector,
                                almStates[i].almSlot0.almAddress
                            );
                    }
                }

                if (quote.tokenOutAmount > almStates[i].almReserves.tokenOutReserves) {
                    return
                        abi.encodeWithSelector(
                            GM.GM__verifyLiquidityQuote_quoteGTReserves.selector,
                            almStates[i].almSlot0.almAddress
                        );
                }

                if (quote.tokenOutAmount != 0) {
                    (amountInRemaining, almStates[i]) = _updateALMState(
                        quote,
                        almStates[i],
                        amountInRemaining,
                        isZeroToOne,
                        currentTick
                    );

                    if (amountInRemaining == 0) {
                        break;
                    }
                }
                almStates[i].latestLiquidityQuote = ALMCachedLiquidityQuote(
                    quote.tokenOutAmount,
                    currentTick,
                    quote.nextLiquidPriceTick,
                    quote.internalContext
                );

                if (almStates[i].latestLiquidityQuote.nextLiquidPriceTick == currentTick) {
                    almStates[i].isParticipatingInSwap = false;
                }
            }

            if (amountInRemaining == 0) {
                break;
            }

            int24 nextTick = _getNextTick(almStates, isZeroToOne);

            if (
                (isZeroToOne && nextTick == PriceTickMath.MIN_PRICE_TICK) ||
                (!isZeroToOne && nextTick == PriceTickMath.MAX_PRICE_TICK)
            ) {
                break;
            }

            if (nextTick == currentTick) {
                break;
            }

            if ((isZeroToOne && nextTick < limitPriceTick) || (!isZeroToOne && nextTick > limitPriceTick)) {
                break;
            }
            currentTick = nextTick;
            j++;
            if (j > 9) {
                break;
            }
        }

        return new bytes(0);
    }

    function _updateALMState(
        ALMLiquidityQuote memory quote,
        InternalSwapALMState memory almState,
        uint256 amountInRemaining,
        bool isZeroToOne,
        int24 tick
    ) internal pure returns (uint256, InternalSwapALMState memory) {
        almState.totalLiquidityProvided += quote.tokenOutAmount;
        almState.almReserves.tokenOutReserves -= quote.tokenOutAmount;

        uint256 tokenInAmount = PriceTickMath.getTokenInAmount(isZeroToOne, quote.tokenOutAmount, tick);

        if (tokenInAmount > amountInRemaining) {
            almState.totalLiquidityReceived = amountInRemaining;
            almState.almReserves.tokenInReserves += amountInRemaining;
            amountInRemaining = 0;
        } else {
            almState.totalLiquidityReceived = tokenInAmount;
            almState.almReserves.tokenInReserves += tokenInAmount;
            amountInRemaining -= tokenInAmount;
        }

        return (amountInRemaining, almState);
    }

    function _getNextTick(InternalSwapALMState[] memory almStates, bool isZeroToOne) internal pure returns (int24) {
        int24 nextTick = isZeroToOne ? PriceTickMath.MIN_PRICE_TICK : PriceTickMath.MAX_PRICE_TICK;

        for (uint256 i; i < 2; i++) {
            if (!almStates[i].isParticipatingInSwap) {
                continue;
            }

            if (isZeroToOne && almStates[i].latestLiquidityQuote.nextLiquidPriceTick > nextTick) {
                nextTick = almStates[i].latestLiquidityQuote.nextLiquidPriceTick;
            }

            if (!isZeroToOne && almStates[i].latestLiquidityQuote.nextLiquidPriceTick < nextTick) {
                nextTick = almStates[i].latestLiquidityQuote.nextLiquidPriceTick;
            }
        }

        return nextTick;
    }
}
