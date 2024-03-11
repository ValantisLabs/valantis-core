// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

enum Lock {
    WITHDRAWAL,
    DEPOSIT,
    SWAP,
    SPOT_PRICE_TICK
}

struct PoolLocks {
    /**
        @notice Locks all functions that require any withdrawal of funds from the pool
                This involves the following functions -
                * withdrawLiquidity
                * claimProtocolFees
                * claimPoolManagerFees
     */
    uint8 withdrawals;
    /**
        @notice Only locks the deposit function
    */
    // @audit is this lock needed? Is it safe to always keep deposits open.
    uint8 deposit;
    /**
        @notice Only locks the swap function
    */
    uint8 swap;
    /**
        @notice Only locks the spotPriceTick function
    */
    uint8 spotPriceTick;
}
