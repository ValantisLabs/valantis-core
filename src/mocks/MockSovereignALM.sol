// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { Math } from '../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol';
import { SafeERC20 } from '../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { ISovereignALM } from '../ALM/interfaces/ISovereignALM.sol';
import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from '../ALM/structs/SovereignALMStructs.sol';
import { ISovereignPool } from '../pools/interfaces/ISovereignPool.sol';
import { MockSovereignVault } from './MockSovereignVault.sol';

contract MockSovereignALM is ISovereignALM {
    using SafeERC20 for IERC20;

    error MockSovereignALM__onlyPool();
    error MockSovereignALM__depositLiquidity_zeroTotalDepositAmount();
    error MockSovereignALM__depositLiquidity_notPermissioned();

    event LogSwapCallback(bool isZeroToOne);

    address public immutable pool;

    bool public quoteExcessAmountIn = false;
    bool public quoteExcessAmountOut = false;
    bool public quoteFromPool = true;
    bool public quotePartialFill = false;
    bool public quoteToRecipientInExcess = false;
    bool public swapCallback = false;

    address public recipient = address(0);

    uint256 public fee0;
    uint256 public fee1;

    MockSovereignVault public sovereignVault;

    ALMLiquidityQuote public cacheLiquidityQuote;

    constructor(address _pool) {
        pool = _pool;
    }

    modifier onlyPool() {
        if (msg.sender != pool) {
            revert MockSovereignALM__onlyPool();
        }
        _;
    }

    function setSovereignVault() external {
        sovereignVault = MockSovereignVault(ISovereignPool(pool).sovereignVault());
    }

    function setLiquidityQuote(ALMLiquidityQuote memory _almLiquidityQuote) external {
        cacheLiquidityQuote = _almLiquidityQuote;
    }

    function setQuoteFromPool(bool _quoteFromPool) external {
        quoteFromPool = _quoteFromPool;
    }

    function setQuoteExcessAmountIn(bool _quoteExcessAmountIn) external {
        quoteExcessAmountIn = _quoteExcessAmountIn;
    }

    function setQuoteExcessAmountOut(bool _quoteExcessAmountOut) external {
        quoteExcessAmountOut = _quoteExcessAmountOut;
    }

    function setQuotePartialFill(bool _quotePartialFill) external {
        quotePartialFill = _quotePartialFill;
    }

    function setQuoteToRecipientInExcess(bool _quoteToRecipientInExcess) external {
        quoteToRecipientInExcess = _quoteToRecipientInExcess;
    }

    function setSwapCallback(bool _swapCallback) external {
        swapCallback = _swapCallback;
    }

    function setRecipient(address _recipient) external {
        recipient = _recipient;
    }

    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _verificationContext
    ) external returns (uint256 amount0Deposited, uint256 amount1Deposited) {
        (amount0Deposited, amount1Deposited) = ISovereignPool(pool).depositLiquidity(
            _amount0,
            _amount1,
            msg.sender,
            _verificationContext,
            abi.encode(msg.sender)
        );
    }

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        uint256,
        uint256,
        address _recipient,
        bytes memory _verificationContext
    ) external {
        ISovereignPool(pool).withdrawLiquidity(_amount0, _amount1, msg.sender, _recipient, _verificationContext);
    }

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory _almLiquidityQuotePoolInput,
        bytes calldata,
        bytes calldata
    ) external override onlyPool returns (ALMLiquidityQuote memory) {
        if (_almLiquidityQuotePoolInput.amountInMinusFee == 0) {
            ALMLiquidityQuote memory emptyQuote;
            return emptyQuote;
        }

        uint256 reserveIn;
        uint256 reserveOut;

        (uint256 reserve0, uint256 reserve1) = ISovereignPool(pool).getReserves();

        reserveIn = _almLiquidityQuotePoolInput.isZeroToOne ? reserve0 : reserve1;
        reserveOut = _almLiquidityQuotePoolInput.isZeroToOne ? reserve1 : reserve0;

        uint256 amountOutExpected = quoteExcessAmountOut
            ? type(uint256).max
            : reserveOut - Math.mulDiv(reserve0, reserve1, reserveIn + _almLiquidityQuotePoolInput.amountInMinusFee);

        ALMLiquidityQuote memory almLiquidityQuote = ALMLiquidityQuote(
            swapCallback,
            amountOutExpected,
            quoteExcessAmountIn
                ? _almLiquidityQuotePoolInput.amountInMinusFee + 1
                : _almLiquidityQuotePoolInput.amountInMinusFee
        );

        if (quotePartialFill) {
            almLiquidityQuote.amountInFilled = _almLiquidityQuotePoolInput.amountInMinusFee / 2;
            almLiquidityQuote.amountOut = quoteExcessAmountOut
                ? type(uint256).max
                : reserveOut - Math.mulDiv(reserve0, reserve1, reserveIn + almLiquidityQuote.amountInFilled);
        }

        if (address(sovereignVault) != pool) {
            sovereignVault.quoteToRecipient(
                _almLiquidityQuotePoolInput.isZeroToOne,
                amountOutExpected,
                _almLiquidityQuotePoolInput.recipient
            );
        }

        uint256 feeMax = Math.mulDiv(
            _almLiquidityQuotePoolInput.amountInMinusFee,
            1e4 + _almLiquidityQuotePoolInput.feeInBips,
            1e4,
            Math.Rounding.Up
        ) - _almLiquidityQuotePoolInput.amountInMinusFee;
        uint256 feeAmount = feeMax - Math.mulDiv(feeMax, ISovereignPool(pool).poolManagerFeeBips(), 1e4);
        _almLiquidityQuotePoolInput.isZeroToOne ? (fee0 += feeAmount) : (fee1 += feeAmount);

        return almLiquidityQuote;
    }

    function onDepositLiquidityCallback(
        uint256 _amount0,
        uint256 _amount1,
        bytes memory _data
    ) external override onlyPool {
        address user = abi.decode(_data, (address));

        (address token0, address token1) = (ISovereignPool(pool).token0(), ISovereignPool(pool).token1());

        if (_amount0 > 0) {
            IERC20(token0).safeTransferFrom(user, msg.sender, _amount0);
        }

        if (_amount1 > 0) {
            IERC20(token1).safeTransferFrom(user, msg.sender, _amount1);
        }
    }

    function onSwapCallback(bool _isZeroToOne, uint256, uint256) external override onlyPool {
        // Changes recipient's balance to an unexpected amount
        if (quoteToRecipientInExcess) {
            (address token0, address token1) = (ISovereignPool(pool).token0(), ISovereignPool(pool).token1());

            if (_isZeroToOne) {
                IERC20(token1).safeTransfer(recipient, 123);
            } else {
                IERC20(token0).safeTransfer(recipient, 123);
            }
        }

        emit LogSwapCallback(_isZeroToOne);
    }
}
