// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IUniversalOracle {
    function pool() external view returns (address);

    function writeOracleUpdate(
        bool isZeroToOne,
        uint256 amountInUsed,
        uint256 fee,
        uint256 amountOut,
        int24 spotPriceTick,
        int24 spotPriceTickStart
    ) external;
}
