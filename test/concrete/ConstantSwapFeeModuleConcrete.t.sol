// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { ConstantSwapFeeModule } from 'src/swap-fee-modules/ConstantSwapFeeModule.sol';
import { SwapFeeModuleData } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';
import { ConstantSwapFeeModuleFactory } from 'src/swap-fee-modules/factories/ConstantSwapFeeModuleFactory.sol';

import { ConstantSwapFeeModuleBase } from 'test/base/ConstantSwapFeeModuleBase.t.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';

contract ConstantSwapFeeModuleConcrete is ConstantSwapFeeModuleBase {
    function test_constructorArgs() public {
        // should not deploy more than allowed
        vm.expectRevert(ConstantSwapFeeModule.ConstantSwapFeeModule__invalidSwapFeeBips.selector);
        deployConstantSwapFeeModule(protocolFactory, address(factory), address(pool), POOL_MANAGER, 10_001);

        swapFeeModule = deployConstantSwapFeeModule(
            protocolFactory,
            address(factory),
            address(pool),
            POOL_MANAGER,
            100
        );

        assertEq(swapFeeModule.feeModuleManager(), POOL_MANAGER);
        assertEq(swapFeeModule.pool(), address(pool));
        assertEq(swapFeeModule.swapFeeBips(), 100);
    }

    function test_setFeeModuleManager() public {
        address newManager = _randomUser();

        vm.expectRevert(ConstantSwapFeeModule.ConstantSwapFeeModule__onlyFeeModuleManager.selector);
        swapFeeModule.setFeeModuleManager(newManager);

        vm.prank(POOL_MANAGER);
        swapFeeModule.setFeeModuleManager(newManager);

        assertEq(swapFeeModule.feeModuleManager(), newManager);
    }

    function test_setSwapFeeBips() public {
        uint256 swapFeeBips = 10_001;

        vm.expectRevert(ConstantSwapFeeModule.ConstantSwapFeeModule__onlyFeeModuleManager.selector);
        swapFeeModule.setSwapFeeBips(swapFeeBips);

        vm.prank(POOL_MANAGER);
        vm.expectRevert(ConstantSwapFeeModule.ConstantSwapFeeModule__invalidSwapFeeBips.selector);
        swapFeeModule.setSwapFeeBips(swapFeeBips);

        swapFeeBips = 100;

        vm.prank(POOL_MANAGER);
        swapFeeModule.setSwapFeeBips(swapFeeBips);

        assertEq(swapFeeModule.swapFeeBips(), swapFeeBips);
    }

    function test_getSwapFeeInBips() public {
        vm.prank(POOL_MANAGER);
        swapFeeModule.setSwapFeeBips(100);

        vm.expectRevert(ConstantSwapFeeModule.ConstantSwapFeeModule__onlyPool.selector);
        swapFeeModule.getSwapFeeInBips(ZERO_ADDRESS, ZERO_ADDRESS, 0, ZERO_ADDRESS, new bytes(0));

        vm.prank(address(pool));
        SwapFeeModuleData memory feeData = swapFeeModule.getSwapFeeInBips(
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            0,
            ZERO_ADDRESS,
            new bytes(0)
        );

        assertEq(feeData.feeInBips, 100);
        assertEq(feeData.internalContext, new bytes(0));
    }

    function test_callback() public {
        vm.prank(address(pool));
        swapFeeModule.callbackOnSwapEnd(0, 0, 0, 0, SwapFeeModuleData(0, new bytes(0)));

        vm.prank(address(pool));
        swapFeeModule.callbackOnSwapEnd(0, 0, 0, SwapFeeModuleData(0, new bytes(0)));
    }

    function test_factoryError() public {
        vm.expectRevert(ConstantSwapFeeModuleFactory.ConstantSwapFeeModuleFactory__deploy_invalidDeployer.selector);
        factory.deploy(bytes32(uint256(1000)), abi.encode(address(pool), POOL_MANAGER, 0));

        vm.prank(address(protocolFactory));
        factory.deploy(bytes32(uint256(1000)), abi.encode(address(pool), POOL_MANAGER, 0));
    }
}
