// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { Constants } from '../utils/Constants.sol';

/**
    @notice Efficient implementation of price = 1.0001 ^ tick in Q128.128 format.
    @dev    Leverages the fact that any such price can be written as a linear combination of
            pre-computed powers of 2 for base 1.0001.
    @dev    Due to rounding errors, this function has innacuracies
            compared to the ground truth value
            of 1.0001 ^ tick (which can be computed off-chain using arbitrary precision arithmetic)
            Therefore, it contains auxiliary functions which over and under-estimate compared to the ground-truth value.
            The upper and lower bound estimates are then used to compute tokenIn and tokenOut amounts in a way that
            always favors LPs.
 */
library PriceTickMath {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error PriceTickMath__getPriceAtTickOver_invalidPriceTick();
    error PriceTickMath__getPriceAtTickUnder_invalidPriceTick();
    error PriceTickMath__getTickAtPriceOver_invalidPrice();

    /************************************************
     *  CONSTANTS
     ***********************************************/

    // solhint-disable-next-line private-vars-leading-underscore
    int24 internal constant MIN_PRICE_TICK = -720909;
    // solhint-disable-next-line private-vars-leading-underscore
    int24 internal constant MAX_PRICE_TICK = 720909;

    /**
        @notice MIN_PRICE <= price <= MAX_PRICE
        @dev Computed as getPriceAtTickOver(MIN_PRICE_TICK) and getPriceAtTickOver(MAX_PRICE_TICK)
     */
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 internal constant MIN_PRICE = 16777402;
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 internal constant MAX_PRICE = 6901670243043972986255200373924895033102563660822112080378694173663318;

    /**
        @notice Returns Q128.128 price at `tick`.
        @dev Always overestimates relatively to the true price.
        @param tick Price in log-space.
        @return priceX128 Price in Q128.128 format.
     */
    function getPriceAtTickOver(int24 tick) internal pure returns (uint256 priceX128) {
        // Checking tick bounds is sufficient in order to ensure that priceX128 is a valid uint256
        unchecked {
            uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint24(tick);
            if (tick < MIN_PRICE_TICK || tick > MAX_PRICE_TICK) {
                revert PriceTickMath__getPriceAtTickOver_invalidPriceTick();
            }

            if (tick > 0) {
                // Add 1 to compensate for rounding down
                priceX128 = (type(uint256).max / _getPriceAtAbsTickUnder(absTick)) + 1;
            } else {
                priceX128 = _getPriceAtAbsTickOver(absTick);
            }
        }
    }

    /**
        @notice Returns Q128.128 price at `tick`.
        @dev Always underestimates relatively to the true price.
        @param tick Price in log-space.
        @return priceX128 Price in Q128.128 format.
     */
    function getPriceAtTickUnder(int24 tick) internal pure returns (uint256 priceX128) {
        // Checking tick bounds is sufficient in order to ensure that priceX128 is a valid uint256
        unchecked {
            uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint24(tick);
            if (tick < MIN_PRICE_TICK || tick > MAX_PRICE_TICK) {
                revert PriceTickMath__getPriceAtTickUnder_invalidPriceTick();
            }

            if (tick > 0) {
                priceX128 = type(uint256).max / _getPriceAtAbsTickOver(absTick);
            } else {
                priceX128 = _getPriceAtAbsTickUnder(absTick);
            }
        }
    }

    /**
        @notice Compute log_1.0001(priceX128) .
        @param priceX128 Input uint256, computed as an overestimate of true price.
        @return tick Output int24.
     */
    function getTickAtPriceOver(uint256 priceX128) internal pure returns (int24 tick) {
        unchecked {
            if (priceX128 < MIN_PRICE || priceX128 >= MAX_PRICE) {
                revert PriceTickMath__getTickAtPriceOver_invalidPrice();
            }

            uint256 r = priceX128;
            uint256 msb;

            assembly {
                let f := shl(7, gt(r, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(6, gt(r, 0xFFFFFFFFFFFFFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(5, gt(r, 0xFFFFFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(4, gt(r, 0xFFFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(3, gt(r, 0xFF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(2, gt(r, 0xF))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := shl(1, gt(r, 0x3))
                msb := or(msb, f)
                r := shr(f, r)
            }
            assembly {
                let f := gt(r, 0x1)
                msb := or(msb, f)
            }

            if (msb >= 128) r = priceX128 >> (msb - 127);
            else r = priceX128 << (127 - msb);

            // solhint-disable-next-line var-name-mixedcase
            int256 log_2 = (int256(msb) - 128) << 64;

            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(63, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(62, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(61, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(60, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(59, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(58, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(57, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(56, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(55, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(54, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(53, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(52, f))
                r := shr(f, r)
            }
            assembly {
                r := shr(127, mul(r, r))
                let f := shr(128, r)
                log_2 := or(log_2, shl(51, f))
                r := shr(f, r)
            }

            // solhint-disable-next-line var-name-mixedcase
            int256 log_10001 = log_2 * 127869479499801913173571;

            int24 tickLow = int24((log_10001 - 3402992106061532191769419228800470504) >> 128);
            int24 tickHi = int24((log_10001 + 291339465622738926460341080071338528831) >> 128);

            tick = tickLow == tickHi ? tickLow : getPriceAtTickOver(tickHi) <= priceX128 ? tickHi : tickLow;
        }
    }

    /**
        @notice Computes tokenOut amount given tokenInAmount.
        @dev Always underestimates relatively to the true amount,
             hence acting in favor of LPs.
        @param isZeroToOne Direction of the swap.
        @param tokenInAmount Amount of input token.
        @param priceTick Price tick.
     */
    function getTokenOutAmount(
        bool isZeroToOne,
        uint256 tokenInAmount,
        int24 priceTick
    ) internal pure returns (uint256) {
        return
            isZeroToOne
                ? Math.mulDiv(tokenInAmount, getPriceAtTickUnder(priceTick), Constants.Q128)
                : Math.mulDiv(tokenInAmount, Constants.Q128, getPriceAtTickOver(priceTick));
    }

    /**
        @notice Computes tokenIn amount given `tokenOutAmount`.
        @dev Always overestimates relatively to the true amount,
             hence acting in favor of LPs.
        @param isZeroToOne Direction of the swap.
        @param tokenOutAmount Amount of output token.
        @param priceTick Price tick.
     */
    function getTokenInAmount(
        bool isZeroToOne,
        uint256 tokenOutAmount,
        int24 priceTick
    ) internal pure returns (uint256) {
        return
            isZeroToOne
                ? Math.mulDiv(tokenOutAmount, Constants.Q128, getPriceAtTickUnder(priceTick), Math.Rounding.Up)
                : Math.mulDiv(tokenOutAmount, getPriceAtTickOver(priceTick), Constants.Q128, Math.Rounding.Up);
    }

    /**
        @notice Returns Q128.128 price at `absTick`.
        @dev Always overestimates relatively the ground truth value.
        @param absTick Price in log-space.
        @dev It is assumed that `absTick` <= MAX_PRICE_TICK.
        @return priceX128 Price in Q128.128 format.
     */
    function _getPriceAtAbsTickOver(uint256 absTick) private pure returns (uint256 priceX128) {
        unchecked {
            priceX128 = absTick & 0x1 != 0 ? 0xfff97272373d413259a46990580e213a : 0x100000000000000000000000000000000;
            if (absTick & 0x2 != 0) priceX128 = ((priceX128 * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128) + 1;
            if (absTick & 0x4 != 0) priceX128 = ((priceX128 * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128) + 1;
            if (absTick & 0x8 != 0) priceX128 = ((priceX128 * 0xffcb9843d60f6159c9db58835c926644) >> 128) + 1;
            if (absTick & 0x10 != 0) priceX128 = ((priceX128 * 0xff973b41fa98c081472e6896dfb254c0) >> 128) + 1;
            if (absTick & 0x20 != 0) priceX128 = ((priceX128 * 0xff2ea16466c96a3843ec78b326b52861) >> 128) + 1;
            if (absTick & 0x40 != 0) priceX128 = ((priceX128 * 0xfe5dee046a99a2a811c461f1969c3053) >> 128) + 1;
            if (absTick & 0x80 != 0) priceX128 = ((priceX128 * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128) + 1;
            if (absTick & 0x100 != 0) priceX128 = ((priceX128 * 0xf987a7253ac413176f2b074cf7815e54) >> 128) + 1;
            if (absTick & 0x200 != 0) priceX128 = ((priceX128 * 0xf3392b0822b70005940c7a398e4b70f3) >> 128) + 1;
            if (absTick & 0x400 != 0) priceX128 = ((priceX128 * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128) + 1;
            if (absTick & 0x800 != 0) priceX128 = ((priceX128 * 0xd097f3bdfd2022b8845ad8f792aa5826) >> 128) + 1;
            if (absTick & 0x1000 != 0) priceX128 = ((priceX128 * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128) + 1;
            if (absTick & 0x2000 != 0) priceX128 = ((priceX128 * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128) + 1;
            if (absTick & 0x4000 != 0) priceX128 = ((priceX128 * 0x31be135f97d08fd981231505542fcfa6) >> 128) + 1;
            if (absTick & 0x8000 != 0) priceX128 = ((priceX128 * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128) + 1;
            if (absTick & 0x10000 != 0) priceX128 = ((priceX128 * 0x5d6af8dedb81196699c329225ee605) >> 128) + 1;
            if (absTick & 0x20000 != 0) priceX128 = ((priceX128 * 0x2216e584f5fa1ea926041bedfe98) >> 128) + 1;
            if (absTick & 0x40000 != 0) priceX128 = ((priceX128 * 0x48a170391f7dc42444e8fa3) >> 128) + 1;
            if (absTick & 0x80000 != 0) priceX128 = ((priceX128 * 0x149b34ee7ac263) >> 128) + 1;
        }
    }

    /**
        @notice Returns Q128.128 price at `absTick`. 
        @dev Always underestimates relatively to the ground truth value.
        @param absTick Price in log-space.
        @dev It is assumed that `absTick` <= MAX_PRICE_TICK.
        @return priceX128 Price in Q128.128 format.
     */
    function _getPriceAtAbsTickUnder(uint256 absTick) private pure returns (uint256 priceX128) {
        unchecked {
            priceX128 = absTick & 0x1 != 0 ? 0xfff97272373d413259a46990580e2139 : 0x100000000000000000000000000000000;
            if (absTick & 0x2 != 0) priceX128 = (priceX128 * 0xfff2e50f5f656932ef12357cf3c7fdcb) >> 128;
            if (absTick & 0x4 != 0) priceX128 = (priceX128 * 0xffe5caca7e10e4e61c3624eaa0941ccf) >> 128;
            if (absTick & 0x8 != 0) priceX128 = (priceX128 * 0xffcb9843d60f6159c9db58835c926643) >> 128;
            if (absTick & 0x10 != 0) priceX128 = (priceX128 * 0xff973b41fa98c081472e6896dfb254bf) >> 128;
            if (absTick & 0x20 != 0) priceX128 = (priceX128 * 0xff2ea16466c96a3843ec78b326b52860) >> 128;
            if (absTick & 0x40 != 0) priceX128 = (priceX128 * 0xfe5dee046a99a2a811c461f1969c3052) >> 128;
            if (absTick & 0x80 != 0) priceX128 = (priceX128 * 0xfcbe86c7900a88aedcffc83b479aa3a3) >> 128;
            if (absTick & 0x100 != 0) priceX128 = (priceX128 * 0xf987a7253ac413176f2b074cf7815e53) >> 128;
            if (absTick & 0x200 != 0) priceX128 = (priceX128 * 0xf3392b0822b70005940c7a398e4b70f2) >> 128;
            if (absTick & 0x400 != 0) priceX128 = (priceX128 * 0xe7159475a2c29b7443b29c7fa6e889d8) >> 128;
            if (absTick & 0x800 != 0) priceX128 = (priceX128 * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x1000 != 0) priceX128 = (priceX128 * 0xa9f746462d870fdf8a65dc1f90e061e4) >> 128;
            if (absTick & 0x2000 != 0) priceX128 = (priceX128 * 0x70d869a156d2a1b890bb3df62baf32f6) >> 128;
            if (absTick & 0x4000 != 0) priceX128 = (priceX128 * 0x31be135f97d08fd981231505542fcfa5) >> 128;
            if (absTick & 0x8000 != 0) priceX128 = (priceX128 * 0x9aa508b5b7a84e1c677de54f3e99bc8) >> 128;
            if (absTick & 0x10000 != 0) priceX128 = (priceX128 * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x20000 != 0) priceX128 = (priceX128 * 0x2216e584f5fa1ea926041bedfe97) >> 128;
            if (absTick & 0x40000 != 0) priceX128 = (priceX128 * 0x48a170391f7dc42444e8fa2) >> 128;
            if (absTick & 0x80000 != 0) priceX128 = (priceX128 * 0x149b34ee7ac262) >> 128;
        }
    }
}
