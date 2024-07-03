// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IFlashBorrower {
    /**
        @dev Receive a flash loan.
        @param initiator The initiator of the loan.
        @param token The loan currency.
        @param amount The amount of tokens lent.
        @param data Arbitrary data structure, intended to contain user-defined parameters.
        @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes32);
}
