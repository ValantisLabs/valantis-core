// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Math } from '../../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from '../../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { PoolState } from '../structs/UniversalPoolStructs.sol';
import { EnumerableALMMap } from '../../libraries/EnumerableALMMap.sol';

/**
  @title Helper libary to offload logic from Valantis Universal Pool contract, to save bytecode size.
  @notice Functions - 
        * depositLiquidity
        * withdrawLiquidity
        * claimPoolManagerFees
        * claimProtocolFees
        * setPoolState

    NOTE: These are ONLY supposed to be helper functions, and depend on reentrancy & consistency guarantees
        from the main UniversalPool contract. These functions should NOT be used independently of their counterpart 
        functions in the Universal Pool.
 */
library StateLib {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;
    using SafeERC20 for IERC20;

    /************************************************
     *  CONSTANTS
     ***********************************************/

    /**
        @notice Maximum BIPS for calculation of fee using bips 
     */
    uint256 private constant MAX_SWAP_FEE_BIPS = 1e4;

    /**
        @notice Minimum fee for LPs is 50% of swap fee,
                and 50% maximum goes to the protocol. 
     */
    // solhint-disable-next-line private-vars-leading-underscore
    uint256 private constant MAX_POOL_MANAGER_FEE_BIPS = 5000;

    /************************************************
     *  EVENTS
     ***********************************************/

    event PoolManagerFeesClaimed(uint256 amount0, uint256 amount1);
    event ProtocolFeesClaimed(uint256 amount0, uint256 amount1);
    event PoolManagerFeeSet(uint256 feeBips);
    event PoolManagerSet(address poolManager);
    event SwapFeeModuleSet(address swapFeeModule);
    event OracleSet(address oracleModule);

    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error StateLib__claimPoolManagerFees_invalidProtocolFee();
    error StateLib__setPoolManagerFeeBips_invalidPoolManagerFee();
    error StateLib__setPoolState_onlyPoolManager();
    error StateLib__setUniversalOracle_universalOracleAlreadySet();
    error StateLib__setSwapFeeModule_invalidSwapFeeModule();

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Claim share of fees accrued by this pool, and optionally share some with the protocol.
        @dev Can only be claimed by `poolManager`.
        @param _feeProtocol0Bips Percent of `token0` fees to be shared with protocol.
        @param _feeProtocol1Bips Percent of `token1` fees to be shared with protocol.
        @return feePoolManager0Claimed Amount of `token0` fees claimed by `poolManager`.
        @return feePoolManager1Claimed Amount of `token1` fees claimed by `poolManager`.
     */
    function claimPoolManagerFees(
        PoolState storage _state,
        IERC20 _token0,
        IERC20 _token1,
        uint256 _feeProtocol0Bips,
        uint256 _feeProtocol1Bips
    ) external returns (uint256 feePoolManager0Claimed, uint256 feePoolManager1Claimed) {
        // Underflow prevention
        if (_feeProtocol0Bips > MAX_SWAP_FEE_BIPS || _feeProtocol1Bips > MAX_SWAP_FEE_BIPS) {
            revert StateLib__claimPoolManagerFees_invalidProtocolFee();
        }

        uint256 feePoolManager0 = _state.feePoolManager0;
        uint256 feePoolManager1 = _state.feePoolManager1;

        uint256 feeProtocol0 = Math.mulDiv(_feeProtocol0Bips, feePoolManager0, MAX_SWAP_FEE_BIPS);
        uint256 feeProtocol1 = Math.mulDiv(_feeProtocol1Bips, feePoolManager1, MAX_SWAP_FEE_BIPS);

        feePoolManager0Claimed = feePoolManager0 - feeProtocol0;
        feePoolManager1Claimed = feePoolManager1 - feeProtocol1;

        _state.feeProtocol0 += feeProtocol0;
        _state.feeProtocol1 += feeProtocol1;

        _state.feePoolManager0 = 0;
        _state.feePoolManager1 = 0;

        if (feePoolManager0Claimed > 0) {
            _token0.safeTransfer(msg.sender, feePoolManager0Claimed);
        }

        if (feePoolManager1Claimed > 0) {
            _token1.safeTransfer(msg.sender, feePoolManager1Claimed);
        }

        emit PoolManagerFeesClaimed(feePoolManager0Claimed, feePoolManager1Claimed);
    }

    /**
        @notice Claim share of protocol fees accrued by this pool.
        @dev Can only be claimed by `gauge` of the pool. 
     */
    function claimProtocolFees(
        PoolState storage _state,
        IERC20 _token0,
        IERC20 _token1
    ) external returns (uint256 feeProtocol0Claimed, uint256 feeProtocol1Claimed) {
        feeProtocol0Claimed = _state.feeProtocol0;
        feeProtocol1Claimed = _state.feeProtocol1;

        if (feeProtocol0Claimed > 0) {
            _state.feeProtocol0 = 0;
            _token0.safeTransfer(msg.sender, feeProtocol0Claimed);
        }

        if (feeProtocol1Claimed > 0) {
            _state.feeProtocol1 = 0;
            _token1.safeTransfer(msg.sender, feeProtocol1Claimed);
        }

        emit ProtocolFeesClaimed(feeProtocol0Claimed, feeProtocol1Claimed);
    }

    /**
        @notice Sets the state struct of the pool.
        @dev Can only be set by `poolManager`.
        @dev UniversalOracle can only be set once in the pool.
        @dev PoolManagerFeeBips has to be greater than MAX_POOL_MANAGER_FEE_BIPS.
     */
    function setPoolState(PoolState storage _state, PoolState memory _newState) external {
        // Update Oracle
        if (_state.universalOracle != _newState.universalOracle) {
            // Once an oracle is set, it cannot be changed.
            if (_state.universalOracle != address(0)) {
                revert StateLib__setUniversalOracle_universalOracleAlreadySet();
            } else {
                _state.universalOracle = _newState.universalOracle;
            }

            emit OracleSet(_newState.universalOracle);
        }

        // Update Pool Manager
        if (_state.poolManager != _newState.poolManager) {
            _state.poolManager = _newState.poolManager;

            emit PoolManagerSet(_newState.poolManager);
        }

        // Update Swap Fee Module
        if (_state.swapFeeModule != _newState.swapFeeModule) {
            _state.swapFeeModule = _newState.swapFeeModule;

            emit SwapFeeModuleSet(_newState.swapFeeModule);
        }

        // Update Pool Manager Fee
        if (_newState.poolManagerFeeBips != _state.poolManagerFeeBips) {
            if (_newState.poolManagerFeeBips > MAX_POOL_MANAGER_FEE_BIPS) {
                revert StateLib__setPoolManagerFeeBips_invalidPoolManagerFee();
            } else {
                _state.poolManagerFeeBips = _newState.poolManagerFeeBips;

                emit PoolManagerFeeSet(_newState.poolManagerFeeBips);
            }
        }
    }
}
