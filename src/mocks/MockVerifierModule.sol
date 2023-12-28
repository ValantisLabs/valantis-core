// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IVerifierModule } from 'src/pools/interfaces/IVerifierModule.sol';

contract MockVerifierModule is IVerifierModule {
    /************************************************
     *  CONSTANTS
     ***********************************************/

    address constant SWAP_USER = address(uint160(uint256(keccak256(abi.encode('SWAP_USER')))));
    address constant DEPOSIT_USER = address(uint160(uint256(keccak256(abi.encode('DEPOSIT_USER')))));

    /************************************************
     *  ENUMS
     ***********************************************/

    enum AccessType {
        SWAP,
        DEPOSIT,
        WITHDRAW
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function verify(
        address _user,
        bytes calldata data,
        uint8 accessType
    ) external pure override returns (bool success, bytes memory returnData) {
        if (accessType == uint8(AccessType.SWAP) && _user == SWAP_USER) {
            return (true, new bytes(0));
        }
        string memory depositUser = 'DEPOSIT_USER';
        if (keccak256(data) == keccak256(abi.encode(depositUser)) && accessType == uint8(AccessType.DEPOSIT)) {
            return (true, new bytes(0));
        }

        if (accessType == uint8(AccessType.DEPOSIT) && _user == DEPOSIT_USER) {
            return (true, new bytes(0));
        }

        string memory withdrawUser = 'WITHDRAW_USER';
        if (keccak256(data) == keccak256(abi.encode(withdrawUser)) && accessType == uint8(AccessType.WITHDRAW)) {
            return (true, new bytes(0));
        }

        return (false, new bytes(0));
    }
}
