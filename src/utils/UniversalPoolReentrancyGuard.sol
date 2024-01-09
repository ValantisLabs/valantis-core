// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { PoolLocks, Lock } from '../pools/structs/ReentrancyGuardStructs.sol';

/**
    @notice ReentrancyGuard for Valantis Universal Pool.
    Allows the pool to have precise control over which functions it wants to lock at a particular time.
    There are 3 pool locks in total - 
    * Deposit - Locks the depositLiquidity function
    * Withdrawals - Locks the withdrawLiquidity function
    * Swap - Locks the swap function and the spotPriceTick view function to prevent view-only reentrancy attacks.

    @dev There is also a global reentrancy gaurd modifier which all other functions can use to lock the pool completely.

    @dev All functions are locked by default ( value is 0 ), before initializeTick is called in the pool.

    Some components of this implementation have been taken from Open Zepelling's ReentrancyGuard contract.
    https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol
    

 */
abstract contract UniversalPoolReentrancyGuard {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error UniversalPoolReentrancyGuard__reentrant();

    /************************************************
     *  CONSTANTS
     ***********************************************/
    /**
        @notice Indicates that a lock is free to be taken
     */
    uint8 internal constant _NOT_ENTERED = 1;
    /**
        @notice Indicates that a lock is taken, thus the function is locked.
     */
    uint8 internal constant _ENTERED = 2;

    /************************************************
     *  STORAGE
     ***********************************************/

    PoolLocks internal _poolLocks;
    /************************************************
     *  MODIFIERS
     ***********************************************/
    /**
        @notice Modifier to lock a function with a particular lock.
        @param lockType The lock to use. Has to be from one of the locks in PoolLocks.
     */
    modifier nonReentrant(Lock storage lockType) {
        _lock(lockType);
        _;
        _unlock(lockType);
    }

    /**
        @notice Modifier to lock all functions in the pool.
     */
    modifier nonReentrantGlobal() {
        _lock(_poolLocks.withdrawals);
        _lock(_poolLocks.deposit);
        _lock(_poolLocks.swap);
        _;
        _unlock(_poolLocks.swap);
        _unlock(_poolLocks.deposit);
        _unlock(_poolLocks.withdrawals);
    }

    /************************************************
     *  FUNCTIONS
     ***********************************************/
    /**
        @notice Checks that the lock has not already been taken. If lock is free, then it is taken.
        @param lockType The lock to use. Has to be from one of the locks in PoolLocks.
     */
    function _lock(Lock storage lockType) internal {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        if (lockType.value != _NOT_ENTERED) {
            revert UniversalPoolReentrancyGuard__reentrant();
        }

        // Any calls to nonReentrant after this point will fail
        lockType.value = _ENTERED;
    }

    /**
        @notice Frees the lock.
        @param lockType The lock to use. Has to be from one of the locks in PoolLocks.
     */
    function _unlock(Lock storage lockType) internal {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        lockType.value = _NOT_ENTERED;
    }
}
