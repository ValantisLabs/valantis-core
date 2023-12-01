// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IValantisPool } from 'src/pools/interfaces/IValantisPool.sol';

interface IUniversalPool is IValantisPool {
    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/
    function spotPriceTick() external view returns (int24);

    /************************************************
     *  OTHER FUNCTIONS
     ***********************************************/

    function addALMPosition(
        bool _isMetaALM,
        bool _isCallbackOnSwapEndRequired,
        bool _shareQuotes,
        uint64 _metaALMFeeShare,
        address _almAddress
    ) external;

    function removeALMPosition(address _almAddress) external;

    function depositLiquidity(uint256 _amount0, uint256 _amount1, bytes memory _depositData) external;

    function withdrawLiquidity(uint256 _amount0, uint256 _amount1, address _recipient) external;

    function setMetaALMFeeShare(address _almAddress, uint64 _feeShare) external;
}
