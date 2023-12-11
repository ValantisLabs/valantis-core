// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SovereignPool } from 'src/pools/SovereignPool.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';
import { IFlashBorrower } from 'src/pools/interfaces/IFlashBorrower.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';

import { SovereignPoolBase } from 'test/base/SovereignPoolBase.t.sol';
import { MockSovereignVaultHelper } from 'test/helpers/MockSovereignVaultHelper.sol';

contract SovereignPoolConcreteTest is SovereignPoolBase {
    /************************************************
     *  Test Constructor
     ***********************************************/

    function test_defaultConstructorArgs() public {
        // check pool manager is set perfectly
        assertEq(pool.poolManager(), POOL_MANAGER);

        address[] memory tokens = pool.getTokens();
        // check tokens are set correctly
        assertEq(tokens[0], address(token0));
        assertEq(tokens[1], address(token1));

        // check protocol factory is set correctly
        assertEq(pool.protocolFactory(), address(protocolFactory));

        // check initial reserves are zero;
        (uint256 reserve0, uint256 reserve1) = pool.getReserves();
        assertEq(reserve0, 0);
        assertEq(reserve1, 0);

        // check sovereign vault is address of pool
        assertEq(pool.sovereignVault(), address(pool));
    }

    function test_customConstructorArgs() public {
        CustomConstructorArgsParams memory customParams = CustomConstructorArgsParams(
            TokenData(true, 9, 1e6),
            TokenData(false, 0, 0),
            makeAddr('SOVEREIGN_VAULT'),
            makeAddr('VERIFIER_MODULE'),
            16
        );

        SovereignPoolConstructorArgs memory args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        uint256 snapshot = vm.snapshot();

        // check custom params for token0
        assertEq(pool.isRebaseTokenPool(), true);
        assertEq(pool.isToken0Rebase(), true);
        assertEq(pool.token0MinAmount(), customParams.token0Data.tokenMinAmount);
        assertEq(pool.token0AbsErrorTolerance(), customParams.token0Data.tokenAbsErrorTolerance);

        // increase tolerance to more than MAX
        args.token0AbsErrorTolerance = 100;

        vm.expectRevert(SovereignPool.SovereignPool__excessiveToken0AbsErrorTolerance.selector);

        this.deploySovereignPool(protocolFactory, args);

        vm.revertTo(snapshot);
        args.token0AbsErrorTolerance = customParams.token0Data.tokenAbsErrorTolerance;

        // check vault and verifier module addresses
        assertEq(pool.sovereignVault(), customParams.sovereignVault);
        assertEq(pool.verifierModule(), customParams.verifierModule);

        // check defaulFeeBips passed
        assertEq(pool.defaultSwapFeeBips(), customParams.defaultFeeBips);

        // increase fee bips to be more than MAX_FEE_BIPS;
        args.defaultSwapFeeBips = 5e10;
        pool = this.deploySovereignPool(protocolFactory, args);
        assertEq(pool.defaultSwapFeeBips(), pool.MAX_SWAP_FEE_BIPS());
    }

    /************************************************
     *  Test Permissioned functions
     ***********************************************/

    function test_setPoolManager() public {
        address newManager = makeAddr('NEW_POOL_MANAGER');

        // check error on unauthorized call to set pool manager
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setPoolManager(newManager);

        vm.prank(POOL_MANAGER);

        pool.setPoolManager(newManager);

        assertEq(pool.poolManager(), newManager);
    }

    function test_setPoolManagerFeeBips() public {
        // check error on unauthorized call to set pool manager
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        uint256 poolManagerFeeBips = 1e10;

        pool.setPoolManagerFeeBips(poolManagerFeeBips);

        vm.startPrank(POOL_MANAGER);

        // check error on trying to set more feeBips than allowed
        vm.expectRevert(SovereignPool.SovereignPool__setPoolManagerFeeBips_excessivePoolManagerFee.selector);

        pool.setPoolManagerFeeBips(poolManagerFeeBips);

        poolManagerFeeBips = pool.MAX_POOL_MANAGER_FEE_BIPS() - 1;

        pool.setPoolManagerFeeBips(poolManagerFeeBips);

        assertEq(pool.poolManagerFeeBips(), poolManagerFeeBips);
    }

    function test_setSovereignOracle() public {
        address oracle;

        // check error on unauthorized call to set sovereign oracle
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setSovereignOracle(oracle);

        vm.startPrank(POOL_MANAGER);

        vm.expectRevert(SovereignPool.SovereignPool__ZeroAddress.selector);
        pool.setSovereignOracle(oracle);

        oracle = makeAddr('ORACLE');

        pool.setSovereignOracle(oracle);

        assertEq(pool.sovereignOracleModule(), oracle);

        oracle = makeAddr('NEW_ORACLE');

        // check error on trying to update sovereign oracle
        vm.expectRevert(SovereignPool.SovereignPool__setSovereignOracle__sovereignOracleAlreadySet.selector);

        pool.setSovereignOracle(oracle);
    }

    function test_setGauge() public {
        address gauge = makeAddr('GAUGE');

        // check error on unauthorized call to set gauge
        vm.expectRevert(SovereignPool.SovereignPool__onlyProtocolFactory.selector);

        pool.setGauge(gauge);

        vm.startPrank(address(protocolFactory));

        pool.setGauge(gauge);

        assertEq(pool.gauge(), gauge);

        // check error on trying to update gauge
        gauge = makeAddr('NEW_GAUGE');

        vm.expectRevert(SovereignPool.SovereignPool__setGauge_gaugeAlreadySet.selector);

        pool.setGauge(gauge);
    }

    function test_setSwapFeeModule() public {
        address swapFeeModule = makeAddr('SWAP_FEE_MODULE');

        // check error on unauthorized call to set swap fee module
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setSwapFeeModule(swapFeeModule);

        vm.startPrank(POOL_MANAGER);

        pool.setSwapFeeModule(swapFeeModule);

        assertEq(pool.swapFeeModule(), swapFeeModule);
    }

    function test_setALM() public {
        address alm;

        // check error on unauthorized call to set alm
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.setALM(alm);

        vm.startPrank(POOL_MANAGER);

        // check zero error protection
        vm.expectRevert(SovereignPool.SovereignPool__ZeroAddress.selector);

        pool.setALM(alm);

        alm = makeAddr('ALM');

        pool.setALM(alm);

        assertEq(pool.alm(), alm);

        // check error on trying to update alm
        alm = makeAddr('NEW_ALM');
        vm.expectRevert(SovereignPool.SovereignPool__ALMAlreadySet.selector);
        pool.setALM(alm);
    }

    function test_claimPoolManagerFees() public {
        // check error on unauthorized call to claim pool manager fees
        vm.expectRevert(SovereignPool.SovereignPool__onlyPoolManager.selector);

        pool.claimPoolManagerFees(1e3, 1e3);

        // check fee bips are less than or equal to 1e4
        vm.expectRevert(SovereignPool.SovereignPool__claimPoolManagerFees_invalidProtocolFee.selector);

        vm.prank(POOL_MANAGER);

        pool.claimPoolManagerFees(1e4 + 1, 1e4 + 1);

        _setupBalanceForUser(address(pool), address(token0), 20e18);
        _setupBalanceForUser(address(pool), address(token1), 20e18);

        _setPoolManagerFeeBips(10e18, 10e18);

        vm.prank(POOL_MANAGER);
        pool.claimPoolManagerFees(5e3, 5e3);

        _assertTokenBalance(token0, POOL_MANAGER, 5e18);
        _assertTokenBalance(token1, POOL_MANAGER, 5e18);

        assertEq(pool.feeProtocol0(), 5e18);
        assertEq(pool.feeProtocol1(), 5e18);

        // for pool with sovereign vault
        address sovereignVault = MockSovereignVaultHelper.deploySovereignVault();

        CustomConstructorArgsParams memory customParams;
        customParams.sovereignVault = sovereignVault;

        SovereignPoolConstructorArgs memory args = _generatCustomConstructorArgs(customParams);

        pool = this.deploySovereignPool(protocolFactory, args);

        MockSovereignVaultHelper.setPool(sovereignVault, address(pool));

        // test with excess fee from sovereign vault
        MockSovereignVaultHelper.toggleExcessFee(sovereignVault, true);

        _setupBalanceForUser(sovereignVault, address(token0), 10e18 + 1);
        _setupBalanceForUser(sovereignVault, address(token1), 10e18 + 1);

        _setPoolManagerFeeBips(10e18, 10e18);

        vm.expectRevert(SovereignPool.SovereignPool__claimPoolManagerFees_invalidFeeReceived.selector);
        vm.prank(POOL_MANAGER);
        pool.claimPoolManagerFees(0, 0);

        MockSovereignVaultHelper.toggleExcessFee(sovereignVault, false);

        // test happy path with sovereign vault
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

        // check error on unauthorized call to claim protocol fees
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

        // test zero deposit amount for both tokens not allowed
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_zeroTotalDepositAmount.selector);

        pool.depositLiquidity(0, 0, USER, new bytes(0), abi.encode(0, amount0Deposit, amount1Deposit));

        // test revert when correct amount not transferred
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

        // should work correctly
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

        // tests for custom params

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
        customArgs.token0Data = TokenData(true, 10, 1e6);
        customArgs.token1Data = TokenData(true, 10, 1e6);

        constructorArgs = _generatCustomConstructorArgs(customArgs);

        pool = this.deploySovereignPool(protocolFactory, constructorArgs);

        _setALMForPool(ALM);

        _setupBalanceForUser(ALM, address(token0), amount0Deposit);
        _setupBalanceForUser(ALM, address(token1), amount1Deposit);

        // check verify permission error
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

        // check token min amount for token0 error
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_token0BelowMinimumDeposit.selector);
        pool.depositLiquidity(
            1e6 - 1,
            amount1Deposit,
            makeAddr('DEPOSIT'),
            new bytes(0),
            abi.encode(0, 1e6 - 1, amount1Deposit)
        );

        // check token min amount for token1 error
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_token1BelowMinimumDeposit.selector);
        pool.depositLiquidity(
            amount0Deposit,
            1e6 - 1,
            makeAddr('DEPOSIT'),
            new bytes(0),
            abi.encode(0, amount0Deposit, 1e6 - 1)
        );

        // check for token0 diff error on transfer
        vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_excessiveToken0ErrorOnTransfer.selector);
        pool.depositLiquidity(
            amount0Deposit,
            amount1Deposit,
            makeAddr('DEPOSIT'),
            new bytes(0),
            abi.encode(1, amount0Deposit - 11, amount1Deposit)
        );

        // check for token1 diff error on transfer
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
        // check permissioned call for withdraw liquidity
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

        // happy path
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

        // check revert on incorrect callback hash
        vm.expectRevert(IValantisPool.ValantisPool__flashloan_callbackFailed.selector);
        vm.prank(initiator);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // check revert on insufficient allowance
        vm.expectRevert('ERC20: insufficient allowance');
        data = abi.encode(1, initiator);
        vm.prank(initiator);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // check revert on amount decrease post flashloan
        data = abi.encode(3, address(this));
        vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanNotRepaid.selector);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // check happy path works fine
        data = abi.encode(2, initiator);
        vm.prank(initiator);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // check flashloan when sovereignVault is not pool address
        SovereignPoolConstructorArgs memory args = _generateDefaultConstructorArgs();
        address vault = makeAddr('VAULT');
        args.sovereignVault = vault;

        pool = this.deploySovereignPool(protocolFactory, args);

        vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanDisabled.selector);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);

        // check flashloan for rebase token not allowed
        args.sovereignVault = address(0);
        args.isToken0Rebase = true;
        pool = this.deploySovereignPool(protocolFactory, args);

        vm.expectRevert(IValantisPool.ValantisPool__flashLoan_rebaseTokenNotAllowed.selector);
        pool.flashLoan(true, FLASH_BORROWER, amount, data);
    }
}
