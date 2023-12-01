// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

interface IPoolGaugeDeployer {
    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external returns (address deployment);
}
