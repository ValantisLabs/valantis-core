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
import { SwapFeeModuleData } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { ISovereignVaultMinimal } from 'src/pools/interfaces/ISovereignVaultMinimal.sol';

import { SovereignPoolBase } from 'test/base/SovereignPoolBase.t.sol';
import { MockSovereignVaultHelper } from 'test/helpers/MockSovereignVaultHelper.sol';
import { Utils } from 'test/helpers/Utils.sol';

contract SovereignPoolFuzz is SovereignPoolBase {
    // interpret flag by getting bit value at i-th index
    // 0 -> sovereign vault
    // 1 -> verifier module
    // 2 -> token0Rebase
    // 3 -> token1Rebase
    modifier setupPool(uint8 flags) {
        bool sovereignVault = (flags & (1 << 0)) != 0;
        bool verifierModule = (flags & (1 << 1)) != 0;
        bool token0Rebase = (flags & (1 << 2)) != 0;
        bool token1Rebase = (flags & (1 << 3)) != 0;

        SovereignPoolConstructorArgs memory args = _generateDefaultConstructorArgs();
        if (sovereignVault) args.sovereignVault = MockSovereignVaultHelper.deploySovereignVault();
        if (verifierModule) args.verifierModule = address(this);

        if (token0Rebase) {
            args.isToken0Rebase = true;
            args.token0AbsErrorTolerance = (flags | (1 << 4)) % 11;
        }

        if (token1Rebase) {
            args.isToken1Rebase = true;
            args.token1AbsErrorTolerance = (flags | (1 << 5)) % 11;
        }

        args.defaultSwapFeeBips = (uint256(flags) * (1 << 13)) % 10_000;

        pool = this.deploySovereignPool(protocolFactory, args);
        _addToContractsToApprove(address(pool));

        _;
    }

    struct DepositFuzzParams {
        uint256 amount0;
        uint256 amount1;
        uint256 amount0ToDeposit;
        uint256 amount1ToDeposit;
        uint8 flags;
    }

    struct WithdrawFuzzParams {
        uint256 amount0;
        uint256 amount1;
        uint256 reserve0;
        uint256 reserve1;
        uint8 flags;
    }

    function test_deposit(DepositFuzzParams memory fuzzParams) public setupPool(fuzzParams.flags) {
        fuzzParams.amount0 = bound(fuzzParams.amount0, 0, 1e26);
        fuzzParams.amount1 = bound(fuzzParams.amount1, 0, 1e26);

        address USER = _randomUser();

        // Set this address as ALM
        _setALM(address(this));

        if (pool.sovereignVault() != address(pool)) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_depositDisabled.selector);
            pool.depositLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, new bytes(0), new bytes(0));
            return;
        }

        if (fuzzParams.amount0 == 0 && fuzzParams.amount1 == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_zeroTotalDepositAmount.selector);

            pool.depositLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, new bytes(0), new bytes(0));

            return;
        }

        if (pool.verifierModule() != address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SovereignPool.SovereignPool___verifyPermission_onlyPermissionedAccess.selector,
                    USER,
                    uint8(AccessType.DEPOSIT)
                )
            );

            pool.depositLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, abi.encode(false), new bytes(0));
        }

        _setupBalanceForUser(address(this), address(token0), fuzzParams.amount0ToDeposit);
        _setupBalanceForUser(address(this), address(token1), fuzzParams.amount1ToDeposit);

        bytes memory depositData = abi.encode(0, fuzzParams.amount0ToDeposit, fuzzParams.amount1ToDeposit);
        (uint256 preReserve0, uint256 preReserve1) = pool.getReserves();

        if (
            pool.isToken0Rebase() &&
            Utils.getAbsoluteDiff(fuzzParams.amount0ToDeposit, fuzzParams.amount0) > pool.token0AbsErrorTolerance()
        ) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_excessiveToken0ErrorOnTransfer.selector);
        } else if (!pool.isToken0Rebase() && fuzzParams.amount0ToDeposit != fuzzParams.amount0) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_insufficientToken0Amount.selector);
        } else if (
            pool.isToken1Rebase() &&
            Utils.getAbsoluteDiff(fuzzParams.amount1ToDeposit, fuzzParams.amount1) > pool.token1AbsErrorTolerance()
        ) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_excessiveToken1ErrorOnTransfer.selector);
        } else if (!pool.isToken1Rebase() && fuzzParams.amount1ToDeposit != fuzzParams.amount1) {
            vm.expectRevert(SovereignPool.SovereignPool__depositLiquidity_insufficientToken1Amount.selector);
        }

        _depositLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, abi.encode(true), depositData);

        _setZeroBalance(address(this), token0);
        _setZeroBalance(address(this), token1);

        _setupBalanceForUser(address(this), address(token0), fuzzParams.amount0);
        _setupBalanceForUser(address(this), address(token1), fuzzParams.amount1);

        (preReserve0, preReserve1) = pool.getReserves();

        depositData = abi.encode(0, fuzzParams.amount0, fuzzParams.amount1);

        _depositLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, abi.encode(true), depositData);

        (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();

        assertEq(preReserve0 + fuzzParams.amount0, postReserve0);
        assertEq(preReserve1 + fuzzParams.amount1, postReserve1);
    }

    function test_withdraw(WithdrawFuzzParams memory fuzzParams) public setupPool(fuzzParams.flags) {
        fuzzParams.amount0 = bound(fuzzParams.amount0, 0, 1e26);
        fuzzParams.amount1 = bound(fuzzParams.amount1, 0, 1e26);

        address USER = _randomUser();
    }

    // function test_withdraw()

    // function test_swap()
}
