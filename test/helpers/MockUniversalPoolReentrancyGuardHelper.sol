// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { UniversalPoolReentrancyGuard } from 'src/utils/UniversalPoolReentrancyGuard.sol';

contract MockUniversalPoolReentrancyGuardHelper is UniversalPoolReentrancyGuard {
    bool public depositToggle;
    bool public withdrawToggle;
    bool public swapToggle;
    bool public globalFunctionToggle;

    function deposit() public nonReentrant(UniversalPoolReentrancyGuard.Lock.DEPOSIT) {
        depositToggle = !depositToggle;
    }

    function withdraw() public nonReentrant(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL) {
        withdrawToggle = !withdrawToggle;
    }

    function swap() public nonReentrant(UniversalPoolReentrancyGuard.Lock.SWAP) {
        swapToggle = !swapToggle;
    }

    function globalFunction() public nonReentrantGlobal {
        globalFunctionToggle = !globalFunctionToggle;
    }

    function initialize() public {
        _initializeLock();
    }

    function lock(Lock _lockNum) public {
        _lock(_lockNum);
    }

    function unlock(Lock _lockNum) public {
        _unlock(_lockNum);
    }

    function poolLocks() public view returns (uint8) {
        return _poolLocks;
    }

    function isInitialized() public view returns (bool) {
        return _isLockInitialized();
    }

    function getLockValue(Lock _lockNum) public view returns (uint8) {
        return _getLockValue(_lockNum);
    }
}
