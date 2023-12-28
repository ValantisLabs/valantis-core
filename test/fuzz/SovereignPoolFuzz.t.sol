// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

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
import { IFlashBorrower } from 'src/pools/interfaces/IFlashBorrower.sol';
import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';

import { SovereignPoolBase } from 'test/base/SovereignPoolBase.t.sol';
import { MockSovereignVaultHelper } from 'test/helpers/MockSovereignVaultHelper.sol';
import { Utils } from 'test/helpers/Utils.sol';

contract SovereignPoolFuzz is SovereignPoolBase {
    /************************************************
     *  STRUCTS
     ***********************************************/

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

    struct FlashloanFuzzParams {
        uint256 amount;
        bool isTokenZero;
        uint256 op;
        uint256 reserve0;
        uint256 reserve1;
        uint8 flags;
    }

    struct SwapFuzzParams {
        uint256 amountIn;
        uint256 amountOutMin;
        uint256 amountInFilled;
        uint256 amountOut;
        uint256 reserve0;
        uint256 reserve1;
        uint8 flags;
    }

    /************************************************
     *  MODIFIERS
     ***********************************************/

    modifier setupPool(uint8 flags) {
        _setupRandomPool(flags);
        _;
    }

    /************************************************
     *  Test public functions
     ***********************************************/

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

        // Set this address as ALM
        _setALM(address(this));

        _setReservesForPool(fuzzParams.reserve0, fuzzParams.reserve1);

        if (pool.verifierModule() != address(0)) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    SovereignPool.SovereignPool___verifyPermission_onlyPermissionedAccess.selector,
                    USER,
                    uint8(AccessType.WITHDRAW)
                )
            );

            pool.withdrawLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, USER, abi.encode(false));
        }

        (uint256 preReserve0, uint256 preReserve1) = pool.getReserves();

        bool isRevert;

        if (pool.sovereignVault() == address(pool) && fuzzParams.amount0 > preReserve0) {
            isRevert = true;
            vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve0.selector);
        } else if (pool.sovereignVault() == address(pool) && fuzzParams.amount1 > preReserve1) {
            isRevert = true;
            vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve1.selector);
        } else if (pool.sovereignVault() != address(pool)) {
            _setupBalanceForUser(address(pool), address(token0), fuzzParams.amount0);
            _setupBalanceForUser(address(pool), address(token1), fuzzParams.amount1);

            if (!pool.isToken0Rebase() && fuzzParams.amount0 > 0) {
                isRevert = true;
                vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve0.selector);
            } else if (!pool.isToken1Rebase() && fuzzParams.amount1 > 0) {
                isRevert = true;
                vm.expectRevert(SovereignPool.SovereignPool__withdrawLiquidity_insufficientReserve1.selector);
            }
        }

        pool.withdrawLiquidity(fuzzParams.amount0, fuzzParams.amount1, USER, USER, abi.encode(true));

        if (isRevert) {
            return;
        }

        if (pool.sovereignVault() != address(pool)) {
            (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();

            assertEq(preReserve0, postReserve0);
            assertEq(preReserve1, postReserve1);
        } else {
            (uint256 postReserve0, uint256 postReserve1) = pool.getReserves();

            assertEq(postReserve0, preReserve0 - fuzzParams.amount0);
            assertEq(postReserve1, preReserve1 - fuzzParams.amount1);
        }
    }

    function test_flashloan(FlashloanFuzzParams memory fuzzParams) public setupPool(fuzzParams.flags) {
        fuzzParams.amount = bound(fuzzParams.amount, 1, 1e26);
        address USER = _randomUser();
        IFlashBorrower FLASH_BORROWER = IFlashBorrower(address(this));

        // Set this address as ALM
        _setALM(address(this));
        _setReservesForPool(fuzzParams.reserve0, fuzzParams.reserve1);

        uint256 tokenReserve = fuzzParams.isTokenZero ? fuzzParams.reserve0 : fuzzParams.reserve1;

        if (pool.sovereignVault() != address(pool)) {
            vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanDisabled.selector);
        } else if (
            (fuzzParams.isTokenZero && pool.isToken0Rebase()) || (!fuzzParams.isTokenZero && pool.isToken1Rebase())
        ) {
            vm.expectRevert(IValantisPool.ValantisPool__flashLoan_rebaseTokenNotAllowed.selector);
        } else if (fuzzParams.amount > tokenReserve) {
            vm.expectRevert('ERC20: transfer amount exceeds balance');
        } else if (fuzzParams.op == 0) {
            vm.expectRevert(IValantisPool.ValantisPool__flashloan_callbackFailed.selector);
        } else if (fuzzParams.op == 3) {
            if (fuzzParams.amount < (fuzzParams.isTokenZero ? fuzzParams.reserve0 : fuzzParams.reserve1)) {
                vm.expectRevert(IValantisPool.ValantisPool__flashLoan_flashLoanNotRepaid.selector);
            }
        } else if (fuzzParams.op == 2) {
            /// Passing condition
        } else {
            vm.expectRevert('ERC20: insufficient allowance');
        }

        vm.prank(USER);
        pool.flashLoan(fuzzParams.isTokenZero, FLASH_BORROWER, fuzzParams.amount, abi.encode(fuzzParams.op, USER));

        (uint256 reserve0, uint256 reserve1) = pool.getReserves();

        assertEq(reserve0, fuzzParams.reserve0);
        assertEq(reserve1, fuzzParams.reserve1);

        if (pool.sovereignVault() == address(pool)) {
            _assertTokenBalance(token0, address(pool), fuzzParams.reserve0);
            _assertTokenBalance(token1, address(pool), fuzzParams.reserve1);
        }
    }

    function test_swap(SwapFuzzParams memory fuzzParams) public setupPool(fuzzParams.flags) {
        fuzzParams.amountIn = bound(fuzzParams.amountIn, 0, 1e26);
        fuzzParams.amountInFilled = bound(fuzzParams.amountInFilled, 0, 1e26);
        fuzzParams.amountOut = bound(fuzzParams.amountOut, 0, 1e26);
        fuzzParams.reserve0 = bound(fuzzParams.reserve0, 0, 1e26);
        fuzzParams.reserve1 = bound(fuzzParams.reserve1, 0, 1e26);

        // calculate isDifferentTokenOut from 4 unused bits in flags
        bool isDifferentTokenOut = (fuzzParams.flags & (1 << 5)) != 0;

        // set reserves for pool
        _setReservesForPool(fuzzParams.reserve0, fuzzParams.reserve1);

        _setALM(address(this));

        address USER = _randomUser();

        // calculate isSwapCallback and isZeroToOne from 4 unused bits in flags
        SovereignPoolSwapParams memory swapParams = SovereignPoolSwapParams(
            (fuzzParams.flags & (1 << 7)) != 0,
            (fuzzParams.flags & (1 << 6)) != 0,
            fuzzParams.amountIn,
            fuzzParams.amountOutMin,
            _randomUser(),
            ZERO_ADDRESS,
            SovereignPoolSwapContextData(new bytes(0), new bytes(0), new bytes(0), new bytes(0))
        );

        // set up balance for user
        _setupBalanceForUser(USER, swapParams.isZeroToOne ? address(token0) : address(token1), fuzzParams.amountIn);

        if (swapParams.isZeroToOne) {
            swapParams.swapTokenOut = address(token1);
        } else {
            swapParams.swapTokenOut = address(token0);
        }

        if (swapParams.amountIn == 0) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_insufficientAmountIn.selector);
            vm.prank(USER);
            pool.swap(swapParams);
            return;
        }

        if (swapParams.recipient == ZERO_ADDRESS) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_invalidRecipient.selector);
            vm.prank(USER);
            pool.swap(swapParams);
            return;
        }

        if (isDifferentTokenOut) {
            address token = _deployToken('Token 3', 'TOKEN3');
            swapParams.swapTokenOut = token;
            _setupBalanceForUser(pool.sovereignVault(), token, fuzzParams.amountOut);
        }

        if (isDifferentTokenOut && pool.sovereignVault() == address(pool)) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_invalidPoolTokenOut.selector);
            vm.prank(USER);
            pool.swap(swapParams);
            return;
        }

        if (pool.verifierModule() != address(0)) {
            swapParams.swapContext.verifierContext = abi.encode(false);
            vm.expectRevert(
                abi.encodeWithSelector(
                    SovereignPool.SovereignPool___verifyPermission_onlyPermissionedAccess.selector,
                    USER,
                    uint8(AccessType.SWAP)
                )
            );
            vm.prank(USER);
            pool.swap(swapParams);

            swapParams.swapContext.verifierContext = abi.encode(true);
        }

        swapParams.swapContext.externalContext = abi.encode(
            ALMLiquidityQuote(true, true, fuzzParams.amountOut, fuzzParams.amountInFilled)
        );

        uint256 amountInTransferred = fuzzParams.amountInFilled ==
            Math.mulDiv(fuzzParams.amountIn, 1e4, 1e4 + pool.defaultSwapFeeBips())
            ? fuzzParams.amountIn
            : fuzzParams.amountInFilled + Math.mulDiv(fuzzParams.amountInFilled, pool.defaultSwapFeeBips(), 1e4);

        if (swapParams.isSwapCallback) {
            swapParams.swapContext.swapCallbackContext = abi.encode(pool.sovereignVault(), amountInTransferred);
        }

        if (!_checkLiquidityQuote(fuzzParams, swapParams.isZeroToOne)) {
            vm.expectRevert(SovereignPool.SovereignPool__swap_invalidLiquidityQuote.selector);
            vm.prank(USER);
            pool.swap(swapParams);
            return;
        }

        if (fuzzParams.amountOut == 0) {
            (uint256 amountInUsed_, uint256 amountOut_) = pool.swap(swapParams);
            assertEq(amountInUsed_, 0);
            assertEq(amountOut_, 0);
            return;
        }

        if (
            pool.sovereignVault() != address(pool) &&
            IERC20(swapParams.swapTokenOut).balanceOf(pool.sovereignVault()) < fuzzParams.amountOut
        ) {
            vm.expectRevert('ERC20: transfer amount exceeds balance');
            if (!swapParams.isSwapCallback) vm.prank(USER);
            pool.swap(swapParams);
            return;
        }

        if (!swapParams.isSwapCallback) _expectTokenInTransferCall(swapParams, USER, amountInTransferred);
        _expectTokenOutTransferCall(swapParams, fuzzParams.amountOut);

        if (!swapParams.isSwapCallback) vm.prank(USER);

        (uint256 amountInUsed, uint256 amountOut) = pool.swap(swapParams);

        assertEq(amountInUsed, amountInTransferred);

        assertEq(amountOut, fuzzParams.amountOut);

        if (pool.sovereignVault() != address(pool)) {
            if (isDifferentTokenOut) {
                _assertPostReserves(swapParams.isZeroToOne, fuzzParams.reserve0, fuzzParams.reserve1, amountInUsed, 0);
            } else {
                _assertPostReserves(
                    swapParams.isZeroToOne,
                    fuzzParams.reserve0,
                    fuzzParams.reserve1,
                    amountInUsed,
                    amountOut
                );
            }
        } else {
            _assertPostReserves(
                swapParams.isZeroToOne,
                fuzzParams.reserve0,
                fuzzParams.reserve1,
                amountInUsed,
                amountOut
            );
        }
    }

    /************************************************
     *  INTERNAL HELPER FUNCTIONS
     ***********************************************/

    function _checkLiquidityQuote(SwapFuzzParams memory fuzzParams, bool isZeroToOne) internal view returns (bool) {
        if (pool.sovereignVault() == address(pool)) {
            if (isZeroToOne && fuzzParams.amountOut > fuzzParams.reserve1) {
                return false;
            }

            if (!isZeroToOne && fuzzParams.amountOut > fuzzParams.reserve0) {
                return false;
            }
        }

        if (fuzzParams.amountOut < fuzzParams.amountOutMin) {
            return false;
        }

        if (Math.mulDiv(fuzzParams.amountIn, 1e4, 1e4 + pool.defaultSwapFeeBips()) < fuzzParams.amountInFilled) {
            return false;
        }

        return true;
    }

    // interpret flag by getting bit value at i-th index
    // 0 -> sovereign vault
    // 1 -> verifier module
    // 2 -> token0Rebase
    // 3 -> token1Rebase
    function _setupRandomPool(uint8 flags) internal {
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

        if (sovereignVault) MockSovereignVaultHelper.setPool(args.sovereignVault, address(pool));
    }
}
