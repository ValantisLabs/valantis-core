// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { console } from 'forge-std/console.sol';
import { Math } from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { UniversalPool } from 'src/pools/UniversalPool.sol';
import { PoolLocks, Lock } from 'src/pools/structs/ReentrancyGuardStructs.sol';
import {
    Slot0,
    ALMPosition,
    ALMStatus,
    UnderlyingALMQuote,
    SwapCache,
    InternalSwapALMState,
    PoolState,
    SwapParams
} from 'src/pools/structs/UniversalPoolStructs.sol';
import { StateLib } from 'src/pools/libraries/StateLib.sol';
import { ALMLib } from 'src/pools/libraries/ALMLib.sol';
import { UniversalPoolReentrancyGuard } from 'src/utils/UniversalPoolReentrancyGuard.sol';
import { PriceTickMath } from 'src/libraries/PriceTickMath.sol';
import { EnumerableALMMap } from 'src/libraries/EnumerableALMMap.sol';
import { IFlashBorrower } from 'src/pools/interfaces/IFlashBorrower.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';
import { ALMLiquidityQuotePoolInputs, ALMReserves, ALMLiquidityQuote } from 'src/ALM/structs/UniversalALMStructs.sol';
import { SwapFeeModuleData } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { IUniversalOracle } from 'src/oracles/interfaces/IUniversalOracle.sol';

import { UniversalPoolBase } from 'test/base/UniversalPoolBase.t.sol';
import { MockUniversalALMHelper } from 'test/helpers/MockUniversalALMHelper.sol';

interface IUniversalSwapFeeModule {
    function callbackOnSwapEnd(
        uint256 _effectiveFee,
        int24 _spotPriceTick,
        uint256 _amountInUsed,
        uint256 _amountOut,
        SwapFeeModuleData memory _swapFeeModuleData
    ) external;
}

contract UniversalPoolConcrete is UniversalPoolBase {
    /************************************************
     *  Test Constructor
     ***********************************************/

    function test_defaultConstructor() public {
        // check pool manager is set correctly
        assertEq(pool.state().poolManager, POOL_MANAGER);

        // check token addresses
        assertEq(pool.token0(), address(token0));
        assertEq(pool.token1(), address(token1));

        // check protocol factory is set correctly
        assertEq(pool.protocolFactory(), address(protocolFactory));

        // check default fee swap bips is 0
        assertEq(pool.defaultSwapFeeBips(), 0);

        PoolLocks memory poolLockStatus = pool.getPoolLockStatus();

        assertEq(poolLockStatus.withdrawals.value, 0);
        assertEq(poolLockStatus.deposit.value, 0);
        assertEq(poolLockStatus.swap.value, 0);

        assertEq(pool.getALMPositionsList().length, 0);
    }

    function test_customConstructorArgs() public {
        vm.expectRevert(UniversalPool.UniversalPool__invalidTokenAddresses.selector);

        // should error when both tokens are same
        deployUniversalPool(protocolFactory, address(token0), address(token0), POOL_MANAGER, 0);

        address newPoolManager = _randomUser();

        // check with different pool manager
        pool = deployUniversalPool(protocolFactory, address(token0), address(token1), newPoolManager, 0);

        assertEq(pool.state().poolManager, newPoolManager);

        // check with non zero default swap fee bips
        pool = deployUniversalPool(protocolFactory, address(token0), address(token1), POOL_MANAGER, 1e3);

        assertEq(pool.defaultSwapFeeBips(), 1e3);

        // check with default swap fee bips greater than max allowed
        pool = deployUniversalPool(protocolFactory, address(token0), address(token1), POOL_MANAGER, 1e5);

        assertEq(pool.defaultSwapFeeBips(), 1e4);
    }

    /************************************************
     *  Test Permissioned functions
     ***********************************************/

    function test_initializeTick() public {
        PoolState memory defaultState = _defaultPoolState();

        // check non pool manager can't call
        vm.expectRevert(UniversalPool.UniversalPool__onlyPoolManager.selector);
        pool.initializeTick(0, defaultState);

        // check tick out of range of price tick is not allowed
        int24 tick = PriceTickMath.MIN_PRICE_TICK - 1;

        vm.prank(POOL_MANAGER);
        vm.expectRevert(UniversalPool.UniversalPool__initializeTick.selector);
        pool.initializeTick(tick, defaultState);

        tick = PriceTickMath.MAX_PRICE_TICK + 1;

        vm.prank(POOL_MANAGER);
        vm.expectRevert(UniversalPool.UniversalPool__initializeTick.selector);
        pool.initializeTick(tick, defaultState);

        tick = 1;
        defaultState.swapFeeModule = makeAddr('SWAP_FEE_MODULE');
        defaultState.universalOracle = makeAddr('ORACLE');
        defaultState.poolManagerFeeBips = 100;

        vm.prank(POOL_MANAGER);
        pool.initializeTick(tick, defaultState);

        // check initialised pool is not allowed
        vm.prank(POOL_MANAGER);
        vm.expectRevert(UniversalPool.UniversalPool__initializeTick.selector);
        pool.initializeTick(tick, defaultState);

        // check values are initialised correctly
        PoolState memory poolState = pool.state();
        assertEq(poolState.swapFeeModule, defaultState.swapFeeModule);
        assertEq(poolState.universalOracle, defaultState.universalOracle);
        assertEq(poolState.poolManagerFeeBips, defaultState.poolManagerFeeBips);

        _lockPool(2);

        vm.expectRevert(UniversalPool.UniversalPool__spotPriceTick_spotPriceTickLocked.selector);
        pool.spotPriceTick();

        _unlockPool(2);

        assertEq(pool.spotPriceTick(), tick);

        // check locks are unlocked
        PoolLocks memory poolLockStatus = pool.getPoolLockStatus();

        assertEq(poolLockStatus.withdrawals.value, 1);
        assertEq(poolLockStatus.deposit.value, 1);
        assertEq(poolLockStatus.swap.value, 1);
    }

    function test_setGauge() public {
        address GAUGE = makeAddr('GAUGE');

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.setGauge(GAUGE);

        _initializePool();
        // check address other than protocol factory can not call setGauge
        vm.expectRevert(UniversalPool.UniversalPool__onlyProtocolFactory.selector);

        pool.setGauge(GAUGE);

        // can not be called with zero address as gauge address
        vm.prank(address(protocolFactory));
        vm.expectRevert(UniversalPool.UniversalPool__setGauge_invalidAddress.selector);

        pool.setGauge(ZERO_ADDRESS);

        vm.prank(address(protocolFactory));
        pool.setGauge(GAUGE);

        assertEq(pool.state().gauge, GAUGE);

        // can not be called once gauge is set
        vm.prank(address(protocolFactory));
        vm.expectRevert(UniversalPool.UniversalPool__setGauge_gaugeAlreadySet.selector);
        pool.setGauge(GAUGE);
    }

    function test_claimProtocolFees() public {
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.claimProtocolFees();

        _initializePool();

        address GAUGE = makeAddr('GAUGE');

        vm.prank(address(protocolFactory));
        pool.setGauge(GAUGE);

        _setProtocolFees(1e18, 2e18);

        _setupBalanceForUser(address(pool), address(token0), 100e18);
        _setupBalanceForUser(address(pool), address(token1), 100e18);

        // check only gauge can call it

        vm.expectRevert(UniversalPool.UniversalPool__onlyGauge.selector);
        pool.claimProtocolFees();

        vm.prank(GAUGE);
        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, GAUGE, 1e18));
        vm.expectCall(address(token1), abi.encodeWithSelector(IERC20.transfer.selector, GAUGE, 2e18));

        (uint256 amountClaimed0, uint256 amountClaimed1) = pool.claimProtocolFees();

        assertEq(amountClaimed0, 1e18);
        assertEq(amountClaimed1, 2e18);

        assertEq(pool.state().feeProtocol0, 0);
        assertEq(pool.state().feeProtocol1, 0);

        assertEq(token0.balanceOf(address(pool)), 100e18 - amountClaimed0);
        assertEq(token1.balanceOf(address(pool)), 100e18 - amountClaimed1);
    }

    function test_setPoolState() public {
        PoolState memory defaultState = _defaultPoolState();

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.setPoolState(defaultState);

        _initializePool();

        // check non pool manager can't call this function
        vm.expectRevert(UniversalPool.UniversalPool__onlyPoolManager.selector);
        pool.setPoolState(defaultState);

        defaultState.swapFeeModule = makeAddr('SWAP_FEE_MODULE');
        defaultState.universalOracle = makeAddr('ORACLE');
        defaultState.poolManager = _randomUser();
        defaultState.poolManagerFeeBips = 100;
        uint256 snapshot = vm.snapshot();
        vm.prank(POOL_MANAGER);
        pool.setPoolState(defaultState);

        PoolState memory poolState = pool.state();
        assertEq(poolState.swapFeeModule, defaultState.swapFeeModule);
        assertEq(poolState.universalOracle, defaultState.universalOracle);
        assertEq(poolState.poolManagerFeeBips, defaultState.poolManagerFeeBips);
        assertEq(poolState.poolManager, defaultState.poolManager);

        vm.revertTo(snapshot);

        defaultState.poolManager = ZERO_ADDRESS;
        _setPoolManagerFees(10e18, 20e18);

        _setupBalanceForUser(address(pool), address(token0), 10e18);
        _setupBalanceForUser(address(pool), address(token1), 20e18);
        vm.prank(POOL_MANAGER);

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, POOL_MANAGER, 10e18));
        vm.expectCall(address(token1), abi.encodeWithSelector(IERC20.transfer.selector, POOL_MANAGER, 20e18));

        pool.setPoolState(defaultState);
    }

    function test_claimPoolManagerFees() public {
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.claimPoolManagerFees(0, 0);

        _initializePool();

        // check non pool manager can't call this function
        vm.expectRevert(UniversalPool.UniversalPool__onlyPoolManager.selector);
        pool.claimPoolManagerFees(0, 0);

        vm.prank(POOL_MANAGER);
        vm.expectRevert(StateLib.StateLib__claimPoolManagerFees_invalidProtocolFee.selector);
        pool.claimPoolManagerFees(1e4 + 1, 1e4 + 1);

        _setPoolManagerFees(1e18, 2e18);
        uint256 fee0Bips = 100;
        uint256 fee1Bips = 100;
        uint256 fee0 = Math.mulDiv(fee0Bips, 1e18, 1e4);
        uint256 fee1 = Math.mulDiv(fee1Bips, 2e18, 1e4);

        _setupBalanceForUser(address(pool), address(token0), 100e18);
        _setupBalanceForUser(address(pool), address(token1), 100e18);

        vm.prank(POOL_MANAGER);
        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, POOL_MANAGER, 1e18 - fee0));
        vm.expectCall(address(token1), abi.encodeWithSelector(IERC20.transfer.selector, POOL_MANAGER, 2e18 - fee1));

        pool.claimPoolManagerFees(fee0Bips, fee1Bips);

        PoolState memory poolState = pool.state();

        assertEq(poolState.feePoolManager0, 0);
        assertEq(poolState.feePoolManager1, 0);
        assertEq(poolState.feeProtocol0, fee0);
        assertEq(poolState.feeProtocol1, fee1);
    }

    function test_addALMPosition() public {
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.claimPoolManagerFees(0, 0);

        _initializePool();

        assertEq(pool.getALMPositionsList().length, 0);

        address alm = MockUniversalALMHelper.deployMockALM(address(pool), true);

        vm.expectRevert(UniversalPool.UniversalPool__onlyPoolManager.selector);
        pool.addALMPosition(true, true, true, 100, alm);

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(true, true, false, 100, alm);

        assertEq(pool.getALMPositionsList().length, 1);

        alm = MockUniversalALMHelper.deployMockALM(address(pool), false);

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, alm);

        assertEq(pool.getALMPositionsList().length, 2);
    }

    function test_removeALMPosition() public {
        test_addALMPosition();

        ALMPosition[] memory almPositions = pool.getALMPositionsList();

        vm.expectRevert(UniversalPool.UniversalPool__onlyPoolManager.selector);
        pool.removeALMPosition(almPositions[0].slot0.almAddress);

        vm.prank(POOL_MANAGER);
        pool.removeALMPosition(almPositions[0].slot0.almAddress);

        assertEq(pool.getALMPositionsList().length, 1);
        address almRemoved = almPositions[0].slot0.almAddress;

        (ALMStatus status, ) = pool.getALMPositionAtAddress(almRemoved);

        assertEq(uint8(ALMStatus.REMOVED), uint8(status));
    }

    function test_setMetaALMFeeShare() public {
        test_addALMPosition();

        ALMPosition[] memory almPositions = pool.getALMPositionsList();

        vm.expectRevert(UniversalPool.UniversalPool__onlyPoolManager.selector);
        pool.setMetaALMFeeShare(almPositions[0].slot0.almAddress, 200);

        vm.prank(POOL_MANAGER);
        vm.expectRevert(EnumerableALMMap.EnumerableALMMap__setMetaALMFeeShare_notMetaALM.selector);
        pool.setMetaALMFeeShare(almPositions[0].slot0.almAddress, 200);

        vm.prank(POOL_MANAGER);
        pool.setMetaALMFeeShare(almPositions[1].slot0.almAddress, 200);

        (, ALMPosition memory position) = pool.getALMPositionAtAddress(almPositions[1].slot0.almAddress);

        assertEq(position.slot0.metaALMFeeShare, 200);
    }

    /************************************************
     *  Test ALM functions
     ***********************************************/

    function test_deposit() public {
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.depositLiquidity(0, 0, new bytes(0));

        _initializePool();

        // check not allowed when pool lock is locked for deposit
        _lockPool(1);

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.depositLiquidity(0, 0, new bytes(0));

        _unlockPool(1);
        // check non alm can't call this function
        vm.expectRevert(UniversalPool.UniversalPool__onlyActiveALM.selector);
        pool.depositLiquidity(0, 0, new bytes(0));

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, address(this));

        // zero amounts
        vm.expectRevert(ALMLib.ALMLib__depositLiquidity_zeroAmounts.selector);
        pool.depositLiquidity(0, 0, new bytes(0));

        vm.expectRevert(ALMLib.ALMLib__depositLiquidity_insufficientTokenAmount.selector);
        pool.depositLiquidity(1e18, 2e18, abi.encode(1e18 - 1, 2e18 - 1));

        pool.depositLiquidity(1e18, 2e18, abi.encode(1e18, 2e18));

        (, ALMPosition memory position) = pool.getALMPositionAtAddress(address(this));

        assertEq(position.reserve0, 1e18);
        assertEq(position.reserve1, 2e18);

        ALMReserves memory almReserves = pool.getALMReserves(address(this), true);

        assertEq(almReserves.tokenInReserves, 1e18);
        assertEq(almReserves.tokenOutReserves, 2e18);
    }

    function test_withdraw() public {
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.withdrawLiquidity(0, 0, address(this));

        _initializePool();

        address RECIPIENT = _randomUser();

        // check not allowed when pool lock is locked for deposit
        _lockPool(0);
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.withdrawLiquidity(0, 0, RECIPIENT);

        _unlockPool(0);

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, address(this));

        pool.depositLiquidity(1e18, 2e18, abi.encode(1e18, 2e18));

        _unlockPool(0);

        vm.expectRevert(ALMLib.ALMLib__withdrawLiquidity_insufficientReserves.selector);
        pool.withdrawLiquidity(1e18 + 1, 2e18 + 1, RECIPIENT);

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 1e18));
        vm.expectCall(address(token1), abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 2e18));
        pool.withdrawLiquidity(1e18, 2e18, RECIPIENT);

        (, ALMPosition memory position) = pool.getALMPositionAtAddress(address(this));
        assertEq(position.reserve0, 0);
        assertEq(position.reserve1, 0);
    }

    /************************************************
     *  Test Public functions
     ***********************************************/

    function test_flashloan() public {
        IFlashBorrower FLASH_BORROWER = IFlashBorrower(address(this));

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.flashLoan(true, FLASH_BORROWER, 0, new bytes(0));

        _initializePool();

        address initiator = makeAddr('INITIATOR');

        bytes memory data = abi.encode(0, initiator);

        uint256 amount = 10e18;

        _setupBalanceForUser(address(pool), address(token0), amount * 2);

        // Check revert on incorrect callback hash.
        vm.expectRevert(IValantisPool.ValantisPool__flashloan_callbackFailed.selector);
        vm.prank(initiator);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // Check revert on insufficient allowance.
        vm.expectRevert('ERC20: insufficient allowance');
        data = abi.encode(1, initiator);
        vm.prank(initiator);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // Check revert on amount decrease post flashloan.
        data = abi.encode(3, address(this));
        vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanNotRepaid.selector);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // Check happy path works fine.
        data = abi.encode(2, initiator);
        vm.prank(initiator);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);
    }

    function test_swap() public {
        address RECIPIENT = _randomUser();

        SwapParams memory swapParams;

        // check deadline
        vm.expectRevert(UniversalPool.UniversalPool__swap_expired.selector);
        pool.swap(swapParams);
        swapParams.deadline = block.timestamp;

        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.swap(swapParams);

        _initializePool();

        // locked withdrawal should also revert
        _lockPool(0);
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.swap(swapParams);

        _unlockPool(0);

        // locked swap should also revert
        _lockPool(2);
        vm.expectRevert(UniversalPoolReentrancyGuard.UniversalPoolReentrancyGuard__reentrant.selector);
        pool.swap(swapParams);

        _unlockPool(2);

        // check revert on zero amount in
        vm.expectRevert(UniversalPool.UniversalPool__swap_amountInCannotBeZero.selector);
        pool.swap(swapParams);

        swapParams.amountIn = 100e18;

        // check revert on recipient as zero address
        vm.expectRevert(UniversalPool.UniversalPool__swap_zeroAddressRecipient.selector);
        pool.swap(swapParams);

        swapParams.recipient = RECIPIENT;

        // check revert limit price tick less than min price tick
        swapParams.limitPriceTick = PriceTickMath.MIN_PRICE_TICK - 1;
        vm.expectRevert(UniversalPool.UniversalPool__swap_invalidLimitPriceTick.selector);
        pool.swap(swapParams);

        // check revert limit price tick more than max price tick
        swapParams.limitPriceTick = PriceTickMath.MAX_PRICE_TICK + 1;
        vm.expectRevert(UniversalPool.UniversalPool__swap_invalidLimitPriceTick.selector);
        pool.swap(swapParams);

        // swap direction is 1->0, so limit price tick should be greater than equal 0
        swapParams.limitPriceTick = -1;
        vm.expectRevert(UniversalPool.UniversalPool__swap_invalidLimitPriceTick.selector);
        pool.swap(swapParams);

        swapParams.limitPriceTick = PriceTickMath.MAX_PRICE_TICK;

        // check revert on no active alm
        vm.expectRevert(UniversalPool.UniversalPool__swap_noActiveALMPositions.selector);
        pool.swap(swapParams);

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, address(this));

        // check revert on invalid external context length
        vm.expectRevert(UniversalPool.UniversalPool__swap_invalidExternalContextArrayLength.selector);
        pool.swap(swapParams);

        swapParams.externalContext = new bytes[](1);

        // check revert on invalid alm ordering length
        vm.expectRevert(UniversalPool.UniversalPool__swap_invalidALMOrderingData.selector);
        pool.swap(swapParams);

        swapParams.almOrdering = new uint8[](1);

        swapParams.almOrdering[0] = 12;

        // check revert on invalid alm ordering index of alm
        vm.expectRevert(UniversalPool.UniversalPool__swap_invalidALMOrderingData.selector);
        pool.swap(swapParams);

        swapParams.almOrdering[0] = 0;

        // liquidity quote at tick 1
        ALMLiquidityQuote memory quote = ALMLiquidityQuote(10e18, 1, new bytes(0));
        // setup quote at tick 0
        quote = ALMLiquidityQuote(30e18, 1, abi.encode(quote));

        swapParams.externalContext[0] = abi.encode(true, true, 50e18, 0, quote);

        swapParams.amountOutMin = 100e18;

        vm.expectRevert(UniversalPool.UniversalPool__swap_minAmountOutNotFilled.selector);
        pool.swap(swapParams);

        swapParams.amountOutMin = 0;

        quote = ALMLiquidityQuote(0, 268711, new bytes(0));
        quote = ALMLiquidityQuote(0, 268711, abi.encode(quote));

        swapParams.amountIn = 1;
        swapParams.externalContext[0] = abi.encode(true, true, 50e18, 0, quote);

        vm.expectRevert(UniversalPool.UniversalPool__swap_zeroAmountOut.selector);
        pool.swap(swapParams);

        quote = ALMLiquidityQuote(10e18, 1, new bytes(0));
        quote = ALMLiquidityQuote(30e18, 1, abi.encode(quote));
        swapParams.externalContext[0] = abi.encode(true, true, 50e18, 0, quote);

        swapParams.amountIn = 100e18;

        uint256 amountInExpected = 30e18 + PriceTickMath.getTokenInAmount(false, 10e18, 1);

        uint256 snapshot = vm.snapshot();

        // without call back swap
        _setupBalanceForUser(address(this), address(token1), 100e18);

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 40e18));

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountOut, 40e18);
        assertEq(amountInUsed, amountInExpected);

        (, ALMPosition memory almPosition) = pool.getALMPositionAtAddress(address(this));

        assertEq(almPosition.reserve0, 50e18 - amountOut);
        assertEq(almPosition.reserve1, amountInExpected);

        vm.revertTo(snapshot);

        // with call back
        swapParams.isSwapCallback = true;
        swapParams.swapCallbackContext = abi.encode(amountInExpected - 1);

        vm.expectRevert(UniversalPool.UniversalPool__swap_insufficientAmountIn.selector);
        pool.swap(swapParams);

        swapParams.swapCallbackContext = abi.encode(amountInExpected + 1);

        vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, RECIPIENT, 40e18));
        (amountInUsed, amountOut) = pool.swap(swapParams);

        assertEq(amountOut, 40e18);
        assertEq(amountInUsed, amountInExpected);

        (, almPosition) = pool.getALMPositionAtAddress(address(this));

        assertEq(almPosition.reserve0, 50e18 - amountOut);
        assertEq(almPosition.reserve1, amountInExpected);
    }

    function test_swap_swapFeeModule() public {
        _initializePool();

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, address(this));

        address RECIPIENT = _randomUser();

        SwapParams memory swapParams;
        swapParams.isZeroToOne = true;
        swapParams.limitPriceTick = -2;
        swapParams.deadline = block.timestamp;
        swapParams.amountIn = 100e18;
        swapParams.recipient = RECIPIENT;
        swapParams.externalContext = new bytes[](1);
        swapParams.almOrdering = new uint8[](1);
        swapParams.almOrdering[0] = 0;

        // liquidity quote at tick -1
        ALMLiquidityQuote memory quote = ALMLiquidityQuote(10e18, -1, new bytes(0));
        // setup quote at tick 0
        quote = ALMLiquidityQuote(30e18, -1, abi.encode(quote));

        swapParams.externalContext[0] = abi.encode(true, true, 0, 50e18, quote);

        // set swap fee module
        PoolState memory poolState = pool.state();

        poolState.swapFeeModule = address(this);

        vm.prank(POOL_MANAGER);
        pool.setPoolState(poolState);

        // check revert on excessive fee
        swapParams.swapFeeModuleContext = abi.encode(SwapFeeModuleData(1e4 + 1, new bytes(0)));
        vm.expectRevert(UniversalPool.UniversalPool__swap_excessiveSwapFee.selector);
        pool.swap(swapParams);

        uint256 amountInFilled = 30e18 + PriceTickMath.getTokenInAmount(true, 10e18, -1);

        uint256 amountInExpected = _getAmountInUsedExpected(amountInFilled, 100);

        _setupBalanceForUser(address(this), address(token0), 100e18);

        uint256 snapshot = vm.snapshot();
        // without swap fee module callback
        swapParams.swapFeeModuleContext = abi.encode(SwapFeeModuleData(100, new bytes(0)));
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountInExpected, amountInUsed);

        vm.revertTo(snapshot);

        swapParams.swapFeeModuleContext = abi.encode(SwapFeeModuleData(100, new bytes(1337)));

        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                IUniversalSwapFeeModule.callbackOnSwapEnd.selector,
                Math.mulDiv(amountInFilled, 100, 1e4),
                -1,
                amountInExpected,
                40e18,
                SwapFeeModuleData(100, new bytes(1337))
            )
        );

        (amountInUsed, amountOut) = pool.swap(swapParams);

        assertEq(amountInExpected, amountInUsed);
        assertEq(40e18, amountOut);
    }

    function test_swap_universalOracle() public {
        _initializePool();

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, address(this));

        address RECIPIENT = _randomUser();

        SwapParams memory swapParams;
        swapParams.isZeroToOne = true;
        swapParams.limitPriceTick = -2;
        swapParams.deadline = block.timestamp;
        swapParams.amountIn = 100e18;
        swapParams.recipient = RECIPIENT;
        swapParams.externalContext = new bytes[](1);
        swapParams.almOrdering = new uint8[](1);
        swapParams.almOrdering[0] = 0;

        // liquidity quote at tick -1
        ALMLiquidityQuote memory quote = ALMLiquidityQuote(10e18, -1, new bytes(0));
        // setup quote at tick 0
        quote = ALMLiquidityQuote(30e18, -1, abi.encode(quote));

        swapParams.externalContext[0] = abi.encode(true, true, 0, 50e18, quote);

        // set universal oracle
        PoolState memory poolState = pool.state();

        poolState.universalOracle = address(this);

        vm.prank(POOL_MANAGER);
        pool.setPoolState(poolState);

        uint256 amountInExpected = 30e18 + PriceTickMath.getTokenInAmount(true, 10e18, -1);

        _setupBalanceForUser(address(this), address(token0), 100e18);

        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                IUniversalOracle.writeOracleUpdate.selector,
                true,
                amountInExpected,
                0,
                40e18,
                -1,
                -2
            )
        );

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountInExpected, amountInUsed);
        assertEq(40e18, amountOut);
    }

    function test_swap_multipleALM() public {
        _initializePool();

        // 3 alms, 1 meta alm and 2 base alm
        address[] memory alms = new address[](3);

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, address(this));

        address alm = MockUniversalALMHelper.deployMockALM(address(pool), false);
        alms[0] = address(this);
        alms[1] = alm;

        alm = MockUniversalALMHelper.deployMockALM(address(pool), true);
        alms[2] = alm;

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, true, true, 0, alms[1]);

        vm.prank(POOL_MANAGER);
        pool.addALMPosition(true, true, false, 100, alms[2]);

        // alms[1] and alms[2] liquidity, alm[0] will be jit
        _setupBalanceForUser(address(this), address(token0), 200e18);
        _setupBalanceForUser(address(this), address(token1), 200e18);

        token0.approve(alms[1], 100e18);
        token1.approve(alms[1], 100e18);

        token0.approve(alms[2], 100e18);
        token1.approve(alms[2], 100e18);

        MockUniversalALMHelper.depositLiquidity(alms[1], 100e18, 100e18);
        MockUniversalALMHelper.depositLiquidity(alms[2], 100e18, 100e18);

        SwapParams memory swapParams;

        address RECIPIENT = _randomUser();

        swapParams.limitPriceTick = 2;
        swapParams.deadline = block.timestamp;
        swapParams.amountIn = 100e18;
        swapParams.recipient = RECIPIENT;
        swapParams.externalContext = new bytes[](3);
        swapParams.almOrdering = new uint8[](2);
        swapParams.almOrdering[0] = 0;
        swapParams.almOrdering[1] = 1;

        // for alm 1
        ALMLiquidityQuote memory quote = ALMLiquidityQuote(10e18, 1, new bytes(0));
        // setup quote at tick 0
        quote = ALMLiquidityQuote(15e18, 1, abi.encode(quote));

        swapParams.externalContext[0] = abi.encode(true, true, 50e18, 0, quote);

        // for alm 2
        quote = ALMLiquidityQuote(10e18, 2, new bytes(0));
        quote = ALMLiquidityQuote(15e18, 2, abi.encode(quote));
        // setup quote at tick 0
        quote = ALMLiquidityQuote(5e18, 1, abi.encode(quote));

        swapParams.externalContext[1] = abi.encode(true, false, 0, 0, quote);

        // for alm 3
        quote = ALMLiquidityQuote(5e18, 2, new bytes(0));
        quote = ALMLiquidityQuote(10e18, 2, abi.encode(quote));
        // setup quote at tick 0
        quote = ALMLiquidityQuote(15e18, 1, abi.encode(quote));

        swapParams.externalContext[2] = abi.encode(true, false, 0, 0, quote);

        _setupBalanceForUser(address(this), address(token1), 100e18);

        uint256 amountInExpected = 15e18 +
            5e18 +
            15e18 +
            PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 15e18, 1) +
            PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 10e18, 1) +
            PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 10e18, 1) +
            PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 5e18, 2) +
            PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 10e18, 2);

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountInExpected, amountInUsed);
        assertEq(85e18, amountOut);

        (, ALMPosition memory almPosition) = pool.getALMPositionAtAddress(alms[0]);

        assertEq(almPosition.reserve0, 50e18 - 25e18);
        assertEq(almPosition.reserve1, 15e18 + PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 10e18, 1));

        (, almPosition) = pool.getALMPositionAtAddress(alms[1]);

        assertEq(almPosition.reserve0, 100e18 - 30e18);
        assertEq(
            almPosition.reserve1,
            100e18 +
                5e18 +
                PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 15e18, 1) +
                PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 10e18, 2)
        );

        (, almPosition) = pool.getALMPositionAtAddress(alms[2]);

        assertEq(almPosition.reserve0, 100e18 - 30e18);
        assertEq(
            almPosition.reserve1,
            100e18 +
                15e18 +
                PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 10e18, 1) +
                PriceTickMath.getTokenInAmount(swapParams.isZeroToOne, 5e18, 2)
        );
    }

    function _initializePool() internal {
        vm.prank(POOL_MANAGER);
        pool.initializeTick(0, _defaultPoolState());
    }

    function _getAmountInUsedExpected(uint256 amountInFilled, uint256 feeBips) internal pure returns (uint256) {
        uint256 effectiveFee = Math.mulDiv(amountInFilled, feeBips, 1e4);
        return amountInFilled + effectiveFee;
    }
}
