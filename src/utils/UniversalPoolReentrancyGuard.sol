// SPDX-License-Identifier: MIT
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
    modifier nonReentrant(Lock lockType) {
        _lock(lockType);
        _;
        _unlock(lockType);
    }

    /**
        @notice Modifier to lock all functions in the pool.
     */
    modifier nonReentrantGlobal() {
        _lock(Lock.WITHDRAWAL);
        _lock(Lock.DEPOSIT);
        _lock(Lock.SWAP);
        _;
        _unlock(Lock.SWAP);
        _unlock(Lock.DEPOSIT);
        _unlock(Lock.WITHDRAWAL);
    }

    /************************************************
     *  FUNCTIONS
     ***********************************************/
    /**
        @notice Checks that the lock has not already been taken. If lock is free, then it is taken.
        @param lockType The lock to use. Has to be from one of the locks in PoolLocks.
     */
    function _lock(Lock lockType) internal {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        if (_getLockValue(lockType) != _NOT_ENTERED) {
            revert UniversalPoolReentrancyGuard__reentrant();
        }

        // Any calls to nonReentrant after this point will fail
        _setLockValue(lockType, _ENTERED);
    }

    /**
        @notice Frees the lock.
        @param lockType The lock to use. Has to be from one of the locks in PoolLocks.
     */
    function _unlock(Lock lockType) internal {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _setLockValue(lockType, _NOT_ENTERED);
    }

    function _getLockValue(Lock lockType) private view returns (uint8) {
        if (Lock.WITHDRAWAL == lockType) {
            return _poolLocks.withdrawals;
        } else if (Lock.DEPOSIT == lockType) {
            return _poolLocks.deposit;
        } else if (Lock.SWAP == lockType) {
            return _poolLocks.swap;
        } else {
            return _poolLocks.spotPriceTick;
        }
    }

    function _setLockValue(Lock lockType, uint8 value) private {
        if (Lock.WITHDRAWAL == lockType) {
            _poolLocks.withdrawals = value;
        } else if (Lock.DEPOSIT == lockType) {
            _poolLocks.deposit = value;
        } else if (Lock.SWAP == lockType) {
            _poolLocks.swap = value;
        } else {
            _poolLocks.spotPriceTick = value;
        }
    }
}
