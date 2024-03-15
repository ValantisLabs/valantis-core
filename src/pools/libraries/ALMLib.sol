// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from '../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { ALMPosition, ALMStatus } from '../structs/UniversalPoolStructs.sol';
import { EnumerableALMMap } from '../../libraries/EnumerableALMMap.sol';
import { IUniversalALM } from '../../ALM/interfaces/IUniversalALM.sol';

library ALMLib {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;
    using SafeERC20 for IERC20;

    /************************************************
     *  EVENTS
     ***********************************************/

    event DepositLiquidity(address indexed alm, uint256 amount0, uint256 amount1);
    event WithdrawLiquidity(address indexed alm, address indexed recipient, uint256 amount0, uint256 amount1);

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error ALMLib__depositLiquidity_insufficientTokenAmount();
    error ALMLib__depositLiquidity_onlyActiveALMCanDeposit();
    error ALMLib__depositLiquidity_zeroAmounts();
    error ALMLib__withdrawLiquidity_insufficientReserves();

    /************************************************
     *  FUNCTIONS
     ***********************************************/

    /**
        @notice Deposit liquidity into an ALM Position.
        @dev Only callable by its respective active ALM Position.
        @param _amount0 Amount of token0 to deposit.
        @param _amount1 Amount of token1 to deposit. 
     */
    function depositLiquidity(
        // solhint-disable-next-line func-param-name-mixedcase, var-name-mixedcase
        EnumerableALMMap.ALMSet storage _ALMPositions,
        IERC20 _token0,
        IERC20 _token1,
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _depositData
    ) external {
        if (_amount0 == 0 && _amount1 == 0) {
            revert ALMLib__depositLiquidity_zeroAmounts();
        }

        (ALMStatus status, ALMPosition storage almPosition) = _ALMPositions.getALM(msg.sender);

        if (status != ALMStatus.ACTIVE) {
            revert ALMLib__depositLiquidity_onlyActiveALMCanDeposit();
        }

        if (_amount0 > 0) almPosition.reserve0 += _amount0;
        if (_amount1 > 0) almPosition.reserve1 += _amount1;

        uint256 preBalanceToken0 = _token0.balanceOf(address(this));
        uint256 preBalanceToken1 = _token1.balanceOf(address(this));

        IUniversalALM(msg.sender).onDepositLiquidityCallback(_amount0, _amount1, _depositData);

        uint256 amount0Deposited = _token0.balanceOf(address(this)) - preBalanceToken0;
        uint256 amount1Deposited = _token1.balanceOf(address(this)) - preBalanceToken1;

        if (amount0Deposited != _amount0 || amount1Deposited != _amount1) {
            revert ALMLib__depositLiquidity_insufficientTokenAmount();
        }

        emit DepositLiquidity(msg.sender, _amount0, _amount1);
    }

    /**
        @notice Withdraw liquidity from this pool to `recipient`.
        @dev Only callable by its respective ALM Position (either active or inactive).
        @param _amount0 Amount of `token0` reserves to withdraw (excluding accrued fees).
        @param _amount1 Amount of `token1` reserves to withdraw (excluding accrued fees).
        @param _recipient Withdrawal recipient.
     */
    function withdrawLiquidity(
        // solhint-disable-next-line func-param-name-mixedcase, var-name-mixedcase
        EnumerableALMMap.ALMSet storage _ALMPositions,
        IERC20 _token0,
        IERC20 _token1,
        uint256 _amount0,
        uint256 _amount1,
        address _recipient
    ) external {
        // We also allow inactive ALM Positions to withdraw liquidity + fees earned
        // We also allow ALMs removed by the pool manager to withdraw funds.
        (, ALMPosition storage almPosition) = _ALMPositions.getALM(msg.sender);

        if (_amount0 > almPosition.reserve0 || _amount1 > almPosition.reserve1) {
            revert ALMLib__withdrawLiquidity_insufficientReserves();
        }

        unchecked {
            almPosition.reserve0 -= _amount0;
            almPosition.reserve1 -= _amount1;
        }

        if (_amount0 > 0) {
            _token0.safeTransfer(_recipient, _amount0);
        }

        if (_amount1 > 0) {
            _token1.safeTransfer(_recipient, _amount1);
        }

        emit WithdrawLiquidity(msg.sender, _recipient, _amount0, _amount1);
    }
}
