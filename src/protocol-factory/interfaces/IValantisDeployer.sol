// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { IPoolDeployer } from './IPoolDeployer.sol';

/**
    @notice Valantis Deployer Factory interfaces.
    @dev All factory contracts whitelisted in ProtocolFactory should implement it.
 */
interface IValantisDeployer is IPoolDeployer {
    /**
        @notice Returns create2 address of a contract deployed with `_constructorArgs`.
        @param _salt Create2 salt, to be determined by ProtocolFactory.
        @param _constructorArgs Abi encoded constructor arguments.
        @dev If there are no constructor args, caller should pass an empty bytes payload. 
     */
    function getCreate2Address(bytes32 _salt, bytes calldata _constructorArgs) external view returns (address);

    /**
        @notice Returns address of Protocol Factory. 
     */
    function protocolFactory() external view returns (address);
}
