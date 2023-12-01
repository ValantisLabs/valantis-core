// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

/**
    @title Minimal interface for Sovereign Pool's custom vault.
    @dev Sovereign Pools can choose to store their token0 and token1
         reserves in this contract.
         Sovereign Vault allows LPs to define where funds should be stored
         on deposits, withdrawals and swaps. Examples:
         - A custom LP vault which can provide liquidity to multiple pools on request.
         - A singleton contract.
         - Any external protocol that provides liquidity to incoming swaps on request.
         Moreover, it supports any number of tokens.
    @dev This is meant to be a minimal interface, containing only the functions
         required for Sovereign Pools to interact with.
 */
interface ISovereignVaultMinimal {
    /**
        @notice Returns array of tokens which can be swapped against for a given Sovereign Pool.
        @param _pool Sovereign Pool to query tokens for.
     */
    function getTokensForPool(address _pool) external view returns (address[] memory);

    /**
        @notice Returns reserve amounts available for a given Sovereign Pool.
        @param _pool Sovereign Pool to query token reserves for.
        @param _tokens Token addresses to query reserves for.
        @dev The full array of available tokens can be retrieved by calling `getTokensForPool` beforehand.
     */
    function getReservesForPool(address _pool, address[] calldata _tokens) external view returns (uint256[] memory);

    /**
        @notice Allows pool to attempt to claim due amount of `poolManager` fees.
        @dev Only callable by a Sovereign Pool. 
        @dev This is required, since on every swap, input token amounts are transferred
             from user into `sovereignVault`, to save on gas. Hence manager fees
             can only be claimed via this separate call.
        @param _feePoolManager0 Amount of token0 due to `poolManager`.
        @param _feePoolManager1 Amount of token1 due to `poolManager`.
     */
    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external;
}
