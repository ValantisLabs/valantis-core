// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { Constants } from '../utils/Constants.sol';

/**
    @notice Efficient implementation of price = 1.0001 ^ tick in Q128.128 format.
    @dev    Leverages the fact that any such price can be written as a linear combination of
            pre-computed powers of 2 for base 1.0001.
 */
library PriceTickMath {
    /************************************************
     *  CONSTANTS
     ***********************************************/

    int24 internal constant MIN_PRICE_TICK = -720909;
    int24 internal constant MAX_PRICE_TICK = 720909;

    /**
        @notice MIN_PRICE <= price <= MAX_PRICE
     */
    uint256 internal constant MIN_PRICE = 16777401;
    uint256 internal constant MAX_PRICE = 6901670243043972986255200373924895033102563660822112080378694173663318;

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error PriceTickMath__getPriceAtTick_invalidPriceTick();
    error PriceTickMath__getTickAtPrice_invalidPrice();

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    /**
        @notice Returns Q128.128 price at `tick`.
        @param tick Price in log-space.
        @return priceX128 Price in Q128.128 format.
     */
    function getPriceAtTick(int24 tick) internal pure returns (uint256 priceX128) {
        // Checking tick bounds is sufficient in order to ensure that priceX128 is a valid uint256
        unchecked {
            uint256 absTick = tick < 0 ? uint256(-int256(tick)) : uint24(tick);
            if (tick < MIN_PRICE_TICK || tick > MAX_PRICE_TICK) {
                revert PriceTickMath__getPriceAtTick_invalidPriceTick();
            }

            priceX128 = absTick & 0x1 != 0 ? 0xfff97272373d413259a46990580e213a : 0x100000000000000000000000000000000;
            if (absTick & 0x2 != 0) priceX128 = (priceX128 * 0xfff2e50f5f656932ef12357cf3c7fdcc) >> 128;
            if (absTick & 0x4 != 0) priceX128 = (priceX128 * 0xffe5caca7e10e4e61c3624eaa0941cd0) >> 128;
            if (absTick & 0x8 != 0) priceX128 = (priceX128 * 0xffcb9843d60f6159c9db58835c926644) >> 128;
            if (absTick & 0x10 != 0) priceX128 = (priceX128 * 0xff973b41fa98c081472e6896dfb254c0) >> 128;
            if (absTick & 0x20 != 0) priceX128 = (priceX128 * 0xff2ea16466c96a3843ec78b326b52861) >> 128;
            if (absTick & 0x40 != 0) priceX128 = (priceX128 * 0xfe5dee046a99a2a811c461f1969c3053) >> 128;
            if (absTick & 0x80 != 0) priceX128 = (priceX128 * 0xfcbe86c7900a88aedcffc83b479aa3a4) >> 128;
            if (absTick & 0x100 != 0) priceX128 = (priceX128 * 0xf987a7253ac413176f2b074cf7815e54) >> 128;
            if (absTick & 0x200 != 0) priceX128 = (priceX128 * 0xf3392b0822b70005940c7a398e4b70f3) >> 128;
            if (absTick & 0x400 != 0) priceX128 = (priceX128 * 0xe7159475a2c29b7443b29c7fa6e889d9) >> 128;
            if (absTick & 0x800 != 0) priceX128 = (priceX128 * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
            if (absTick & 0x1000 != 0) priceX128 = (priceX128 * 0xa9f746462d870fdf8a65dc1f90e061e5) >> 128;
            if (absTick & 0x2000 != 0) priceX128 = (priceX128 * 0x70d869a156d2a1b890bb3df62baf32f7) >> 128;
            if (absTick & 0x4000 != 0) priceX128 = (priceX128 * 0x31be135f97d08fd981231505542fcfa6) >> 128;
            if (absTick & 0x8000 != 0) priceX128 = (priceX128 * 0x9aa508b5b7a84e1c677de54f3e99bc9) >> 128;
            if (absTick & 0x10000 != 0) priceX128 = (priceX128 * 0x5d6af8dedb81196699c329225ee604) >> 128;
            if (absTick & 0x20000 != 0) priceX128 = (priceX128 * 0x2216e584f5fa1ea926041bedfe98) >> 128;
            if (absTick & 0x40000 != 0) priceX128 = (priceX128 * 0x48a170391f7dc42444e8fa2) >> 128;
            if (absTick & 0x80000 != 0) priceX128 = (priceX128 * 0x149b34ee7ac263) >> 128;

            if (tick > 0) priceX128 = type(uint256).max / priceX128;
        }
    }

    // AUDIT: Determine bounds for precision loss.
    /**
        @notice Compute log_1.0001(priceX128) .
        @param priceX128 Input uint256.
        @return tick Output int24.
     */
    function getTickAtPrice(uint256 priceX128) internal pure returns (int24 tick) {
        unchecked {
            if (priceX128 < MIN_PRICE || priceX128 >= MAX_PRICE) {
                revert PriceTickMath__getTickAtPrice_invalidPrice();
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

            int256 log_10001 = log_2 * 127869479499801913173571;

            int24 tickLow = int24((log_10001 - 3402992106061532191769419228800470504) >> 128);
            int24 tickHi = int24((log_10001 + 291339465622738926460341080071338528831) >> 128);

            tick = tickLow == tickHi ? tickLow : getPriceAtTick(tickHi) <= priceX128 ? tickHi : tickLow;
        }
    }

    /**
        @notice Computes tokenOut amount given tokenInAmount
        @param isZeroToOne Direction of the swap.
        @param tokenInAmount Amount of input token.
        @param priceTick Price tick. 
     */
    function getTokenOutAmount(
        bool isZeroToOne,
        uint256 tokenInAmount,
        int24 priceTick
    ) internal pure returns (uint256) {
        uint256 priceX128 = getPriceAtTick(priceTick);

        return
            isZeroToOne
                ? Math.mulDiv(tokenInAmount, priceX128, Constants.Q128)
                : Math.mulDiv(tokenInAmount, Constants.Q128, priceX128);
    }

    /**
        @notice Computes tokenIn amount given `tokenOutAmount`.
        @param isZeroToOne Direction of the swap.
        @param tokenOutAmount Amount of output token.
        @param priceTick Price tick. 
     */
    function getTokenInAmount(
        bool isZeroToOne,
        uint256 tokenOutAmount,
        int24 priceTick
    ) internal pure returns (uint256) {
        uint256 priceX128 = getPriceAtTick(priceTick);

        return
            isZeroToOne
                ? Math.mulDiv(tokenOutAmount, Constants.Q128, priceX128, Math.Rounding.Up)
                : Math.mulDiv(tokenOutAmount, priceX128, Constants.Q128, Math.Rounding.Up);
    }
}
