// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { console } from 'forge-std/console.sol';

import { UniversalPoolReentrancyGuard } from 'src/utils/UniversalPoolReentrancyGuard.sol';
import { MockUniversalPoolReentrancyGuardHelper } from 'test/helpers/MockUniversalPoolReentrancyGuardHelper.sol';

contract UniversalPoolReentrancyGuardTest is Test {
    MockUniversalPoolReentrancyGuardHelper pool;

    function setUp() public {
        pool = new MockUniversalPoolReentrancyGuardHelper();
        pool.initialize();
    }

    function test_initialize() public {
        pool = new MockUniversalPoolReentrancyGuardHelper();

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.deposit();
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.withdraw();
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.swap();
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.globalFunction();

        assertFalse(pool.isInitialized(), 'pool should not be initialized');
        pool.initialize();
        assertTrue(pool.isInitialized(), 'pool should  be initialized');

        pool.deposit();
        assertTrue(pool.depositToggle(), 'deposit should not revert');

        pool.withdraw();
        assertTrue(pool.withdrawToggle(), 'withdraw should not revert');

        pool.swap();
        assertTrue(pool.swapToggle(), 'swap should not revert');

        pool.globalFunction();
        assertTrue(pool.globalFunctionToggle(), 'globalFunction should not revert');

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard___initializeLock.selector);
        pool.initialize();
    }

    function test_lock() public {
        assertEq(pool.poolLocks(), 1 << 7, 'poolLock not initialized correctly');

        // Test Withdrawal Lock
        pool.lock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);
        // Check pool locks value
        assertEq(pool.poolLocks(), uint8(1 << 7) | uint8(1), 'withdrawal lock incorrect 1');
        assertEq(
            pool.getLockValue(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL),
            uint8(1),
            'withdrawal lock incorrect 2'
        );
        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.DEPOSIT), uint8(0), 'withdrawal lock incorrect 3');

        // Check reentrancy
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.lock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);

        // Test Deposit Lock
        pool.lock(UniversalPoolReentrancyGuard.Lock.DEPOSIT);

        // Check pool locks value
        assertEq(pool.poolLocks(), uint8(1 << 7) | uint8(1) | uint8(1 << 1), 'deposit lock incorrect');
        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL), uint8(1), 'deposit lock incorrect 1');
        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.DEPOSIT), uint8(1), 'deposit lock incorrect 2');

        // Check reentrancy
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.lock(UniversalPoolReentrancyGuard.Lock.DEPOSIT);
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.lock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);

        // Test Swap Lock
        pool.lock(UniversalPoolReentrancyGuard.Lock.SWAP);

        // Check pool locks value
        assertEq(pool.poolLocks(), uint8(1 << 7) | uint8(1) | uint8(1 << 1) | uint8(1 << 2), 'swaps lock incorrect');
        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL), uint8(1), 'swap lock incorrect 1');
        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.SWAP), uint8(1), 'swap lock incorrect 2');

        // Check reentrancy
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.lock(UniversalPoolReentrancyGuard.Lock.SWAP);
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.lock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);
    }

    function test_unlock() public {
        assertEq(pool.poolLocks(), 1 << 7, 'poolLock not initialized correctly');

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard___setLockValue.selector);
        pool.unlock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);

        // Test Withdrawal Unlock
        pool.lock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);
        pool.lock(UniversalPoolReentrancyGuard.Lock.DEPOSIT);
        pool.unlock(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL);

        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.WITHDRAWAL), uint8(0), 'unlock incorrect 1');
        assertEq(pool.getLockValue(UniversalPoolReentrancyGuard.Lock.DEPOSIT), uint8(1), 'unlock incorrect 2');
    }
}
