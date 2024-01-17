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
        (address token0, address token1, address protocolFactory, address poolManager, uint256 defaultSwapFeeBips) = abi
            .decode(_constructorArgs, (address, address, address, address, uint256));

        // Salt to trigger a create2 deployment,
        // as create is prone to re-org attacks
        bytes32 salt = keccak256(abi.encode(nonce, block.chainid));
        deployment = address(
            new UniversalPool{ salt: salt }(token0, token1, protocolFactory, poolManager, defaultSwapFeeBips)
        );

        nonce++;
    }
}
