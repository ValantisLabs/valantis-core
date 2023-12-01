// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface ISovereignOracle {
    function pool() external view returns (address);

    function writeOracleUpdate(bool isZeroToOne, uint256 amountInMinusFee, uint256 fee, uint256 amountOut) external;
}
