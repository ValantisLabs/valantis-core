// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { IValantisDeployer } from '../protocol-factory/interfaces/IValantisDeployer.sol';
import { MockSovereignALM } from './MockSovereignALM.sol';

contract MockSovereignALMFactory is IValantisDeployer {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error MockSovereignALMFactory__deploy_invalidDeployer();

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
                        ? abi.encodePacked(type(MockSovereignALM).creationCode, _constructorArgs)
                        : type(MockSovereignALM).creationCode
                )
            )
        );

        return address(uint160(uint256(create2Hash)));
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external override returns (address deployment) {
        if (msg.sender != protocolFactory) {
            revert MockSovereignALMFactory__deploy_invalidDeployer();
        }

        address pool = abi.decode(_constructorArgs, (address));
        deployment = address(new MockSovereignALM{ salt: _salt }(pool));
    }
}
