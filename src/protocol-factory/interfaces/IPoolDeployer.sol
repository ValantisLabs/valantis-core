// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IPoolDeployer {
    /**
        @notice Deploys a new pool.
        @param _salt The salt to use for deployment.
        @param _constructorArgs The arguments to pass to the pool constructor.
        @return deployment The address of the deployed pool.
     */
    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external returns (address deployment);
}
