// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IFlashBorrower } from './IFlashBorrower.sol';

interface IValantisPool {
    /************************************************
     *  EVENTS
     ***********************************************/

    event Flashloan(address indexed initiator, address indexed receiver, uint256 amount, address token);

    /************************************************
     *  ERRORS
     ***********************************************/

    error ValantisPool__flashloan_callbackFailed();
    error ValantisPool__flashLoan_flashLoanDisabled();
    error ValantisPool__flashLoan_flashLoanNotRepaid();
    error ValantisPool__flashLoan_rebaseTokenNotAllowed();

    /************************************************
     *  VIEW FUNCTIONS
     ***********************************************/

    /**
        @notice Address of ERC20 token0 of the pool.
     */
    function token0() external view returns (address);

    /**
        @notice Address of ERC20 token1 of the pool.
     */
    function token1() external view returns (address);

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Claim share of protocol fees accrued by this pool.
        @dev Can only be claimed by `gauge` of the pool. 
     */
    function claimProtocolFees() external returns (uint256, uint256);

    /**
        @notice Claim share of fees accrued by this pool
                And optionally share some with the protocol.
        @dev Only callable by `poolManager`.
        @param _feeProtocol0Bips Percent of `token0` fees to be shared with protocol.
        @param _feeProtocol1Bips Percent of `token1` fees to be shared with protocol.
     */
    function claimPoolManagerFees(
        uint256 _feeProtocol0Bips,
        uint256 _feeProtocol1Bips
    ) external returns (uint256 feePoolManager0Received, uint256 feePoolManager1Received);

    /**
        @notice Sets the gauge contract address for the pool.
        @dev Only callable by `protocolFactory`.
        @dev Once a gauge is set it cannot be changed again.
        @param _gauge address of the gauge.
     */
    function setGauge(address _gauge) external;

    /**
        @notice Allows anyone to flash loan any amount of tokens from the pool.
        @param _isTokenZero True if token0 is being flash loaned, False otherwise.
        @param _receiver Address of the flash loan receiver.
        @param _amount Amount of tokens to be flash loaned.
        @param _data Bytes encoded data for flash loan callback.
     */
    function flashLoan(bool _isTokenZero, IFlashBorrower _receiver, uint256 _amount, bytes calldata _data) external;
}
