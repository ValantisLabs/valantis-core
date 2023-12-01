// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

struct Lock {
    uint8 value;
}

struct PoolLocks {
    /**
        @notice Locks all functions that require any withdrawal of funds from the pool
                This involves the following functions -
                * withdrawLiquidity
                * claimProtocolFees
                * claimPoolManagerFees
     */
    Lock withdrawals;
    /**
        @notice Only locks the deposit function
    */
    // @audit is this lock needed? Is it safe to always keep deposits open.
    Lock deposit;
    /**
        @notice Only locks the swap function
    */
    Lock swap;
}
