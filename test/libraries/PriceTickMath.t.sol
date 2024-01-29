// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { PriceTickMath } from 'src/libraries/PriceTickMath.sol';

contract Harness {
    function getPriceAtTick(int24 tick) external pure returns (uint256) {
        uint256 priceX128 = PriceTickMath.getPriceAtTick(tick);
        return priceX128;
    }

    function getTickAtPrice(uint256 priceX128) external pure returns (int24) {
        int24 tick = PriceTickMath.getTickAtPrice(priceX128);
        return tick;
    }
}

contract PriceTickMathTest is Test {
    Harness harness;

    function setUp() public {
        harness = new Harness();
    }

    /************************************************
     *  Test Functions
     ***********************************************/

    function test_getPriceAtTick(int24 tick) public {
        if (tick < PriceTickMath.MIN_PRICE_TICK || tick > PriceTickMath.MAX_PRICE_TICK) {
            vm.expectRevert(PriceTickMath.PriceTickMath__getPriceAtTickOver_invalidPriceTick.selector);
        }
        uint256 priceX128Over = harness.getPriceAtTickOver(tick);

        if (tick < PriceTickMath.MIN_PRICE_TICK || tick > PriceTickMath.MAX_PRICE_TICK) {
            return;
        }

        int24 tickResultOver = harness.getTickAtPriceOver(priceX128Over);
        assertEq(tickResultOver, tick);
    }

    function test_getTickAtPrice(uint256 price) public {
        if (price < PriceTickMath.MIN_PRICE || price >= PriceTickMath.MAX_PRICE) {
            vm.expectRevert(PriceTickMath.PriceTickMath__getTickAtPriceOver_invalidPrice.selector);
        }

        int24 tick = harness.getTickAtPriceOver(price);

        if (price < PriceTickMath.MIN_PRICE || price >= PriceTickMath.MAX_PRICE) {
            return;
        }

        uint256 priceResult = harness.getPriceAtTickOver(tick);

        if (tick != PriceTickMath.MAX_PRICE_TICK) assert(harness.getPriceAtTickOver(tick + 1) > price);

        assert(harness.getPriceAtTickOver(tick) <= price);
        assertEq(harness.getTickAtPriceOver(priceResult), tick);
    }

    function test_getPriceAtTickOverAndUnder(int24 tick) public {
        if (tick < PriceTickMath.MIN_PRICE_TICK || tick > PriceTickMath.MAX_PRICE_TICK) {
            vm.expectRevert(PriceTickMath.PriceTickMath__getPriceAtTickOver_invalidPriceTick.selector);
        }
        uint256 priceX128Over = PriceTickMath.getPriceAtTickOver(tick);
        uint256 priceX128Under = PriceTickMath.getPriceAtTickUnder(tick);
        // Check that that priceX128Over is always no smaller than priceX128Under
        assertTrue(priceX128Over >= priceX128Under);
    }

    function test_uniqueTickValues() public {
        uint256 priceMin = PriceTickMath.getPriceAtTickOver(PriceTickMath.MIN_PRICE_TICK);
        console.log('MIN_PRICE: ', priceMin);

        uint256 priceMax = PriceTickMath.getPriceAtTickOver(PriceTickMath.MAX_PRICE_TICK);
        console.log('MAX_PRICE: ', priceMax);

        int24 startTick = 600_000;

        uint256 priceCache;
        uint256 price;

        for (int24 tick = startTick; tick <= PriceTickMath.MAX_PRICE_TICK; ) {
            price = harness.getPriceAtTickOver(tick);
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
            price = harness.getPriceAtTickOver(tick);
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
