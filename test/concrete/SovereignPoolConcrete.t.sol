// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { SovereignPool } from 'src/pools/SovereignPool.sol';
import { ALMLiquidityQuote } from 'src/ALM/structs/SovereignALMStructs.sol';
import {
    SovereignPoolConstructorArgs,
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData
} from 'src/pools/structs/SovereignPoolStructs.sol';
import { IFlashBorrower } from 'src/pools/interfaces/IFlashBorrower.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';
import { ISovereignSwapFeeModule, SwapFeeModuleData } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { ISovereignVaultMinimal } from 'src/pools/interfaces/ISovereignVaultMinimal.sol';
import { ISovereignALM } from 'src/ALM/interfaces/ISovereignALM.sol';
import { ISovereignOracle } from 'src/oracles/interfaces/ISovereignOracle.sol';

import { SovereignPoolBase } from 'test/base/SovereignPoolBase.t.sol';
import { MockSovereignVaultHelper } from 'test/helpers/MockSovereignVaultHelper.sol';

contract SovereignPoolConcreteTest is SovereignPoolBase {
    /************************************************
     *  Test Constructor
     ***********************************************/

    function test_defaultConstructorArgs() public {
        // Check pool manager is set perfectly.
        assertEq(pool.poolManager(), POOL_MANAGER);

        address[] memory tokens = pool.getTokens();

        // Check tokens are set correctly.
        assertEq(tokens[0], address(token0));
        assertEq(tokens[1], address(token1));

        // Check protocol factory is set correctly.
        assertEq(pool.protocolFactory(), address(protocolFactory));

        // Check initial reserves are zero.
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);

        // Check sovereign vault is address of pool.
        assertEq(pool.sovereignVault(), address(pool));

        assertEq(pool.isLocked(), false);
        assertEq(pool.swapFeeModuleUpdateTimestamp(), block.timestamp);
    }

    function test_customConstructorArgs() public {
        CustomConstructorArgsParams memory customParams = CustomConstructorArgsParams(
            TokenData(true, 9),
            TokenData(false, 0),
            makeAddr('SOVEREIGN_VAULT'),
            makeAddr('VERIFIER_MODULE'),
            16
        );

        SovereignPoolConstructorArgs memory args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        uint256 snapshot = vm.snapshot();

        // Check custom params for token0.
        assertEq(pool.isRebaseTokenPool(), true);
        assertEq(pool.isToken0Rebase(), true);
        assertEq(pool.token0AbsErrorTolerance(), customParams.token0Data.tokenAbsErrorTolerance);

        // Increase tolerance to more than MAX.
        args.token0AbsErrorTolerance = 100;

        vm.expectRevert(SovereignPool.SovereignPool__excessiveToken0AbsErrorTolerance.selector);

        this.deploySovereignPool(protocolFactory, args);

        vm.revertTo(snapshot);
        args.token0AbsErrorTolerance = customParams.token0Data.tokenAbsErrorTolerance;

        // Check vault and verifier module addresses.
        assertEq(pool.sovereignVault(), customParams.sovereignVault);
        assertEq(pool.verifierModule(), customParams.verifierModule);

        // Check defaulFeeBips passed.
        assertEq(pool.defaultSwapFeeBips(), customParams.defaultFeeBips);

        // Increase fee bips to be more than MAX_FEE_BIPS.
        args.defaultSwapFeeBips = 5e10;
        pool = this.deploySovereignPool(protocolFactory, args);
        assertEq(pool.defaultSwapFeeBips(), 10_000);

        assertEq(pool.swapFeeModuleUpdateTimestamp(), block.timestamp);
    }

    /************************************************
     *  Test Permissioned functions
     ***********************************************/

    function test_setPoolManager() public {
        address newManager = makeAddr('NEW_POOL_MANAGER');

        // Check error on unauthorized call to set pool manager.
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setPoolManager(newManager);

        vm.prank(POOL_MANAGER);

        pool.setPoolManager(newManager);

        assertEq(pool.poolManager(), newManager);

        _setPoolManagerFees(1e18, 1e18);
        _setupBalanceForUser(address(pool), address(token0), 2e18);
        _setupBalanceForUser(address(pool), address(token1), 2e18);

        vm.prank(newManager);
        pool.setPoolManager(ZERO_ADDRESS);

        _assertTokenBalance(token0, address(pool), 1e18);
        _assertTokenBalance(token1, address(pool), 1e18);

        _assertTokenBalance(token0, newManager, 1e18);
        _assertTokenBalance(token1, newManager, 1e18);
    }

    function test_setPoolManagerFeeBips() public {
        // Check error on unauthorized call to set pool manager.
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        uint256 poolManagerFeeBips = 1e10;

        pool.setPoolManagerFeeBips(poolManagerFeeBips);

        vm.startPrank(POOL_MANAGER);

        // Check error on trying to set more feeBips than allowed.
        vm.expectRevert(SovereignPool.SovereignPool__setPoolManagerFeeBips_excessivePoolManagerFee.selector);

        pool.setPoolManagerFeeBips(poolManagerFeeBips);

        poolManagerFeeBips = 5_000 - 1;

        pool.setPoolManagerFeeBips(poolManagerFeeBips);

        assertEq(pool.poolManagerFeeBips(), poolManagerFeeBips);
    }

    function test_setSovereignOracle() public {
        address oracle;

        // Check error on unauthorized call to set sovereign oracle.
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setSovereignOracle(oracle);

        vm.startPrank(POOL_MANAGER);

        vm.expectRevert(SovereignPool.SovereignPool__ZeroAddress.selector);
        pool.setSovereignOracle(oracle);

        oracle = makeAddr('ORACLE');

        pool.setSovereignOracle(oracle);

        assertEq(pool.sovereignOracleModule(), oracle);

        oracle = makeAddr('NEW_ORACLE');

        // Check error on trying to update sovereign oracle.
        vm.expectRevert(SovereignPool.SovereignPool__setSovereignOracle__sovereignOracleAlreadySet.selector);

        pool.setSovereignOracle(oracle);
    }

    function test_setGauge() public {
        address gauge = makeAddr('GAUGE');

        // Check error on unauthorized call to set gauge.
        vm.expectRevert(SovereignPool.SovereignPool__onlyProtocolFactory.selector);

        pool.setGauge(gauge);

        vm.startPrank(address(protocolFactory));

        pool.setGauge(gauge);

        assertEq(pool.gauge(), gauge);

        // Check error on trying to update gauge.
        gauge = makeAddr('NEW_GAUGE');

        vm.expectRevert(SovereignPool.SovereignPool__setGauge_gaugeAlreadySet.selector);

        pool.setGauge(gauge);
    }

    function test_setSwapFeeModule() public {
        address swapFeeModule = makeAddr('SWAP_FEE_MODULE');

        // Check error on unauthorized call to set swap fee module.
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setSwapFeeModule(swapFeeModule);

        vm.startPrank(POOL_MANAGER);

        // Test Swap Fee Module is set correctly
        pool.setSwapFeeModule(swapFeeModule);

        assertEq(pool.swapFeeModule(), swapFeeModule);
        assertEq(pool.swapFeeModuleUpdateTimestamp(), block.timestamp + 3 days);

        // Check error on Swap Fee Module being set too frequently (more than once every 3 days)
        vm.expectRevert(SovereignPool.SovereignPool__setSwapFeeModule_timelock.selector);
        pool.setSwapFeeModule(swapFeeModule);

        // Test Swap Fee Module update after timelock
        vm.warp(block.timestamp + 3 days);
        pool.setSwapFeeModule(ZERO_ADDRESS);
        assertEq(pool.swapFeeModule(), ZERO_ADDRESS);
        assertEq(pool.swapFeeModuleUpdateTimestamp(), block.timestamp + 3 days);
    }

    function test_setALM() public {
        address alm;

        // Check error on unauthorized call to set alm.
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setALM(alm);

        vm.startPrank(POOL_MANAGER);

        // Check zero error protection.
        vm.expectRevert(SovereignPool.SovereignPool__ZeroAddress.selector);

        pool.setALM(alm);

        alm = makeAddr('ALM');

        pool.setALM(alm);

        assertEq(pool.alm(), alm);

        // Check error on trying to update alm.
        alm = makeAddr('NEW_ALM');
        vm.expectRevert(SovereignPool.SovereignPool__ALMAlreadySet.selector);
        pool.setALM(alm);
    }

    function test_claimPoolManagerFees() public {
        // Check error on unauthorized call to claim pool manager fees.
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.claimPoolManagerFees(1e3, 1e3);

        // Check fee bips are less than or equal to 1e4.
        vm.expectRevert(SovereignPool.SovereignPool___claimPoolManagerFees_invalidProtocolFee.selector);

        vm.prank(POOL_MANAGER);

        pool.claimPoolManagerFees(1e4 + 1, 1e4 + 1);

        _setupBalanceForUser(address(pool), address(token0), 20e18);
        _setupBalanceForUser(address(pool), address(token1), 20e18);

        _setPoolManagerFees(10e18, 10e18);

        vm.prank(POOL_MANAGER);
        pool.claimPoolManagerFees(5e3, 5e3);

        _assertTokenBalance(token0, POOL_MANAGER, 5e18);
        _assertTokenBalance(token1, POOL_MANAGER, 5e18);

        assertEq(pool.feeProtocol0(), 5e18);
        assertEq(pool.feeProtocol1(), 5e18);

        // For pool with sovereign vault.
        address sovereignVault = MockSovereignVaultHelper.deploySovereignVault();

        CustomConstructorArgsParams memory customParams;
        customParams.sovereignVault = sovereignVault;

        SovereignPoolConstructorArgs memory args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        MockSovereignVaultHelper.setPool(sovereignVault, address(pool));

        // Test with excess fee from sovereign vault.
        MockSovereignVaultHelper.toggleExcessFee(sovereignVault, true);

        _setupBalanceForUser(sovereignVault, address(token0), 10e18 + 1);
        _setupBalanceForUser(sovereignVault, address(token1), 10e18 + 1);

        _setPoolManagerFees(10e18, 10e18);

        vm.expectRevert(SovereignPool.SovereignPool___claimPoolManagerFees_invalidFeeReceived.selector);
        vm.prank(POOL_MANAGER);
        pool.claimPoolManagerFees(0, 0);

        MockSovereignVaultHelper.toggleExcessFee(sovereignVault, false);

        // Test happy path with sovereign vault.
        _setZeroBalance(POOL_MANAGER, token0);
        _setZeroBalance(POOL_MANAGER, token1);

        vm.prank(POOL_MANAGER);
        pool.claimPoolManagerFees(1e3, 1e3);
        _assertTokenBalance(token0, POOL_MANAGER, 9e18);
        _assertTokenBalance(token1, POOL_MANAGER, 9e18);

        assertEq(pool.feeProtocol0(), 1e18);
        assertEq(pool.feeProtocol1(), 1e18);
    }

    function test_claimProtocolFees() public {
        address gauge = makeAddr('GAUGE');

        vm.prank(address(protocolFactory));
        pool.setGauge(gauge);

        // Check error on unauthorized call to claim protocol fees.
        vm.expectRevert(SovereignPool.SovereignPool__onlyGauge.selector);

        pool.claimProtocolFees();

        _setProtocolFees(10e18, 10e18);
        _setupBalanceForUser(address(pool), address(token0), 10e18);
        _setupBalanceForUser(address(pool), address(token1), 10e18);

        vm.prank(gauge);

        pool.claimProtocolFees();

        _assertTokenBalance(token0, gauge, 10e18);
        _assertTokenBalance(token1, gauge, 10e18);

        assertEq(pool.feeProtocol0(), 0);
        assertEq(pool.feeProtocol1(), 0);
    }

    function test_depositLiquidity() public {
        address USER = _randomUser();

        address ALM = address(this);

        _setALMForPool(ALM);

        uint256 amount0Deposit = 100e18;
        uint256 amount1Deposit = 100e18;

        _setupBalanceForUser(ALM, address(token0), amount0Deposit);
        _setupBalanceForUser(ALM, address(token1), amount1Deposit);

        vm.expectRevert(SovereignPool.SovereignPool__onlyALM.selector);

        vm.prank(USER);

        pool.depositLiquidity(10e18, 10e18, address(this), new bytes(0), new bytes(0));

        // Test zero deposit amount for both tokens not allowed.
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_zeroTotalDepositAmount.selector);

        pool.depositLiquidity(0, 0, USER, new bytes(0), abi.encode(0, amount0Deposit, amount1Deposit));

        // Test revert when correct amount not transferred.
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_insufficientToken0Amount.selector);

        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            USER,
            new bytes(0),
            abi.encode(1, amount0Deposit - 1, amount1Deposit)
        );

        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_insufficientToken1Amount.selector);

        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            USER,
            new bytes(0),
            abi.encode(2, amount0Deposit, amount1Deposit - 1)
        );

        // Should work correctly.
        (uint256 amount0, uint256 amount1) = pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            USER,
            new bytes(0),
            abi.encode(0, amount0Deposit, amount1Deposit)
        );

        assertEq(amount0, amount0Deposit);
        assertEq(amount1, amount1Deposit);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, amount0Deposit);
        assertEq(reserve1, amount1Deposit);

        // Tests for custom params.
        CustomConstructorArgsParams memory customArgs;
        customArgs.sovereignVault = makeAddr('VAULT');

        SovereignPoolConstructorArgs memory constructorArgs = _generatCustomConstructorArgs(customArgs);

        pool = this.deploySovereignPool(protocolFactory, constructorArgs);

        _setALMForPool(ALM);

        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_depositDisabled.selector);

        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            USER,
            new bytes(0),
            abi.encode(2, amount0Deposit, amount1Deposit)
        );

        customArgs.sovereignVault = address(0);
        customArgs.verifierModule = address(this);
        customArgs.token0Data = TokenData(true, 10);
        customArgs.token1Data = TokenData(true, 10);

        constructorArgs = _generatCustomConstructorArgs(customArgs);

        pool = this.deploySovereignPool(protocolFactory, constructorArgs);

        _setALMForPool(ALM);

        _setupBalanceForUser(ALM, address(token0), amount0Deposit);
        _setupBalanceForUser(ALM, address(token1), amount1Deposit);

        // Check verify permission error.
        vm.expectRevert(
            abi.encodeWithSelector(
                SovereignPool.SovereignPool___verifyPermission_onlyPermissionedAccess.selector,
                USER,
                uint8(AccessType.DEPOSIT)
            )
        );
        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            USER,
            new bytes(0),
            abi.encode(1, amount0Deposit, amount1Deposit)
        );

        // Check for token0 diff error on transfer.
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_excessiveToken0ErrorOnTransfer.selector);
        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            makeAddr('DEPOSIT'),
            new bytes(0),
            abi.encode(1, amount0Deposit - 11, amount1Deposit)
        );

        // Check for token1 diff error on transfer.
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_excessiveToken1ErrorOnTransfer.selector);
        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            makeAddr('DEPOSIT'),
            new bytes(0),
            abi.encode(1, amount0Deposit, amount1Deposit - 11)
        );

        (amount0, amount1) = pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            makeAddr('DEPOSIT'),
            new bytes(0),
            abi.encode(1, amount0Deposit - 10, amount1Deposit - 10)
        );

        assertEq(amount0, amount0Deposit - 10);
        assertEq(amount1, amount1Deposit - 10);
    }

    function test_withdrawLiquidity() public {
        address USER = _randomUser();

        address ALM = address(this);

        _setALMForPool(ALM);

        uint256 amount0 = 100e18;
        uint256 amount1 = 100e18;

        vm.expectRevert(SovereignPool.SovereignPool__onlyALM.selector);

        vm.prank(USER);
        // Check permissioned call for withdraw liquidity.
        pool.withdrawLiquidity(10e18, 10e18, USER, USER, new bytes(0));

        vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_invalidRecipient.selector);
        pool.withdrawLiquidity(amount0, amount1, USER, address(0), new bytes(0));

        vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve0.selector);
        pool.withdrawLiquidity(amount0, amount1, USER, USER, new bytes(0));

        vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve1.selector);
        pool.withdrawLiquidity(0, amount1, USER, USER, new bytes(0));

        CustomConstructorArgsParams memory customArgs;
        customArgs.verifierModule = address(this);

        pool = this.deploySovereignPool(protocolFactory, _generatCustomConstructorArgs(customArgs));

        _setALMForPool(ALM);
        _setReserves(amount0 + 100, amount1 + 100);

        vm.expectRevert(
            abi.encodeWithSelector(
                SovereignPool.SovereignPool___verifyPermission_onlyPermissionedAccess.selector,
                USER,
                uint8(AccessType.WITHDRAW)
            )
        );

        pool.withdrawLiquidity(amount0, amount1, USER, USER, new bytes(0));

        // Happy path.
        _setupBalanceForUser(address(pool), address(token0), amount0);
        _setupBalanceForUser(address(pool), address(token1), amount1);

        pool.withdrawLiquidity(amount0, amount1, makeAddr('WITHDRAW'), USER, new bytes(0));

        _assertTokenBalance(token0, USER, amount0);
        _assertTokenBalance(token1, USER, amount1);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        assertEq(reserve0, 100);
        assertEq(reserve1, 100);
    }

    /************************************************
     *  Test Public Functions
     ***********************************************/

    function test_flashloan() public {
        IFlashBorrower FLASH_BORROWER = IFlashBorrower(address(this));

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

        // Check flashloan when sovereignVault is not pool address.
        SovereignPoolConstructorArgs memory args = _generateDefaultConstructorArgs();
        address vault = makeAddr('VAULT');
        args.sovereignVault = vault;

        pool = this.deploySovereignPool(protocolFactory, args);

        vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanDisabled.selector);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // Check flashloan for rebase token not allowed.
        args.sovereignVault = address(0);
        args.isToken0Rebase = true;
        pool = this.deploySovereignPool(protocolFactory, args);

        vm.expectRevert(IValantisPool.ValantisPool__flashLoan_rebaseTokenNotAllowed.selector);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);
    }

    function test_swap() public {
        address RECIPIENT = makeAddr('RECIPIENT');

        SovereignPoolSwapParams memory swapParams;

        // Test error when block timestamp is past the deadline
        swapParams.deadline = block.timestamp - 1;

        vm.expectRevert(SovereignPool.SovereignPool__swap_expired.selector);
        pool.swap(swapParams);

        swapParams.deadline = block.timestamp;

        // Test error when amountIn is zero.
        vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
        pool.swap(swapParams);

        swapParams.amountIn = 10e18;

        // Test error when recipient is zero.
        vm.expectRevert(SovereignPool.SovereignPool__swap_invalidRecipient.selector);
        pool.swap(swapParams);

        swapParams.recipient = RECIPIENT;

        // Test error when tokenOut is address(0).
        vm.expectRevert(SovereignPool.SovereignPool__swap_invalidSwapTokenOut.selector);
        pool.swap(swapParams);

        // Test error when tokenOut in tokenIn.
        swapParams.swapTokenOut = address(101);

        vm.expectRevert(SovereignPool.SovereignPool__swap_invalidPoolTokenOut.selector);
        pool.swap(swapParams);

        swapParams.swapTokenOut = address(token0);

        // Test error when fee quoted is more than MAX.
        _setSwapFeeModule(address(this));

        swapParams.swapContext = SovereignPoolSwapContextData(
            new bytes(0),
            new bytes(0),
            new bytes(0),
            abi.encode(10_001, new bytes(0))
        );

        vm.expectRevert(SovereignPool.SovereignPool__swap_excessiveSwapFee.selector);
        pool.swap(swapParams);

        _setSwapFeeModule(address(0));

        _setALM(address(this));

        // Test failing cases for invalid liquidity quote by ALM.

        swapParams.swapContext.externalContext = abi.encode(ALMLiquidityQuote(false, 10e18, 11e18));

        // This revert due to more reserve being quoted than was available in reserves.
        vm.expectRevert(SovereignPool.SovereignPool__swap_invalidLiquidityQuote.selector);
        pool.swap(swapParams);

        _setReserves(10e18, 0);

        swapParams.amountOutMin = 11e18;

        // This revert due to amountOut being quoted less than amountOutMin.
        vm.expectRevert(SovereignPool.SovereignPool__swap_invalidLiquidityQuote.selector);
        pool.swap(swapParams);

        swapParams.amountOutMin = 0;

        // This revert due to more amountIn filled than amountIn provided.
        vm.expectRevert(SovereignPool.SovereignPool__swap_invalidLiquidityQuote.selector);
        pool.swap(swapParams);

        // If amountOut quoted is zero, both amountIn and amountOut returned should be zero.
        swapParams.swapContext.externalContext = abi.encode(ALMLiquidityQuote(false, 0, 5e18));

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountInUsed, 0);
        assertEq(amountOut, 0);

        _setupBalanceForUser(address(pool), address(token0), 10e18);

        // When we want funds to be transferred through callback.
        swapParams.isSwapCallback = true;
        swapParams.swapContext.externalContext = abi.encode(ALMLiquidityQuote(false, 5e18, 5e18));
        swapParams.swapContext.swapCallbackContext = abi.encode(pool.sovereignVault(), 5e18 - 1);

        // Amount transferred in is less than amountIn requested.
        vm.expectRevert(SovereignPool.SovereignPool___handleTokenInOnSwap_invalidTokenInAmount.selector);
        (amountInUsed, amountOut) = pool.swap(swapParams);

        swapParams.isSwapCallback = false;

        // When we want funds to be transferred.
        _setupBalanceForUser(address(this), address(token1), 10e18);

        uint256 snapshot = vm.snapshot();

        // Happy path with zero swap fee.
        (amountInUsed, amountOut) = pool.swap(swapParams);
        assertEq(amountInUsed, 5e18);
        assertEq(amountOut, 5e18);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 5e18);
        assertEq(reserve1, 5e18);

        vm.revertTo(snapshot);
        _setSwapFeeModule(address(this));
        swapParams.swapContext.swapFeeModuleContext = abi.encode(100, new bytes(0));
        swapParams.swapContext.externalContext = abi.encode(
            ALMLiquidityQuote(false, 5e18, Math.mulDiv(10e18, 1e4, 1e4 + 100))
        );

        // Half fee to pool manager.
        _setPoolManagerFeeBips(5000);
        (amountInUsed, amountOut) = pool.swap(swapParams);

        // Check fee and reserve updates correctly.
        assertEq(amountInUsed, 10e18, 'AmountIn not correct');
        assertEq(amountOut, 5e18, 'AmountOut not correct');

        (reserve0, reserve1) = pool.getReserves();

        assertEq(reserve0, 5e18, 'Reserve0 not updated correctly');
        assertEq(
            reserve1,
            Math.mulDiv(10e18, 1e4, 1e4 + 100) + (10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100)) / 2,
            'Reserve1 not updated correctly'
        );

        (uint256 poolManagerFee0, uint256 poolManagerFee1) = pool.getPoolManagerFees();
        assertEq(poolManagerFee0, 0, 'Pool manager0 fee not updated correctly');
        assertEq(
            poolManagerFee1,
            (10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100)) / 2,
            'Pool manager1 fee not updated correctly'
        );

        // Swap in opposite direction to check it behaves same.
        vm.revertTo(snapshot);

        _setZeroBalance(address(pool), token0);
        _setZeroBalance(address(pool), token1);
        _setPoolManagerFees(0, 0);

        _setReserves(0, 10e18);
        _setupBalanceForUser(address(pool), address(token1), 10e18);

        _setSwapFeeModule(address(this));
        _setOracleModule(address(this));

        _setupBalanceForUser(address(this), address(token0), 10e18);

        swapParams.swapTokenOut = address(token1);
        swapParams.isZeroToOne = true;
        swapParams.swapContext.swapFeeModuleContext = abi.encode(100, abi.encode('test'));
        swapParams.swapContext.externalContext = abi.encode(
            ALMLiquidityQuote(true, 5e18, Math.mulDiv(10e18, 1e4, 1e4 + 100))
        );

        // Half fee to pool manager.
        _setPoolManagerFeeBips(5000);

        // Checks callback to ALM on swap end.
        vm.expectCall(address(this), abi.encodeWithSelector(ISovereignALM.onSwapCallback.selector, true, 10e18, 5e18));

        // Check callback to oracle.
        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                ISovereignOracle.writeOracleUpdate.selector,
                true,
                10e18,
                10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100),
                5e18
            )
        );

        // Check callback to swap fee module.
        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                ISovereignSwapFeeModule.callbackOnSwapEnd.selector,
                10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100),
                10e18,
                5e18,
                SwapFeeModuleData(100, abi.encode('test'))
            )
        );

        (amountInUsed, amountOut) = pool.swap(swapParams);

        // Check fee and reserve updates correctly.
        assertEq(amountInUsed, 10e18, 'AmountIn not correct');
        assertEq(amountOut, 5e18, 'AmountOut not correct');

        (reserve0, reserve1) = pool.getReserves();

        assertEq(reserve1, 5e18, 'Reserve0 not updated correctly');
        assertEq(
            reserve0,
            Math.mulDiv(10e18, 1e4, 1e4 + 100) + (10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100)) / 2,
            'Reserve1 not updated correctly'
        );

        (poolManagerFee0, poolManagerFee1) = pool.getPoolManagerFees();
        assertEq(poolManagerFee1, 0, 'Pool manager0 fee not updated correctly');
        assertEq(
            poolManagerFee0,
            (10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100)) / 2,
            'Pool manager1 fee not updated correctly'
        );
    }

    function test_swap_rebaseTokens() public {
        address RECIPIENT = makeAddr('RECIPIENT');

        SovereignPoolSwapParams memory swapParams;
        swapParams.amountIn = 10e18;
        swapParams.deadline = block.timestamp;
        swapParams.recipient = RECIPIENT;

        // Prepare new pool, but with rebase tokens.
        SovereignPoolConstructorArgs memory args = _generateDefaultConstructorArgs();

        args.isToken0Rebase = true;
        args.isToken1Rebase = true;
        args.token0AbsErrorTolerance = 10;
        args.token1AbsErrorTolerance = 10;

        pool = this.deploySovereignPool(protocolFactory, args);

        _setALM(address(this));
        _setPoolManagerFeeBips(5000);
        _setOracleModule(address(this));
        _setSwapFeeModule(address(this));

        uint256 snapshot = vm.snapshot();

        _setReserves(0, 10e18);
        _setupBalanceForUser(address(pool), address(token1), 10e18);
        _setupBalanceForUser(address(this), address(token0), 10e18);

        swapParams.swapTokenOut = address(token1);
        swapParams.isZeroToOne = true;
        swapParams.isSwapCallback = true;
        swapParams.swapContext.swapFeeModuleContext = abi.encode(100, abi.encode('test'));
        swapParams.swapContext.swapCallbackContext = abi.encode(
            pool.sovereignVault(),
            Math.mulDiv(10e18, 1e4, 1e4 + 100) - 11
        );

        swapParams.swapContext.externalContext = abi.encode(
            ALMLiquidityQuote(true, 5e18, Math.mulDiv(10e18, 1e4, 1e4 + 100))
        );

        // Should revert when error in token in transfer for rebase token is more than 10.
        vm.expectRevert(SovereignPool.SovereignPool___handleTokenInOnSwap_excessiveTokenInErrorOnTransfer.selector);
        pool.swap(swapParams);

        swapParams.swapContext.swapCallbackContext = abi.encode(pool.sovereignVault(), 10e18 - 9);

        // Checks callback to ALM on swap end.
        vm.expectCall(address(this), abi.encodeWithSelector(ISovereignALM.onSwapCallback.selector, true, 10e18, 5e18));

        // Check callback to oracle.
        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                ISovereignOracle.writeOracleUpdate.selector,
                true,
                10e18,
                10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100),
                5e18
            )
        );

        // Check callback to swap fee module.
        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                ISovereignSwapFeeModule.callbackOnSwapEnd.selector,
                10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100),
                10e18,
                5e18,
                SwapFeeModuleData(100, abi.encode('test'))
            )
        );

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountInUsed, 10e18);
        assertEq(amountOut, 5e18);

        _assertTokenBalance(token0, POOL_MANAGER, (10e18 - Math.mulDiv(10e18, 1e4, 1e4 + 100)) / 2);

        // Do reverse swap and set pool manager to address(0) to make sure, fee is not transferred to zero address

        vm.revertTo(snapshot);

        _setPoolManager(ZERO_ADDRESS);
        _setReserves(10e18, 0);
        _setupBalanceForUser(address(pool), address(token0), 10e18);
        _setupBalanceForUser(address(this), address(token1), 10e18);

        swapParams.swapTokenOut = address(token0);
        swapParams.isZeroToOne = false;
        swapParams.isSwapCallback = true;
        swapParams.swapContext.swapFeeModuleContext = abi.encode(100, abi.encode('test'));
        swapParams.swapContext.swapCallbackContext = abi.encode(pool.sovereignVault(), 10e18 - 9);

        swapParams.swapContext.externalContext = abi.encode(
            ALMLiquidityQuote(true, 5e18, Math.mulDiv(10e18, 1e4, 1e4 + 100))
        );

        (amountInUsed, amountOut) = pool.swap(swapParams);
        assertEq(amountInUsed, 10e18);
        assertEq(amountOut, 5e18);

        _assertTokenBalance(token0, ZERO_ADDRESS, 0);
    }

    function test_swap_verifierModule() public {
        address RECIPIENT = makeAddr('RECIPIENT');

        address SWAP_USER = makeAddr('SWAP');

        SovereignPoolSwapParams memory swapParams;

        swapParams.amountIn = 10e18;
        swapParams.deadline = block.timestamp;
        swapParams.recipient = RECIPIENT;
        swapParams.swapTokenOut = address(token0);

        // Test with permission verifier.

        SovereignPoolConstructorArgs memory args = _generateDefaultConstructorArgs();
        args.verifierModule = address(this);

        pool = this.deploySovereignPool(protocolFactory, args);
        _addToContractsToApprove(address(pool));

        _setALM(address(this));
        _setReserves(10e18, 0);

        swapParams.swapContext.externalContext = abi.encode(ALMLiquidityQuote(false, 5e18, 5e18));
        _setupBalanceForUser(address(pool), address(token0), 10e18);
        _setupBalanceForUser(SWAP_USER, address(token1), 5e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                SovereignPool.SovereignPool___verifyPermission_onlyPermissionedAccess.selector,
                RECIPIENT,
                uint8(AccessType.SWAP)
            )
        );

        vm.prank(RECIPIENT);
        pool.swap(swapParams);

        vm.prank(SWAP_USER);
        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);
        assertEq(amountInUsed, 5e18);
        assertEq(amountOut, 5e18);
    }

    function test_swap_sovereignVault() public {
        address sovereignVault = MockSovereignVaultHelper.deploySovereignVault();

        CustomConstructorArgsParams memory customParams;
        customParams.token0Data.isTokenRebase = true;
        customParams.token1Data.isTokenRebase = true;
        customParams.sovereignVault = sovereignVault;

        pool = this.deploySovereignPool(protocolFactory, _generatCustomConstructorArgs(customParams));
        _addToContractsToApprove(address(pool));

        _setReserves(10e18, 0);
        _setALM(address(this));

        _setupBalanceForUser(address(this), address(token1), 10e18);

        _setupBalanceForUser(sovereignVault, address(token0), 10e18);

        MockSovereignVaultHelper.setPool(sovereignVault, address(pool));

        SovereignPoolSwapParams memory swapParams;

        swapParams.amountIn = 10e18;
        swapParams.deadline = block.timestamp;
        swapParams.swapTokenOut = address(token0);
        swapParams.recipient = makeAddr('RECIPIENT');

        swapParams.swapContext.externalContext = abi.encode(ALMLiquidityQuote(true, 5e18, 10e18));

        (uint256 amountIn, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountIn, 10e18);
        assertEq(amountOut, 5e18);

        _assertTokenBalance(token0, sovereignVault, 5e18);
    }

    /************************************************
     *  Test View Functions
     ***********************************************/

    function test_getReserves() public {
        _setReserves(10e18, 10e18);
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        assertEq(reserve0, 10e18);
        assertEq(reserve1, 10e18);

        // Check when pool only have rebase tokens.
        CustomConstructorArgsParams memory customParams;
        customParams.token0Data.isTokenRebase = true;
        customParams.token1Data.isTokenRebase = true;

        SovereignPoolConstructorArgs memory args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        _setupBalanceForUser(address(pool), address(token0), 10e18);
        _setupBalanceForUser(address(pool), address(token1), 10e18);

        (reserve0, reserve1) = pool.getReserves();

        assertEq(reserve0, 10e18);
        assertEq(reserve1, 10e18);

        // For pool with sovereign vault and rebase tokens.
        address sovereignVault = MockSovereignVaultHelper.deploySovereignVault();

        customParams.token0Data.isTokenRebase = true;
        customParams.token1Data.isTokenRebase = true;
        customParams.sovereignVault = sovereignVault;

        args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        MockSovereignVaultHelper.setPool(sovereignVault, address(pool));

        _setupBalanceForUser(sovereignVault, address(token0), 10e18);
        _setupBalanceForUser(sovereignVault, address(token1), 10e18);

        (reserve0, reserve1) = pool.getReserves();

        assertEq(reserve0, 10e18);
        assertEq(reserve1, 10e18);

        MockSovereignVaultHelper.toggleInvalidReserveArray(sovereignVault, true);

        vm.expectRevert(SovereignPool.SovereignPool__getReserves_invalidReservesLength.selector);

        pool.getReserves();
    }

    function test_getTokens() public {
        address[] memory tokens = pool.getTokens();

        assertEq(tokens.length, 2);

        assertEq(tokens[0], address(token0));
        assertEq(tokens[1], address(token1));

        // For pools with sovereign vault.
        address sovereignVault = MockSovereignVaultHelper.deploySovereignVault();

        CustomConstructorArgsParams memory customParams;
        customParams.token0Data.isTokenRebase = true;
        customParams.token1Data.isTokenRebase = true;
        customParams.sovereignVault = sovereignVault;

        SovereignPoolConstructorArgs memory args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        MockSovereignVaultHelper.setPool(sovereignVault, address(pool));

        vm.expectCall(
            sovereignVault,
            abi.encodeWithSelector(ISovereignVaultMinimal.getTokensForPool.selector, address(pool))
        );

        tokens = pool.getTokens();

        assertEq(tokens.length, 2);

        assertEq(tokens[0], address(token0));
        assertEq(tokens[1], address(token1));
    }
}
