// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IPoolGaugeDeployer {
    /**
     * @notice Deploys a new pool gauge.
     * @param _salt The salt to use for deployment.
     * @param _constructorArgs The arguments to pass to the pool gauge constructor.
     * @return deployment The address of the deployed pool gauge.
     */
    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external returns (address deployment);
}
