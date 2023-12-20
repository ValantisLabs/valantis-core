// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { Test } from 'forge-std/Test.sol';
import { ERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { MockRebaseToken } from 'test/mocks/MockRebaseToken.sol';

contract Base is Test {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    address internal ZERO_ADDRESS = address(0);
    address internal DUMP_ADDRESS = makeAddr('DUMP_ADDRESS');

    address internal POOL_MANAGER = makeAddr('POOL_MANAGER');

    address[] internal signers;
    address[] internal contractToApprove;

    ERC20 internal token0;
    ERC20 internal token1;

    fallback() external {}

    function _setupBase() internal {
        token0 = new ERC20('Token 0', 'TOKEN0');
        token1 = new ERC20('Token 1', 'TOKEN1');

        signers.push(makeAddr('USER 1'));
        signers.push(makeAddr('USER 2'));
        signers.push(makeAddr('USER 3'));
        signers.push(makeAddr('USER 4'));
        signers.push(makeAddr('USER 5'));
        signers.push(makeAddr('USER 6'));
        signers.push(makeAddr('USER 7'));
        signers.push(makeAddr('USER 8'));
        signers.push(makeAddr('USER 9'));
        signers.push(makeAddr('USER 10'));
    }

    function _deployRebaseToken(bool isTokenZero) internal {
        if (isTokenZero) {
            token0 = ERC20(new MockRebaseToken('Token 0', 'TOKEN0'));
        } else {
            token1 = ERC20(new MockRebaseToken('TOKEN 1', 'TOKEN1'));
        }
    }

    function _randomUser() internal view returns (address user) {
        user = signers[gasleft() % signers.length];
    }

    function _addToContractsToApprove(address addr) internal {
        contractToApprove.push(addr);
    }

    function _setupBalanceForUser(address user, address token, uint256 amount) internal {
        if (token == ZERO_ADDRESS) {
            vm.deal(user, amount);
        } else {
            deal(token, user, amount);
            _approveForUser(user, token);
        }
    }

    function _setZeroBalance(address user, ERC20 token) internal {
        uint256 amount = token.balanceOf(user);
        vm.prank(user);
        token.safeTransfer(DUMP_ADDRESS, amount);
    }

    function _approveForUser(address user, address token) internal {
        uint256 approvalsLength = contractToApprove.length;

        vm.startPrank(user);

        for (uint i; i < approvalsLength; i++) {
            if (user == contractToApprove[i] || IERC20(token).allowance(user, contractToApprove[i]) > 0) {
                continue;
            }
            // Not using safeApprove because of issues with prank
            IERC20(token).approve(contractToApprove[i], type(uint256).max);
        }

        vm.stopPrank();
    }

    function _assertTokenBalance(ERC20 token, address recipient, uint256 expectedAmount) internal {
        assertEq(token.balanceOf(recipient), expectedAmount);
    }
}
