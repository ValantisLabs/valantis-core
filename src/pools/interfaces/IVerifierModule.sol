// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IVerifierModule {
    /**
     * @notice Used to verify user access to important pool functions.
     * @param _user The address of the user.
     * @param _verificationContext Arbitrary bytes data which can be sent to the verifier module.
     * @param accessType The type of function being called, can be - SWAP(0), DEPOSIT(1), or WITHDRAW(2)
     * @return success True if the user is verified, false otherwise
     * @return returnData Additional data which can be passed along to the LM in case of a swap
     */
    function verify(
        address _user,
        bytes calldata _verificationContext,
        uint8 accessType
    ) external returns (bool success, bytes memory returnData);
}
