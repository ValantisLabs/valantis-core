// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

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
enum Lock {
    WITHDRAWAL, // Bit 0
    DEPOSIT, // Bit 1
    SWAP // Bit 2
}

abstract contract UniversalPoolReentrancyGuard {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error UniversalPoolReentrancyGuard__reentrant();
    error UniversalPoolReentrancyGuard___setLockValue();
    error UniversalPoolReentrancyGuard___initializeLock();

    /************************************************
     *  CONSTANTS
     ***********************************************/
    /**
        @notice Indicates that a lock is free to be taken
     */
    uint8 internal constant _NOT_ENTERED = 0;
    /**
        @notice Indicates that a lock is taken, thus the function is locked.
     */
    uint8 internal constant _ENTERED = 1;

    /************************************************
     *  STORAGE
     ***********************************************/
    /**
        @notice Bitmap where the first 3 bits represent a lock -
        Bit 0: Withdraw Lock
        Bit 1: Deposit Lock
        Bit 2: Swap Lock
        Bit 7: Bit is permanently set to 1, at the time of initialization.

        @dev A bit value of 1 indicates that the lock is taken,
            and a value of 0 indicates that the lock is free. 
            Note: Bit 7 is permanently set to 1 at the time of pool initialization.
     */
    uint8 internal _poolLocks;
    /************************************************
     *  MODIFIERS
     ***********************************************/
    /**
        @notice Modifier to lock a function with a particular lock.
        @param lockNum The lock to use. Has to be from one of the locks in PoolLocks.
     */
    modifier nonReentrant(Lock lockNum) {
        _lock(lockNum);
        _;
        _unlock(lockNum);
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
        @param lockNum The lock to use. Has to be from one of the locks in PoolLocks.
     */
    function _lock(Lock lockNum) internal {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        if (_getLockValue(lockNum) != _NOT_ENTERED) {
            revert UniversalPoolReentrancyGuard__reentrant();
        }

        // Any calls to nonReentrant after this point will fail
        _setLockValue(lockNum, _ENTERED);
    }

    /**
        @notice Frees the lock.
        @param lockNum The lock to use. Has to be from one of the locks in PoolLocks.
     */
    function _unlock(Lock lockNum) internal {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _setLockValue(lockNum, _NOT_ENTERED);
    }

    function _getLockValue(Lock lockNum) internal view returns (uint8) {
        // Until the pool lock is initialized, all locks are taken.
        if (!_isLockInitialized()) {
            return _ENTERED;
        } else {
            return ((_poolLocks >> uint8(lockNum)) & uint8(1));
        }
    }

    /**
        @notice Should never be called directly
     */
    function _setLockValue(Lock lockNum, uint8 value) private {
        if (value != _getLockValue(lockNum) || value > 2) {
            // Flip Bit
            _poolLocks ^= (uint8(1) << uint8(lockNum));
        } else {
            revert UniversalPoolReentrancyGuard___setLockValue();
        }
    }

    /**
        @notice Initializes the pool locks.
        @dev Should only be called once, at the time of pool iniitalization.
     */
    function _initializeLock() internal {
        if (_poolLocks == 0) {
            _poolLocks = uint8(1 << 7);
        } else {
            revert UniversalPoolReentrancyGuard___initializeLock();
        }
    }

    function _isLockInitialized() internal view returns (bool) {
        return _poolLocks >> 7 == 1;
    }
}
