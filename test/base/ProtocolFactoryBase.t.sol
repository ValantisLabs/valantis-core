// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ProtocolFactory } from '../../src/protocol-factory/ProtocolFactory.sol';
import { SovereignPoolConstructorArgs } from '../../src/pools/structs/SovereignPoolStructs.sol';

import { Base } from '../base/Base.sol';
import { ProtocolFactoryDeployer } from '../deployers/ProtocolFactoryDeployer.sol';
import { SovereignPoolFactoryDeployer } from '../deployers/SovereignPoolFactoryDeployer.sol';
import { UniversalPoolFactoryDeployer } from '../deployers/UniversalPoolFactoryDeployer.sol';

contract ProtocolFactoryBase is
    Base,
    ProtocolFactoryDeployer,
    SovereignPoolFactoryDeployer,
    UniversalPoolFactoryDeployer
{
    ProtocolFactory public protocolFactory;

    bool public isAuctionControllerInitialized;

    bool public isDeployment;

    bool public create2AddressWithContract;

    function setUp() public {
        _setupBase();

        protocolFactory = deployProtocolFactory();
    }

    function setIsDeployment(bool _isDeployment) public {
        isDeployment = _isDeployment;
    }

    function setCreate2AddressWithContract(bool _create2AddressWithContract) public {
        create2AddressWithContract = _create2AddressWithContract;
    }

    function getCreate2Address(bytes32 _salt, bytes calldata _constructorArgs) external view returns (address) {
        if (create2AddressWithContract) {
            return address(this);
        } else {
            bool hasConstructorArgs = keccak256(_constructorArgs) != keccak256(new bytes(0));

            if (!hasConstructorArgs) revert('ProtocolFactoryBase: Only tests with non-empty constructor args');

            bytes32 create2Hash = keccak256(
                abi.encodePacked(
                    bytes1(0xff),
                    address(this),
                    _salt,
                    keccak256(abi.encodePacked(type(ProtocolFactory).creationCode, _constructorArgs))
                )
            );

            return address(uint160(uint256(create2Hash)));
        }
    }

    function initiateAuctionController() external {
        assertEq(msg.sender, address(protocolFactory));

        isAuctionControllerInitialized = true;
    }

    function deploy(bytes32 _salt, bytes calldata _constructorArgs) external returns (address deployment) {
        assertEq(msg.sender, address(protocolFactory));

        if (!isDeployment) return makeAddr('NO_CONTRACT_DEPLOYMENT');

        address protocolDeployer = abi.decode(_constructorArgs, (address));

        deployment = address(new ProtocolFactory{ salt: _salt }(protocolDeployer));
    }

    function _setSovereignPoolFactory() internal {
        address sovereignPoolFactory = address(deploySovereignPoolFactory());
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);
        assertEq(protocolFactory.sovereignPoolFactory(), sovereignPoolFactory);
    }

    function _setUniversalPoolFactory() internal {
        address universalPoolFactory = address(deployUniversalPoolFactory());
        protocolFactory.setUniversalPoolFactory(universalPoolFactory);
        assertEq(protocolFactory.universalPoolFactory(), universalPoolFactory);
    }

    function _generateSovereignPoolDeploymentArgs(
        address token0_,
        address token1_,
        address poolManager
    ) internal view returns (SovereignPoolConstructorArgs memory) {
        SovereignPoolConstructorArgs memory args = SovereignPoolConstructorArgs({
            token0: token0_,
            token1: token1_,
            protocolFactory: address(protocolFactory),
            poolManager: poolManager,
            sovereignVault: address(0),
            verifierModule: address(0),
            isToken0Rebase: false,
            isToken1Rebase: false,
            token0AbsErrorTolerance: 0,
            token1AbsErrorTolerance: 0,
            defaultSwapFeeBips: 0
        });

        return args;
    }
}
