// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IValantisDeployer } from '../protocol-factory/interfaces/IValantisDeployer.sol';
import { MockUniversalALM } from './MockUniversalALM.sol';

contract MockUniversalALMFactory is IValantisDeployer {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error MockUniversalALMFactory__deploy_invalidDeployer();

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    address public immutable protocolFactory;

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(address _protocolFactory) {
        protocolFactory = _protocolFactory;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    function getCreate2Address(bytes32 _salt, bytes calldata _constructorArgs) external view returns (address) {
        bool hasConstructorArgs = keccak256(_constructorArgs) != keccak256(new bytes(0));

        bytes32 create2Hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(
                    hasConstructorArgs
                        ? abi.encodePacked(type(MockUniversalALM).creationCode, _constructorArgs)
                        : type(MockUniversalALM).creationCode
                )
            )
        );

        return address(uint160(uint256(create2Hash)));
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external override returns (address deployment) {
        if (msg.sender != protocolFactory) {
            revert MockUniversalALMFactory__deploy_invalidDeployer();
        }

        (address pool, bool isMetaALM) = abi.decode(_constructorArgs, (address, bool));
        deployment = address(new MockUniversalALM{ salt: _salt }(pool, isMetaALM));
    }
}
