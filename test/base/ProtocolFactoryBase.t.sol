// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ProtocolFactory } from 'src/protocol-factory/ProtocolFactory.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';

import { Base } from 'test/base/Base.sol';
import { ProtocolFactoryDeployer } from 'test/deployers/ProtocolFactoryDeployer.sol';
import { SovereignPoolFactoryDeployer } from 'test/deployers/SovereignPoolFactoryDeployer.sol';

contract ProtocolFactoryBase is Base, ProtocolFactoryDeployer, SovereignPoolFactoryDeployer {
    ProtocolFactory public protocolFactory;

    bool public isAuctionControllerInitialized;

    function setUp() public {
        _setupBase();

        protocolFactory = deployProtocolFactory();
    }

    function initiateAuctionController() external {
        assertEq(msg.sender, address(protocolFactory));

        isAuctionControllerInitialized = true;
    }

    function deploy(bytes32 /*_salt*/, bytes calldata /*_constructorArgs*/) external returns (address deployment) {
        deployment = makeAddr('GAUGE');
    }

    function _setSovereignPoolFactory() internal {
        address sovereignPoolFactory = address(deploySovereignPoolFactory());
        protocolFactory.setSovereignPoolFactory(sovereignPoolFactory);
        assertEq(protocolFactory.sovereignPoolFactory(), sovereignPoolFactory);
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
