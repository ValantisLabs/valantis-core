// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IPoolDeployer } from 'src/protocol-factory/interfaces/IPoolDeployer.sol';

interface IValantisDeployer is IPoolDeployer {
    function getContractBytecode() external view returns (bytes memory);

    function protocolFactory() external view returns (address);
}
