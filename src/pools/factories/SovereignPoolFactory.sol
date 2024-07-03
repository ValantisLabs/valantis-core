// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IPoolDeployer } from '../../protocol-factory/interfaces/IPoolDeployer.sol';

import { SovereignPool } from '../SovereignPool.sol';
import { SovereignPoolConstructorArgs } from '../structs/SovereignPoolStructs.sol';

contract SovereignPoolFactory is IPoolDeployer {
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
        SovereignPoolConstructorArgs memory args = abi.decode(_constructorArgs, (SovereignPoolConstructorArgs));

        // Salt to trigger a create2 deployment,
        // as create is prone to re-org attacks
        bytes32 salt = keccak256(abi.encode(nonce, block.chainid, _constructorArgs));
        deployment = address(new SovereignPool{ salt: salt }(args));

        nonce++;
    }
}
