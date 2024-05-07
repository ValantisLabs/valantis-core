// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ISovereignOracle {
    /**
        @notice Returns the address of the pool associated with the oracle.
        @return pool The address of the pool.
     */
    function pool() external view returns (address);

    /**
        @notice Writes an update to the oracle after a swap in the Sovereign Pool.
        @param isZeroToOne True if the swap is from token0 to token1, false otherwise.
        @param amountInMinusFee The amount of the tokenIn used minus fees.
        @param fee The fee amount.
        @param amountOut The amount of the tokenOut transferred to the user.
     */
    function writeOracleUpdate(bool isZeroToOne, uint256 amountInMinusFee, uint256 fee, uint256 amountOut) external;
}
