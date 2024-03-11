// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IPoolDeployer } from '../../protocol-factory/interfaces/IPoolDeployer.sol';
import { UniversalPoolFactoryHelper } from '../libraries/UniversalPoolFactoryHelper.sol';

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
        // Salt to trigger a create2 deployment,
        // as create is prone to re-org attacks
        bytes32 salt = keccak256(abi.encode(nonce, block.chainid, _constructorArgs));

        bytes memory bytecode = abi.encodePacked(UniversalPoolFactoryHelper.getContractBytecode(), _constructorArgs);

        assembly {
            deployment := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

            if iszero(deployment) {
                revert(0, 0)
            }
        }

        nonce++;
    }
}
