// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { Slot0, ALMPosition, ALMStatus, PoolState, SwapParams } from '../structs/UniversalPoolStructs.sol';
import { IValantisPool } from '../interfaces/IValantisPool.sol';
import { PoolLocks } from '../structs/ReentrancyGuardStructs.sol';
import { ALMReserves } from '../../ALM/structs/UniversalALMStructs.sol';

interface IUniversalPool is IValantisPool {
    /************************************************
     *  EVENTS
     ***********************************************/

    event Swap(address indexed user, uint256 amountIn, uint256 amountOut, bool isZeroToOne);
    event GaugeSet(address gauge);
    event InitializeTick(int24 tick);

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/

    function spotPriceTick() external view returns (int24);

    function state() external view returns (PoolState memory);

    function getALMReserves(address _almPositionAddress, bool _isZeroToOne) external view returns (ALMReserves memory);

    function getALMPositionsList() external view returns (ALMPosition[] memory);

    function getPoolLockStatus() external view returns (PoolLocks memory);

    function getALMPositionAtAddress(
        address _almPositionAddress
    ) external view returns (ALMStatus status, ALMPosition memory);

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function addALMPosition(
        bool _isMetaALM,
        bool _isCallbackOnSwapEndRequired,
        bool _shareQuotes,
        uint64 _metaALMFeeShare,
        address _almAddress
    ) external;

    function removeALMPosition(address _almAddress) external;

    function setPoolState(PoolState memory newState) external;

    function swap(SwapParams calldata _swapParams) external returns (uint256, uint256);

    function depositLiquidity(uint256 _amount0, uint256 _amount1, bytes memory _depositData) external;

    function withdrawLiquidity(uint256 _amount0, uint256 _amount1, address _recipient) external;

    function initializeTick(int24 _tick) external;

    function setMetaALMFeeShare(address _almAddress, uint64 _feeShare) external;
}
