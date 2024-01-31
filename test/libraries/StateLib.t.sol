// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { Math } from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';

import { PoolState } from 'src/pools/structs/UniversalPoolStructs.sol';
import { StateLib } from 'src/pools/libraries/StateLib.sol';

import { Base } from 'test/base/Base.sol';

contract StateLibTest is Base {
    /************************************************
     *  STRUCTS
     ***********************************************/

    struct ClaimPoolManagerFeeFuzzParams {
        uint256 protocolBips0;
        uint256 protocolBips1;
        uint256 feePoolManager0;
        uint256 feePoolManager1;
        uint256 feeProtocol0;
        uint256 feeProtocol1;
    }

    struct ClaimProtocolFeeFuzzParams {
        uint256 feeProtocol0;
        uint256 feeProtocol1;
    }

    struct SetPoolStateFuzzParams {
        uint8 flags;
        address currentOracle;
        uint256 poolManagerFeeBipsOld;
        uint256 poolManagerFeeBipsNew;
    }

    PoolState internal poolState;

    function setUp() public {
        _setupBase();
    }

    /************************************************
     *  Test functions
     ***********************************************/

    function test_claimPoolManagerFees(ClaimPoolManagerFeeFuzzParams memory args) public {
        args.feePoolManager0 = bound(args.feePoolManager0, 0, 1e26);
        args.feePoolManager1 = bound(args.feePoolManager1, 0, 1e26);

        args.feeProtocol0 = bound(args.feeProtocol0, 0, 1e26);
        args.feeProtocol1 = bound(args.feeProtocol1, 0, 1e26);

        poolState = PoolState(
            0,
            args.feeProtocol0,
            args.feeProtocol1,
            args.feePoolManager0,
            args.feePoolManager1,
            block.timestamp,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            ZERO_ADDRESS
        );

        uint256 feeClaimed0;
        uint256 feeClaimed1;

        if (args.protocolBips0 > 1e4 || args.protocolBips1 > 1e4) {
            vm.expectRevert(StateLib.StateLib__claimPoolManagerFees_invalidProtocolFee.selector);
            StateLib.claimPoolManagerFees(poolState, token0, token1, args.protocolBips0, args.protocolBips1);

            return;
        }

        feeClaimed0 = poolState.feePoolManager0 - Math.mulDiv(args.protocolBips0, poolState.feePoolManager0, 1e4);

        feeClaimed1 = poolState.feePoolManager1 - Math.mulDiv(args.protocolBips1, poolState.feePoolManager1, 1e4);

        _setupBalanceForUser(address(this), address(token0), feeClaimed0);
        _setupBalanceForUser(address(this), address(token1), feeClaimed1);

        if (feeClaimed0 > 0)
            vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, feeClaimed0));
        if (feeClaimed1 > 0)
            vm.expectCall(address(token1), abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, feeClaimed1));

        StateLib.claimPoolManagerFees(poolState, token0, token1, args.protocolBips0, args.protocolBips1);

        assertEq(poolState.feePoolManager0, 0);
        assertEq(poolState.feePoolManager1, 0);

        assertEq(poolState.feeProtocol0, args.feeProtocol0 + args.feePoolManager0 - feeClaimed0);
        assertEq(poolState.feeProtocol1, args.feeProtocol1 + args.feePoolManager1 - feeClaimed1);
    }

    function test_claimProtocolFees(ClaimProtocolFeeFuzzParams memory args) public {
        args.feeProtocol0 = bound(args.feeProtocol0, 0, 1e26);
        args.feeProtocol1 = bound(args.feeProtocol1, 0, 1e26);

        poolState.feeProtocol0 = args.feeProtocol0;
        poolState.feeProtocol1 = args.feeProtocol1;

        _setupBalanceForUser(address(this), address(token0), args.feeProtocol0);
        _setupBalanceForUser(address(this), address(token1), args.feeProtocol1);

        if (args.feeProtocol0 > 0)
            vm.expectCall(
                address(token0),
                abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, args.feeProtocol0)
            );
        if (args.feeProtocol1 > 0)
            vm.expectCall(
                address(token1),
                abi.encodeWithSelector(IERC20.transfer.selector, msg.sender, args.feeProtocol1)
            );

        StateLib.claimProtocolFees(poolState, token0, token1);

        assertEq(poolState.feeProtocol0, 0);
        assertEq(poolState.feeProtocol1, 0);
    }

    function test_setPoolState(SetPoolStateFuzzParams memory args) public {
        args.poolManagerFeeBipsOld = bound(args.poolManagerFeeBipsOld, 0, 5000);

        poolState.universalOracle = args.currentOracle;
        poolState.poolManager = POOL_MANAGER;
        poolState.swapFeeModule = makeAddr('SWAP_FEE_MODULE');
        poolState.poolManagerFeeBips = args.poolManagerFeeBipsOld;

        PoolState memory newState;

        newState.universalOracle = (args.flags & (1 << 1)) != 0 ? makeAddr('NEW_ORACLE') : poolState.universalOracle;
        newState.poolManager = (args.flags & (1 << 2)) != 0 ? makeAddr('NEW_MANAGER') : POOL_MANAGER;
        newState.swapFeeModule = (args.flags & (1 << 3)) != 0
            ? makeAddr('NEW_SWAP_FEE_MODULE')
            : poolState.swapFeeModule;
        newState.poolManagerFeeBips = (args.flags & (1 << 4)) != 0
            ? args.poolManagerFeeBipsNew
            : args.poolManagerFeeBipsOld;

        if (poolState.universalOracle != ZERO_ADDRESS && newState.universalOracle != poolState.universalOracle) {
            vm.expectRevert(StateLib.StateLib__setUniversalOracle_universalOracleAlreadySet.selector);
            StateLib.setPoolState(poolState, newState);
            return;
        }

        if (poolState.poolManagerFeeBips != newState.poolManagerFeeBips && newState.poolManagerFeeBips > 5000) {
            vm.expectRevert(StateLib.StateLib__setPoolManagerFeeBips_invalidPoolManagerFee.selector);
            StateLib.setPoolState(poolState, newState);
            return;
        }

        StateLib.setPoolState(poolState, newState);

        assertEq(poolState.universalOracle, newState.universalOracle);
        assertEq(poolState.poolManager, newState.poolManager);
        assertEq(poolState.swapFeeModule, newState.swapFeeModule);
        assertEq(poolState.poolManagerFeeBips, newState.poolManagerFeeBips);
    }
}
