// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import {
    Slot0,
    ALMPosition,
    MetaALMData,
    SwapCache,
    InternalSwapALMState,
    UnderlyingALMQuote,
    PoolState,
    SwapParams
} from '../structs/UniversalPoolStructs.sol';
import { EnumerableALMMap } from '../../libraries/EnumerableALMMap.sol';
import { StateLib } from './StateLib.sol';
import { IUniversalALM } from '../../ALM/interfaces/IUniversalALM.sol';
import {
    ALMLiquidityQuotePoolInputs,
    ALMLiquidityQuote,
    ALMCachedLiquidityQuote,
    ALMReserves
} from '../../ALM/structs/UniversalALMStructs.sol';
import { PriceTickMath } from '../../libraries/PriceTickMath.sol';

/**
    @notice Library of helper functions.
        Allows the Universal Pool to apply the GM algorithm on the set of ALMs.
*/
library GM {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;
    using StateLib for EnumerableALMMap.ALMSet;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error GM__verifyLiquidityQuote_quoteGTExpected(address);
    error GM__verifyLiquidityQuote_quoteGTReserves(address);
    error GM__verifyLiquidityQuote_invalidNLPT(address);

    /************************************************
     *  CONSTANTS
     ***********************************************/

    /**
        @notice Maximum BIPS for calculation of fee using bips 
     */
    uint256 private constant MAX_SWAP_FEE_BIPS = 1e4;

    /**
        @notice Factor of one or 100% representation in Basis points
     */
    uint256 private constant FACTOR_ONE = 10_000;

    /************************************************
     *  INTERNAL FUNCTIONS
     ***********************************************/
    /**
        @notice Performs the setupSwap operation on all ALMs.
        @return next spot price tick.
     */
    function setupSwaps(
        InternalSwapALMState[] memory almStates,
        UnderlyingALMQuote[] memory baseALMQuotes,
        EnumerableALMMap.ALMSet storage ALMPositions,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) internal returns (int24) {
        // Generate the pool inputs to ALMs
        ALMLiquidityQuotePoolInputs memory almLiquidityQuotePoolInputs = _getALMLiquidityQuoteInput(
            swapCache,
            swapParams
        );

        // Setup swap does only one round of calls.
        for (uint256 almNum; almNum < almStates.length; ) {
            // Make the setup call
            ALMLiquidityQuote memory _setupQuote;

            (almStates[almNum].isParticipatingInSwap, almStates[almNum].refreshReserves, _setupQuote) = IUniversalALM(
                almStates[almNum].almSlot0.almAddress
            ).setupSwap(
                    almLiquidityQuotePoolInputs,
                    msg.sender,
                    swapCache.feeInBips,
                    almStates[almNum].almReserves,
                    // Append baseALMQuotes to external context, if call is being made to meta ALM
                    _getContext(almStates[almNum].almSlot0.isMetaALM, baseALMQuotes, swapParams.externalContext[almNum])
                );

            if (almStates[almNum].isParticipatingInSwap) {
                // If participating in swap, ALM reserves are cached from storage again after setupSwap call
                // Gives ALM opportunity to deposit JIT liquidity
                // WARNING: ALMs should never deposit into other ALM during setup swap
                // can lead to unaccounted deposits thus leading to loss of funds for ALM

                if (almStates[almNum].refreshReserves) {
                    almStates[almNum].almReserves = ALMPositions.getALMReserves(
                        almLiquidityQuotePoolInputs.isZeroToOne,
                        almStates[almNum].almSlot0.almAddress
                    );
                }
                // Revert the transaction if the quote is invalid.
                _verifyLiquidityQuote(_setupQuote, almLiquidityQuotePoolInputs, almStates[almNum]);

                // If the tokenOutAmount is non zero, then process the quote.
                if (_setupQuote.tokenOutAmount != 0) {
                    _processLiquidityQuote(_setupQuote, almLiquidityQuotePoolInputs, almStates[almNum], swapCache);

                    // If amountInRemaining is 0 or amountOutExpect = 0, swap has been filled, so stop the loop.
                    if (swapCache.amountInRemaining == 0 || almLiquidityQuotePoolInputs.amountOutExpected == 0) {
                        // The spot price tick does not change.
                        return almLiquidityQuotePoolInputs.currentSpotPriceTick;
                    }

                    // For all Base ALMs that shareQuotes, cache their quote to send to Meta ALMs.
                    _writeBaseALMQuote(almNum, swapCache, almStates[almNum], baseALMQuotes);
                } else {
                    // Latest liquidity quote needs to be cached, even if tokenOutAmount is 0.
                    almStates[almNum].latestLiquidityQuote = ALMCachedLiquidityQuote({
                        tokenOutAmount: 0,
                        priceTick: almLiquidityQuotePoolInputs.currentSpotPriceTick,
                        nextLiquidPriceTick: _setupQuote.nextLiquidPriceTick,
                        internalContext: _setupQuote.internalContext
                    });
                }
            }

            unchecked {
                ++almNum;
            }
        }

        // After the round has ended, find the next liquid price tick in the direction of the swap.
        (bool foundNextSpotPriceTick, int24 nextSpotPriceTick) = _getNextSpotPriceTick(
            almLiquidityQuotePoolInputs,
            almStates,
            baseALMQuotes,
            swapCache
        );

        if (foundNextSpotPriceTick) {
            // If a price tick is found, then the swap continues to RFQ.
            return nextSpotPriceTick;
        } else {
            // If no liquidity quotes are available, spot price does not change, and swap should end.
            return almLiquidityQuotePoolInputs.currentSpotPriceTick;
        }
    }

    /**
        @notice Performs the getLiquidityQuote operation on all ALMs.
        @return postSwapSpotPriceTick Final spot price tick post swap.
     */
    function requestForQuotes(
        InternalSwapALMState[] memory almStates,
        UnderlyingALMQuote[] memory baseALMQuotes,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) internal returns (int24 postSwapSpotPriceTick) {
        // Initialize almLiquidityQuotePoolInputs
        ALMLiquidityQuotePoolInputs memory almLiquidityQuotePoolInputs = _getALMLiquidityQuoteInput(
            swapCache,
            swapParams
        );

        // Get tokenOut liquidity quotes from each ALM
        while (true) {
            // Loop termination conditions -
            // 1. AmountInRemaining is 0 --> swap is completely filled.
            // 2. No more liquidity quotes are available --> swap is partially filled.
            uint256 numALMs = almStates.length;
            for (uint256 almNum; almNum < numALMs; ) {
                // Only call an ALM if -
                // 1. It is participatingInSwap.
                // 2. If the current spotPriceTick is equal to the nextLiquidPriceTick indicated by the ALM.
                if (
                    almStates[almNum].isParticipatingInSwap &&
                    (almStates[almNum].latestLiquidityQuote.nextLiquidPriceTick ==
                        almLiquidityQuotePoolInputs.currentSpotPriceTick)
                ) {
                    ALMLiquidityQuote memory _almLiquidityQuote = IUniversalALM(almStates[almNum].almSlot0.almAddress)
                        .getLiquidityQuote(
                            almLiquidityQuotePoolInputs,
                            almStates[almNum].almReserves,
                            _getContext(
                                almStates[almNum].almSlot0.isMetaALM,
                                baseALMQuotes,
                                almStates[almNum].latestLiquidityQuote.internalContext
                            )
                        );

                    // Revert the transaction if the quote is invalid.
                    _verifyLiquidityQuote(_almLiquidityQuote, almLiquidityQuotePoolInputs, almStates[almNum]);

                    _processLiquidityQuote(
                        _almLiquidityQuote,
                        almLiquidityQuotePoolInputs,
                        almStates[almNum],
                        swapCache
                    );

                    // If amountInRemaining is 0, then the swap has been completely filled, so stop the loop.
                    if (swapCache.amountInRemaining == 0) {
                        // The spot price tick does not change.
                        return almLiquidityQuotePoolInputs.currentSpotPriceTick;
                    }

                    // For all Base ALMs that shareQuotes, cache their quote to send to Meta ALMs.
                    _writeBaseALMQuote(almNum, swapCache, almStates[almNum], baseALMQuotes);
                }

                unchecked {
                    ++almNum;
                }
            }

            // After the round has ended, find the next liquid price tick in the direction of the swap.
            (bool foundNextSpotPriceTick, int24 nextSpotPriceTick) = _getNextSpotPriceTick(
                almLiquidityQuotePoolInputs,
                almStates,
                baseALMQuotes,
                swapCache
            );

            if (foundNextSpotPriceTick) {
                // If a price tick is found, then continue to the next round.
                almLiquidityQuotePoolInputs.currentSpotPriceTick = nextSpotPriceTick;

                // Update the amountOutExpected according to the new spot price tick.
                almLiquidityQuotePoolInputs.amountOutExpected = PriceTickMath.getTokenOutAmount(
                    almLiquidityQuotePoolInputs.isZeroToOne,
                    almLiquidityQuotePoolInputs.amountInRemaining,
                    nextSpotPriceTick
                );

                if (almLiquidityQuotePoolInputs.amountOutExpected == 0) {
                    return almLiquidityQuotePoolInputs.currentSpotPriceTick;
                }
            } else {
                // Update the swap cache spot price tick to the last value at which quotes were requested.
                // If no liquidity quotes are available, then swap should end.
                return almLiquidityQuotePoolInputs.currentSpotPriceTick;
            }
        }
    }

    /**
        @notice Updates all ALMPositions and pool manager fees post swap.
     */
    function updatePoolState(
        InternalSwapALMState[] memory almStates,
        EnumerableALMMap.ALMSet storage ALMPositions,
        PoolState storage state,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) internal {
        // Calculate ALM Fee
        uint256 totalALMFee = Math.mulDiv(swapCache.effectiveFee, FACTOR_ONE - state.poolManagerFeeBips, FACTOR_ONE);
        uint256 totalMetaALMSharedFee;

        // Set Pool Manager Fee
        {
            uint256 poolManagerFee = swapCache.effectiveFee - totalALMFee;
            if (poolManagerFee > 0) {
                swapParams.isZeroToOne
                    ? (state.feePoolManager0 += poolManagerFee)
                    : (state.feePoolManager1 += poolManagerFee);
            }
        }

        // Loop backwards, so that fee shares for all Meta ALMs are updated first
        uint256 i = almStates.length - 1;
        while (true) {
            if (almStates[i].totalLiquidityProvided != 0) {
                uint256 almFeeEarned;

                if (almStates[i].almSlot0.isMetaALM) {
                    uint256 fee = Math.mulDiv(
                        totalALMFee,
                        almStates[i].totalLiquidityProvided,
                        swapCache.amountOutFilled
                    );

                    uint256 sharedFee = Math.mulDiv(fee, almStates[i].almSlot0.metaALMFeeShare, FACTOR_ONE);
                    almFeeEarned = fee - sharedFee;
                    totalMetaALMSharedFee += sharedFee;
                } else {
                    almFeeEarned = Math.mulDiv(
                        totalALMFee,
                        almStates[i].totalLiquidityProvided,
                        swapCache.amountOutFilled
                    );

                    if (
                        swapCache.isMetaALMPool &&
                        almStates[i].almSlot0.shareQuotes &&
                        swapCache.baseShareQuoteLiquidity != 0
                    ) {
                        almFeeEarned += Math.mulDiv(
                            totalMetaALMSharedFee,
                            almStates[i].totalLiquidityProvided,
                            swapCache.baseShareQuoteLiquidity
                        );
                    }
                }

                almStates[i].feeEarned = almFeeEarned;
            }

            if (almStates[i].totalLiquidityReceived != 0 || almStates[i].totalLiquidityProvided != 0) {
                ALMPositions.updateReservesPostSwap(
                    swapParams.isZeroToOne,
                    almStates[i].almSlot0.almAddress,
                    almStates[i].almReserves,
                    almStates[i].feeEarned
                );
            }

            unchecked {
                if (i == 0) {
                    break;
                } else {
                    --i;
                }
            }
        }
    }

    /**
        @notice Performs the callbackOnSwapEnd operation on all ALMs
     */
    function updateALMPositionsOnSwapEnd(
        InternalSwapALMState[] memory almStates,
        SwapParams calldata swapParams,
        SwapCache memory swapCache
    ) internal {
        uint256 numALMs = almStates.length;
        for (uint256 i; i < numALMs; ) {
            if (almStates[i].isParticipatingInSwap && almStates[i].almSlot0.isCallbackOnSwapEndRequired) {
                IUniversalALM(almStates[i].almSlot0.almAddress).callbackOnSwapEnd(
                    swapParams.isZeroToOne,
                    almStates[i].totalLiquidityReceived,
                    almStates[i].totalLiquidityProvided,
                    almStates[i].feeEarned,
                    almStates[i].almReserves,
                    swapCache.spotPriceTickStart,
                    swapCache.spotPriceTick,
                    almStates[i].latestLiquidityQuote
                );
            }

            unchecked {
                ++i;
            }
        }
    }

    /************************************************
     *  PRIVATE FUNCTIONS
     ***********************************************/

    function _verifyLiquidityQuote(
        ALMLiquidityQuote memory almLiquidityQuote,
        ALMLiquidityQuotePoolInputs memory almLiquidityQuotePoolInputs,
        InternalSwapALMState memory internalSwapALMState
    ) private pure {
        // ALMs cannot quote amounts greater than needed by the swap
        if (almLiquidityQuote.tokenOutAmount > almLiquidityQuotePoolInputs.amountOutExpected) {
            revert GM__verifyLiquidityQuote_quoteGTExpected(internalSwapALMState.almSlot0.almAddress);
        }

        // Checks only for base ALMs
        if (!internalSwapALMState.almSlot0.isMetaALM) {
            // Next liquid price tick has to be valid for current spot price tick
            // Next liquid price tick has to be within limit price tick bounds
            if (almLiquidityQuotePoolInputs.isZeroToOne) {
                if (
                    (almLiquidityQuote.nextLiquidPriceTick > almLiquidityQuotePoolInputs.currentSpotPriceTick) ||
                    almLiquidityQuote.nextLiquidPriceTick < almLiquidityQuotePoolInputs.limitPriceTick
                ) {
                    revert GM__verifyLiquidityQuote_invalidNLPT(internalSwapALMState.almSlot0.almAddress);
                }
            } else {
                if (
                    (almLiquidityQuote.nextLiquidPriceTick < almLiquidityQuotePoolInputs.currentSpotPriceTick) ||
                    almLiquidityQuote.nextLiquidPriceTick > almLiquidityQuotePoolInputs.limitPriceTick
                ) {
                    revert GM__verifyLiquidityQuote_invalidNLPT(internalSwapALMState.almSlot0.almAddress);
                }
            }
        }

        // tokenOut amount cannot be greater than its reserves
        if (almLiquidityQuote.tokenOutAmount > internalSwapALMState.almReserves.tokenOutReserves) {
            revert GM__verifyLiquidityQuote_quoteGTReserves(internalSwapALMState.almSlot0.almAddress);
        }
    }

    /**
        @notice Updates internal accounting, after a quote is received.
     */
    function _processLiquidityQuote(
        ALMLiquidityQuote memory almLiquidityQuote,
        ALMLiquidityQuotePoolInputs memory almLiquidityQuotePoolInputs,
        InternalSwapALMState memory internalSwapALMState,
        SwapCache memory swapCache
    ) private pure {
        uint256 tokenInAmount;

        almLiquidityQuotePoolInputs.amountOutExpected -= almLiquidityQuote.tokenOutAmount;

        // If amountOutExpected is 0, avoid redundant calls due to precision issues by setting amountInRemaining to 0.
        if (almLiquidityQuotePoolInputs.amountOutExpected == 0) {
            tokenInAmount = almLiquidityQuotePoolInputs.amountInRemaining;
        } else {
            // This function rounds up to ensure that precision loss
            // favors LPs
            tokenInAmount = PriceTickMath.getTokenInAmount(
                almLiquidityQuotePoolInputs.isZeroToOne,
                almLiquidityQuote.tokenOutAmount,
                almLiquidityQuotePoolInputs.currentSpotPriceTick
            );

            if (tokenInAmount > almLiquidityQuotePoolInputs.amountInRemaining) {
                tokenInAmount = almLiquidityQuotePoolInputs.amountInRemaining;
            }
        }
        almLiquidityQuotePoolInputs.amountInRemaining -= tokenInAmount;

        // Process liquidity quote
        internalSwapALMState.totalLiquidityProvided += almLiquidityQuote.tokenOutAmount;
        internalSwapALMState.totalLiquidityReceived += tokenInAmount;
        internalSwapALMState.almReserves.tokenOutReserves -= almLiquidityQuote.tokenOutAmount;
        internalSwapALMState.almReserves.tokenInReserves += tokenInAmount;

        swapCache.amountOutFilled += almLiquidityQuote.tokenOutAmount;
        swapCache.amountInRemaining = almLiquidityQuotePoolInputs.amountInRemaining;

        internalSwapALMState.latestLiquidityQuote = ALMCachedLiquidityQuote({
            tokenOutAmount: almLiquidityQuote.tokenOutAmount,
            priceTick: almLiquidityQuotePoolInputs.currentSpotPriceTick,
            nextLiquidPriceTick: almLiquidityQuote.nextLiquidPriceTick,
            internalContext: almLiquidityQuote.internalContext
        });
    }

    /**
        @notice Returns the context for setupSwap and getLiquidityQuote calls.
        @dev For base ALMs, it returns the context value, for meta ALMs it appends the baseALMQuotes array to context.
     */
    function _getContext(
        bool isMetaALM,
        UnderlyingALMQuote[] memory baseALMQuotes,
        bytes memory context
    ) private pure returns (bytes memory) {
        return (isMetaALM ? abi.encode(MetaALMData({ almQuotes: baseALMQuotes, almContext: context })) : context);
    }

    /**
        @notice Constructs the pool inputs for the setupSwap and getLiquidityQuote calls.
     */
    function _getALMLiquidityQuoteInput(
        SwapCache memory swapCache,
        SwapParams calldata swapParams
    ) private pure returns (ALMLiquidityQuotePoolInputs memory) {
        return
            ALMLiquidityQuotePoolInputs({
                isZeroToOne: swapParams.isZeroToOne,
                limitPriceTick: swapParams.limitPriceTick,
                currentSpotPriceTick: swapCache.spotPriceTick,
                amountInRemaining: swapCache.amountInRemaining,
                amountOutExpected: PriceTickMath.getTokenOutAmount(
                    swapParams.isZeroToOne,
                    swapCache.amountInRemaining,
                    swapCache.spotPriceTick
                )
            });
    }

    /**
        @notice Returns the next liquid price tick in the direction of the swap.
        @return isValid is set to true, if the function can find a valid next spot price tick.
        @return nextSpotPriceTick is the next liquid price tick in the direction of the swap.
     */
    function _getNextSpotPriceTick(
        ALMLiquidityQuotePoolInputs memory almLiquidityQuotePoolInputs,
        InternalSwapALMState[] memory almStates,
        UnderlyingALMQuote[] memory baseALMQuotes,
        SwapCache memory swapCache
    ) private pure returns (bool isValid, int24 nextSpotPriceTick) {
        // If zero => one, then spot price will decrease
        // Else spot price will increase
        // Therefore we set initialValues of nextSpotPrice 1 tick beyond the extremes
        nextSpotPriceTick = almLiquidityQuotePoolInputs.isZeroToOne
            ? PriceTickMath.MIN_PRICE_TICK - 1
            : PriceTickMath.MAX_PRICE_TICK + 1;

        // Determine the next liquid price tick
        for (uint256 almNum; almNum < swapCache.numBaseALMs; ) {
            // Reset baseALMQuote array, since execution must be at the end of the round.
            if (swapCache.isMetaALMPool) {
                baseALMQuotes[almNum].tokenOutAmount = 0;
                baseALMQuotes[almNum].isValidQuote = false;
            }

            if (almStates[almNum].isParticipatingInSwap) {
                // Check if this nextLiquidPriceTick is better than the candidate nextSpotPriceTick
                int24 nextLiquidPriceTick = almStates[almNum].latestLiquidityQuote.nextLiquidPriceTick;

                if (
                    almLiquidityQuotePoolInputs.isZeroToOne
                        ? ((nextLiquidPriceTick > nextSpotPriceTick) &&
                            (nextLiquidPriceTick < almLiquidityQuotePoolInputs.currentSpotPriceTick))
                        : ((nextLiquidPriceTick < nextSpotPriceTick) &&
                            (nextLiquidPriceTick > almLiquidityQuotePoolInputs.currentSpotPriceTick))
                ) {
                    // If ALM sends next liquid price tick as current spot price tick,
                    // then it will not provide any further liquidity in this swap
                    nextSpotPriceTick = nextLiquidPriceTick;
                    isValid = true;
                }
            }

            unchecked {
                ++almNum;
            }
        }
    }

    /**
        @notice Updates the quotes coming from a base ALM into the baseALMQuotes array.
        @dev Update happens only if the almNum corresponds to a baseALM, and the pool has atleast 1 metaALM.
     */
    function _writeBaseALMQuote(
        uint256 almNum,
        SwapCache memory swapCache,
        InternalSwapALMState memory almState,
        UnderlyingALMQuote[] memory baseALMQuotes
    ) private pure {
        // For all base ALMs -
        // 1. Update the quotes in baseALMQuotes array
        // 2. Update nextLiquidPriceTick
        // NOTE: Meta ALMs do not have pricing power, so they are skipped.
        if (swapCache.isMetaALMPool && !almState.almSlot0.isMetaALM && almState.almSlot0.shareQuotes) {
            // If quote is processed successfully, then update the value for metaALM use
            baseALMQuotes[almNum].tokenOutAmount = almState.latestLiquidityQuote.tokenOutAmount;
            baseALMQuotes[almNum].isValidQuote = true;
            // Total liquidity provided by ALMs which share quotes
            // Needed for metaALMFeeShare calculations
            swapCache.baseShareQuoteLiquidity += almState.latestLiquidityQuote.tokenOutAmount;
        }
    }
}
