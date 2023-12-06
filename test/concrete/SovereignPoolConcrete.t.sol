// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SovereignPool } from 'src/pools/SovereignPool.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';
import { IFlashBorrower } from 'src/pools/interfaces/IFlashBorrower.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';

import { SovereignPoolBase } from 'test/base/SovereignPoolBase.t.sol';

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
