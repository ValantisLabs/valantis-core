// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { ISovereignVaultMinimal } from '../pools/interfaces/ISovereignVaultMinimal.sol';
import { ISovereignPool } from '../pools/interfaces/ISovereignPool.sol';

contract MockSovereignVault is ISovereignVaultMinimal {
    using SafeERC20 for IERC20;

    error MockSovereignVault__getReservesForPool_invalidPool();
    error MockSovereignVault__claimPoolManagerFees_onlyPool();
    error MockSovereignVault__quoteToRecipient_onlyALM();

    ISovereignPool public pool;

    address public alm;

    /**
        @dev Amount to be sent to `_recipient` on `quoteToRecipient`,
             assuming that `insufficientQuote=True`. 
     */
    uint256 public insufficientQuoteAmount;

    /**
        @dev If True, `claimPoolManagerFees` will send fees in excess. 
     */
    bool public excessFee;

    /**
        @dev If True, `quoteToRecipient` will provide `insufficientQuoteAmount`. 
     */
    bool public insufficientQuote;

    /**
        @dev If True, `getReservesForPool` will return the wrong length array. 
     */
    bool public sendInvalidReservesArray;

    /**
        @dev If True, `getReservesForPool` will return the wrong length array. 
     */
    bool public sendInvalidTokensArray;

    function setPool(address _pool) external {
        pool = ISovereignPool(_pool);
    }

    function setALM(address _alm) external {
        alm = _alm;
    }

    function toggleExcessFee(bool _state) external {
        excessFee = _state;
    }

    function toggleInsufficientQuote(bool _state) external {
        insufficientQuote = _state;
    }

    function toggleSendInvalidReservesArray(bool _state) external {
        sendInvalidReservesArray = _state;
    }

    function toggleSendInvalidTokensArray(bool _state) external {
        sendInvalidTokensArray = _state;
    }

    function getTokensForPool(address) external view override returns (address[] memory tokens) {
        if (sendInvalidTokensArray) {
            tokens = new address[](3);

            tokens[0] = pool.token0();
            tokens[1] = pool.token1();
            // Dummy token
            tokens[2] = address(0x123);
        } else {
            tokens = new address[](2);

            tokens[0] = pool.token0();
            tokens[1] = pool.token1();
        }
    }

    function getReservesForPool(
        address _pool,
        address[] calldata _tokens
    ) external view override returns (uint256[] memory) {
        if (_pool != address(pool)) revert MockSovereignVault__getReservesForPool_invalidPool();

        if (sendInvalidReservesArray) {
            uint256[] memory reserves = new uint256[](1);

            reserves[0] = 123;

            return reserves;
        } else {
            uint256[] memory reserves = new uint256[](2);

            reserves[0] = IERC20(_tokens[0]).balanceOf(address(this));
            reserves[1] = IERC20(_tokens[1]).balanceOf(address(this));

            return reserves;
        }
    }

    function quoteToRecipient(bool _isZeroToOne, uint256 _amount, address) external {
        if (msg.sender != alm) revert MockSovereignVault__quoteToRecipient_onlyALM();

        if (_amount == 0) return;

        uint256 amountOut = insufficientQuote ? insufficientQuoteAmount : _amount;

        // Approve pool to spend amountOut of tokenOut
        if (_isZeroToOne) {
            IERC20(pool.token1()).safeApprove(address(pool), amountOut);
        } else {
            IERC20(pool.token0()).safeApprove(address(pool), amountOut);
        }
    }

    function claimPoolManagerFees(uint256 _feePoolManager0, uint256 _feePoolManager1) external override {
        if (msg.sender != address(pool)) revert MockSovereignVault__claimPoolManagerFees_onlyPool();

        IERC20(pool.token0()).safeTransfer(msg.sender, excessFee ? _feePoolManager0 + 1 : _feePoolManager0);
        IERC20(pool.token1()).safeTransfer(msg.sender, excessFee ? _feePoolManager1 + 1 : _feePoolManager1);
    }
}
