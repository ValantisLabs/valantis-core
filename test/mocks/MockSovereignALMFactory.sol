// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IValantisDeployer } from 'src/protocol-factory/interfaces/IValantisDeployer.sol';

import { MockSovereignALM } from 'test/mocks/MockSovereignALM.sol';

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

    function getContractBytecode() external pure override returns (bytes memory) {
        return type(MockSovereignALM).creationCode;
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external override returns (address deployment) {
        if (msg.sender != protocolFactory) {
            revert MockSovereignALMFactory__deploy_invalidDeployer();
        }

        address pool = abi.decode(_constructorArgs, (address));
        deployment = address(new MockSovereignALM{ salt: _salt }(pool));
    }
}
