// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { SovereignPool } from 'src/pools/SovereignPool.sol';
import {
    SovereignPoolSwapParams,
    SovereignPoolSwapContextData,
    SovereignPoolConstructorArgs
} from 'src/pools/structs/SovereignPoolStructs.sol';
import { MockSovereignALM } from 'src/mocks/MockSovereignALM.sol';

import { SovereignPoolBase } from 'test/base/SovereignPoolBase.t.sol';
import { MockSovereignALMHelper } from 'test/helpers/MockSovereignALMHelper.sol';
import { MockSwapFeeModuleHelper } from 'test/helpers/MockSwapFeeModuleHelper.sol';
import { InvariantBase } from 'test/invariant/InvariantBase.sol';

contract SovereignPoolInvariantTest is InvariantBase, SovereignPoolBase {
    SovereignPool[] internal pools;
    address internal GAUGE;

    function setUp() public virtual override {
        super.setUp();

        GAUGE = makeAddr('GAUGE');
        bytes4[] memory handlerSelectors = new bytes4[](8);

        handlerSelectors[0] = this.depositToPool.selector;
        handlerSelectors[1] = this.withdrawFromPool.selector;
        handlerSelectors[2] = this.swap.selector;
        handlerSelectors[3] = this.setPoolManagerFeeBips.selector;
        handlerSelectors[4] = this.claimPoolManagerFees.selector;
        handlerSelectors[5] = this.claimProtocolFees.selector;
        handlerSelectors[6] = this.setSwapFeeBips.selector;

        uint256[] memory numbers = new uint256[](8);
        numbers[0] = 50;
        numbers[1] = 50;
        numbers[2] = 100;
        numbers[3] = 10;
        numbers[4] = 10;
        numbers[5] = 10;
        numbers[6] = 10;

        _setupSelectors(address(this), handlerSelectors, numbers);

        SovereignPoolConstructorArgs memory args = _generateDefaultConstructorArgs();

        // both tokens non rebase tokens
        pools.push(_preparePool(args));

        // token0 rebase
        args.isToken0Rebase = true;
        pools.push(_preparePool(args));

        // both token0 and token1 rebase
        args.isToken1Rebase = true;
        pools.push(_preparePool(args));

        // only token1 rebase
        args.isToken0Rebase = false;
        pools.push(_preparePool(args));

        targetContract(address(this));
    }

    function _preparePool(SovereignPoolConstructorArgs memory args) internal returns (SovereignPool newPool) {
        newPool = this.deploySovereignPool(protocolFactory, args);
        _addToContractsToApprove(address(newPool));

        address alm = MockSovereignALMHelper.deploySovereignALM(address(newPool));
        _addToContractsToApprove(address(alm));

        MockSovereignALMHelper.setSovereignVault(alm);

        vm.prank(POOL_MANAGER);
        newPool.setALM(alm);

        vm.prank(address(protocolFactory));
        newPool.setGauge(GAUGE);

        address swapFeeModule = MockSwapFeeModuleHelper.deployMockSwapFeeModule();
        vm.prank(POOL_MANAGER);
        newPool.setSwapFeeModule(swapFeeModule);
    }

    function _randomPool(uint256 flag) internal {
        pool = pools[flag % pools.length];
    }

    /************************************************
     *  Handler functions
     ***********************************************/

    function depositToPool(uint256 userFlag, uint256 poolFlag, uint256 amount0, uint256 amount1) external {
        amount0 = bound(amount0, 1, 1e26);
        amount1 = bound(amount1, 1, 1e26);

        _randomPool(poolFlag);

        address USER = _randomUser(userFlag);

        _setupBalanceForUser(USER, address(token0), amount0);
        _setupBalanceForUser(USER, address(token1), amount1);

        address alm = pool.alm();
        vm.prank(USER);
        MockSovereignALMHelper.addLiquidity(alm, amount0, amount1);
    }

    function withdrawFromPool(uint256 userFlag, uint256 poolFlag, uint256 amount0, uint256 amount1) external {
        _randomPool(poolFlag);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        amount0 = bound(amount0, 0, reserve0);
        amount1 = bound(amount1, 0, reserve1);

        address USER = _randomUser(userFlag);
        address alm = pool.alm();
        vm.prank(USER);
        MockSovereignALMHelper.withdrawLiquidity(alm, USER, amount0, amount1);
    }

    function swap(uint256 userFlag, uint256 poolFlag, uint256 amountIn, bool isZeroToOne) external {
        amountIn = bound(amountIn, 1, 1e26);

        _randomPool(poolFlag);

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        if ((isZeroToOne && reserve1 == 0) || (!isZeroToOne && reserve0 == 0)) {
            return;
        }

        address USER = _randomUser(userFlag);

        if (isZeroToOne) {
            _setupBalanceForUser(USER, address(token0), amountIn);
        } else {
            _setupBalanceForUser(USER, address(token1), amountIn);
        }

        address swapTokenOut = isZeroToOne ? pool.token1() : pool.token0();
        vm.prank(USER);

        pool.swap(
            SovereignPoolSwapParams(
                false,
                isZeroToOne,
                amountIn,
                0,
                USER,
                swapTokenOut,
                SovereignPoolSwapContextData(new bytes(0), new bytes(0), new bytes(0), new bytes(0))
            )
        );
    }

    function setPoolManagerFeeBips(uint256 poolFlag, uint256 feeBips) external {
        feeBips = bound(feeBips, 0, 5_000);

        _randomPool(poolFlag);

        vm.prank(POOL_MANAGER);

        pool.setPoolManagerFeeBips(feeBips);
    }

    function claimPoolManagerFees(uint256 poolFlag, uint256 fee0Bips, uint256 fee1Bips) external {
        fee0Bips = bound(fee0Bips, 0, 1e4);
        fee1Bips = bound(fee1Bips, 0, 1e4);

        _randomPool(poolFlag);

        vm.prank(POOL_MANAGER);
        pool.claimPoolManagerFees(fee0Bips, fee1Bips);
    }

    function claimProtocolFees(uint256 poolFlag) external {
        _randomPool(poolFlag);

        vm.prank(GAUGE);
        pool.claimProtocolFees();
    }

    function setSwapFeeBips(uint256 poolFlag, uint256 swapFeeBips) external {
        swapFeeBips = bound(swapFeeBips, 0, 10_000);

        _randomPool(poolFlag);

        MockSwapFeeModuleHelper.setSwapFeeBips(pool.swapFeeModule(), swapFeeBips);
    }

    /************************************************
     *  Invariant tests
     ***********************************************/

    function invariant_reserves() public {
        for (uint256 i = 0; i < pools.length; i++) {
            pool = pools[i];

            (uint256 reserve0, uint256 reserve1) = pool.getReserves();

            (uint256 poolManagerFee0, uint256 poolManagerFee1) = pool.getPoolManagerFees();

            uint256 protocolFee0 = pool.feeProtocol0();
            uint256 protocolFee1 = pool.feeProtocol1();

            uint256 token0Balance = token0.balanceOf(address(pool));
            uint256 token1Balance = token1.balanceOf(address(pool));

            assertGe(token0Balance, reserve0 + poolManagerFee0 + protocolFee0);
            assertGe(token1Balance, reserve1 + poolManagerFee1 + protocolFee1);
        }
    }
}
