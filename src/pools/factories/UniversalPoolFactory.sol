// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IPoolDeployer } from '../../protocol-factory/interfaces/IPoolDeployer.sol';
import { UniversalPool } from '../UniversalPool.sol';

contract UniversalPoolFactory is IPoolDeployer {
    /************************************************
     *  STORAGE
     ***********************************************/

    /**
        @notice Nonce used to derive unique CREATE2 salts. 
     */
    uint256 public nonce;

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function deploy(bytes32, bytes calldata _constructorArgs) external override returns (address deployment) {
        // AUDIT
        // NOTE: We don't need to check if the sender of deploy is protocolFactory
        // As there is nothing harmful that a person can do by deploying a new pool

        (address token0, address token1, address protocolFactory, address poolManager, uint256 defaultSwapFeeBips) = abi
            .decode(_constructorArgs, (address, address, address, address, uint256));

        // Salt to trigger a create2 deployment,
        // as create is prone to re-org attacks
        bytes32 salt = keccak256(abi.encode(nonce));
        deployment = address(
            new UniversalPool{ salt: salt }(token0, token1, protocolFactory, poolManager, defaultSwapFeeBips)
        );

        nonce++;
    }
}
