// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { PriceTickMath } from 'src/libraries/PriceTickMath.sol';

contract PriceTickMathTest is Test {
    /************************************************
     *  Test Functions
     ***********************************************/

    function test_getPriceAtTick(int24 tick) public {
        if (tick < PriceTickMath.MIN_PRICE_TICK || tick > PriceTickMath.MAX_PRICE_TICK) {
            vm.expectRevert(PriceTickMath.PriceTickMath__getPriceAtTickOver_invalidPriceTick.selector);
        }
        uint256 priceX128Over = PriceTickMath.getPriceAtTickOver(tick);

        int24 tickResultOver = PriceTickMath.getTickAtPriceOver(priceX128Over);
        assertEq(tickResultOver, tick);
    }

    function test_getTickAtPrice(uint256 price) public {
        if (price < PriceTickMath.MIN_PRICE || price >= PriceTickMath.MAX_PRICE) {
            vm.expectRevert(PriceTickMath.PriceTickMath__getTickAtPriceOver_invalidPrice.selector);
        }

        int24 tick = PriceTickMath.getTickAtPriceOver(price);
        uint256 priceResult = PriceTickMath.getPriceAtTickOver(tick);

        if (tick != PriceTickMath.MAX_PRICE_TICK) assert(PriceTickMath.getPriceAtTickOver(tick + 1) > price);

        assert(PriceTickMath.getPriceAtTickOver(tick) <= price);
        assertEq(PriceTickMath.getTickAtPriceOver(priceResult), tick);
    }

    function test_uniqueTickValues() public {
        int24 startTick = 600_000;

        uint256 priceCache;
        uint256 price;

        for (int24 tick = startTick; tick <= PriceTickMath.MAX_PRICE_TICK; ) {
            price = PriceTickMath.getPriceAtTickOver(tick);
            if (price == priceCache) {
                console.logInt(tick);
                assertEq(false, true, 'Duplication Found');
            }
            priceCache = price;

            unchecked {
                ++tick;
            }
        }

        for (int24 tick = -startTick; tick >= PriceTickMath.MIN_PRICE_TICK; ) {
            price = PriceTickMath.getPriceAtTickOver(tick);
            if (price == priceCache) {
                console.logInt(tick);
                assertEq(false, true, 'Duplication Found');
            }
            priceCache = price;

            unchecked {
                --tick;
            }
        }
    }
}
