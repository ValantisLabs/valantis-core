// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IVerifierModule {
    function verify(
        address _user,
        bytes calldata _verificationContext,
        uint8 accessType
    ) external returns (bool success, bytes memory returnData);
}
