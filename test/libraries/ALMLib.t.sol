// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { Math } from 'lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';

import { EnumerableALMMap } from 'src/libraries/EnumerableALMMap.sol';
import { ALMLib } from 'src/pools/libraries/ALMLib.sol';
import { ALMPosition, ALMStatus, Slot0 } from 'src/pools/structs/UniversalPoolStructs.sol';

import { Base } from 'test/base/Base.sol';

contract ALMLibTest is Base {
    using EnumerableALMMap for EnumerableALMMap.ALMSet;

    /************************************************
     *  STRUCTS
     ***********************************************/

    struct DepositLiquidityFuzzParams {
        uint256 amount0;
        uint256 amount1;
        uint256 preReserve0;
        uint256 preReserve1;
    }

    struct WithdrawLiquidityFuzzParams {
        uint256 amount0;
        uint256 amount1;
        uint256 preReserve0;
        uint256 preReserve1;
    }

    EnumerableALMMap.ALMSet internal _ALMPositions;

    function setUp() public {
        _setupBase();

        _ALMPositions.add(ALMPosition(Slot0(false, false, false, 0, address(this)), 0, 0, 0, 0));
    }

    /************************************************
     *  Test functions
     ***********************************************/

    function test_depositLiquidity(DepositLiquidityFuzzParams memory args) public {
        args.amount0 = bound(args.amount0, 1, 1e26);
        args.amount1 = bound(args.amount1, 1, 1e26);
        args.preReserve0 = bound(args.preReserve0, 0, 1e26);
        args.preReserve1 = bound(args.preReserve1, 0, 1e26);

        _updateReserves(args.preReserve0, args.preReserve1);

        vm.expectRevert(ALMLib.ALMLib__depositLiquidity_zeroAmounts.selector);
        this.depositLiquidity(0, 0, abi.encode(args.amount0, args.amount1));

        vm.expectRevert(ALMLib.ALMLib__depositLiquidity_insufficientTokenAmount.selector);
        this.depositLiquidity(args.amount0, args.amount1, abi.encode(args.amount0 + 1, args.amount1 + 1));

        vm.expectCall(
            address(this),
            abi.encodeWithSelector(
                this.onDepositLiquidityCallback.selector,
                args.amount0,
                args.amount1,
                abi.encode(args.amount0, args.amount1)
            )
        );

        uint256 preBalance0 = token0.balanceOf(address(this));
        uint256 preBalance1 = token1.balanceOf(address(this));

        this.depositLiquidity(args.amount0, args.amount1, abi.encode(args.amount0, args.amount1));

        (, ALMPosition memory almPosition) = _ALMPositions.getALM(address(this));

        assertEq(almPosition.reserve0, args.preReserve0 + args.amount0);
        assertEq(almPosition.reserve1, args.preReserve1 + args.amount1);

        assertEq(preBalance0, token0.balanceOf(address(this)) - args.amount0);
        assertEq(preBalance1, token1.balanceOf(address(this)) - args.amount1);
    }

    function test_withdrawLiquidity(WithdrawLiquidityFuzzParams memory args) public {
        args.amount0 = bound(args.amount0, 0, 1e26);
        args.amount1 = bound(args.amount1, 0, 1e26);
        args.preReserve0 = bound(args.preReserve0, 0, 1e26);
        args.preReserve1 = bound(args.preReserve1, 0, 1e26);

        address USER = _randomUser();

        _updateReserves(args.preReserve0, args.preReserve1);

        if (args.amount0 > args.preReserve0 || args.amount1 > args.preReserve1) {
            vm.expectRevert(ALMLib.ALMLib__withdrawLiquidity_insufficientReserves.selector);
            this.withdrawLiquidity(args.amount0, args.amount1, USER);
            return;
        }

        if (args.amount0 > 0)
            vm.expectCall(address(token0), abi.encodeWithSelector(IERC20.transfer.selector, USER, args.amount0));
        if (args.amount1 > 0)
            vm.expectCall(address(token1), abi.encodeWithSelector(IERC20.transfer.selector, USER, args.amount1));

        this.withdrawLiquidity(args.amount0, args.amount1, USER);

        (, ALMPosition memory almPosition) = _ALMPositions.getALM(address(this));

        assertEq(almPosition.reserve0, args.preReserve0 - args.amount0);
        assertEq(almPosition.reserve1, args.preReserve1 - args.amount1);
    }

    /************************************************
     *  External functions
     ***********************************************/

    function onDepositLiquidityCallback(uint256, uint256, bytes memory depositData) external {
        assertEq(msg.sender, address(this));
        address USER = _randomUser();

        (uint256 balanceDelta0, uint256 balanceDelta1) = abi.decode(depositData, (uint256, uint256));

        _setupBalanceForUser(USER, address(token0), balanceDelta0);
        _setupBalanceForUser(USER, address(token1), balanceDelta1);

        address recipient = address(this);

        vm.prank(USER);
        token0.transfer(recipient, balanceDelta0);

        vm.prank(USER);
        token1.transfer(recipient, balanceDelta1);
    }

    function depositLiquidity(uint256 amount0, uint256 amount1, bytes memory depositData) external {
        ALMLib.depositLiquidity(_ALMPositions, token0, token1, amount0, amount1, depositData);
    }

    function withdrawLiquidity(uint256 amount0, uint256 amount1, address recipient) external {
        ALMLib.withdrawLiquidity(_ALMPositions, token0, token1, amount0, amount1, recipient);
    }

    /************************************************
     *  Internal functions
     ***********************************************/

    function _updateReserves(uint256 reserve0, uint256 reserve1) internal {
        (, ALMPosition storage almPosition) = _ALMPositions.getALM(address(this));

        almPosition.reserve0 = reserve0;
        almPosition.reserve1 = reserve1;

        _setupBalanceForUser(address(this), address(token0), reserve0);
        _setupBalanceForUser(address(this), address(token1), reserve1);
    }
}
