// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IValantisDeployer } from 'src/protocol-factory/interfaces/IValantisDeployer.sol';
import { ConstantSwapFeeModule } from 'src/swap-fee-modules/ConstantSwapFeeModule.sol';

contract ConstantSwapFeeModuleFactory is IValantisDeployer {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error ConstantSwapFeeModuleFactory__deploy_invalidDeployer();

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

    function getCreate2Address(
        bytes32 _salt,
        bytes calldata _constructorArgs
    ) external view override returns (address) {
        bool hasConstructorArgs = keccak256(_constructorArgs) != keccak256(new bytes(0));

        bytes32 create2Hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                _salt,
                keccak256(
                    hasConstructorArgs
                        ? abi.encodePacked(type(ConstantSwapFeeModule).creationCode, _constructorArgs)
                        : type(ConstantSwapFeeModule).creationCode
                )
            )
        );

        return address(uint160(uint256(create2Hash)));
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external override returns (address deployment) {
        if (msg.sender != protocolFactory) {
            revert ConstantSwapFeeModuleFactory__deploy_invalidDeployer();
        }

        (address pool, uint256 swapFeeBips, address feeModuleManager) = abi.decode(
            _constructorArgs,
            (address, uint256, address)
        );
        deployment = address(new ConstantSwapFeeModule{ salt: _salt }(pool, swapFeeBips, feeModuleManager));
    }
}
