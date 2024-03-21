// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IUniversalOracle {
    /**
        @notice Returns the address of the pool associated with the oracle.
        @return pool The address of the pool.
     */
    function pool() external view returns (address);

    /**
        @notice Writes an update to the oracle after a swap in the Universal Pool.
        @param isZeroToOne True if the swap is from token0 to token1, false otherwise.
        @param amountInUsed The amount of the tokenIn used for the swap.
        @param fee The fee amount.
        @param amountOut The amount of the tokenOut transferred to the user.
        @param spotPriceTick The spot price tick after the swap.
        @param spotPriceTickStart The spot price tick before the swap.
     */
    function writeOracleUpdate(
        bool isZeroToOne,
        uint256 amountInUsed,
        uint256 fee,
        uint256 amountOut,
        int24 spotPriceTick,
        int24 spotPriceTickStart
    ) external;
}
