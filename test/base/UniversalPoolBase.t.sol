// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { UniversalPool } from 'src/pools/UniversalPool.sol';
import { ProtocolFactory } from 'src/protocol-factory/ProtocolFactory.sol';
import { PoolState } from 'src/pools/structs/UniversalPoolStructs.sol';
import {
    ALMLiquidityQuotePoolInputs,
    ALMReserves,
    ALMLiquidityQuote,
    ALMCachedLiquidityQuote
} from 'src/ALM/structs/UniversalALMStructs.sol';
import { PoolLocks, Lock } from 'src/pools/structs/ReentrancyGuardStructs.sol';
import { SwapFeeModuleData } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { Base } from 'test/base/Base.sol';
import { UniversalPoolDeployer } from 'test/deployers/UniversalPoolDeployer.sol';

contract UniversalPoolBase is UniversalPoolDeployer, Base {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    UniversalPool internal pool;
    ProtocolFactory internal protocolFactory;

    function setUp() public virtual {
        _setupBase();

        pool = deployUniversalPool(address(token0), address(token1), POOL_MANAGER, 0);

        protocolFactory = ProtocolFactory(pool.protocolFactory());

        _addToContractsToApprove(address(pool));
    }

    // swap function for ALM
    function setupSwap(
        ALMLiquidityQuotePoolInputs memory,
        address,
        uint256,
        ALMReserves memory,
        bytes calldata externalContext
    ) external returns (bool isParticipatingInSwap, bool refreshReserves, ALMLiquidityQuote memory swapSetupQuote) {
        uint256 amount0;
        uint256 amount1;
        (isParticipatingInSwap, refreshReserves, amount0, amount1, swapSetupQuote) = abi.decode(
            externalContext,
            (bool, bool, uint256, uint256, ALMLiquidityQuote)
        );

        PoolLocks memory poolLockStatus = pool.getPoolLockStatus();

        assertEq(poolLockStatus.withdrawals.value, 2);
        assertEq(poolLockStatus.swap.value, 2);

        // deposit is enabled
        assertEq(poolLockStatus.deposit.value, 1);

        if (refreshReserves) pool.depositLiquidity(amount0, amount1, abi.encode(amount0, amount1));
    }

    // swap function for ALM
    function getLiquidityQuote(
        ALMLiquidityQuotePoolInputs memory,
        ALMReserves memory,
        bytes calldata internalContext
    ) external returns (ALMLiquidityQuote memory almLiquidityQuote) {
        PoolLocks memory poolLockStatus = pool.getPoolLockStatus();

        assertEq(poolLockStatus.withdrawals.value, 2);
        assertEq(poolLockStatus.swap.value, 2);
        assertEq(poolLockStatus.deposit.value, 2);

        (almLiquidityQuote) = abi.decode(internalContext, (ALMLiquidityQuote));
    }

    // alm callback
    function callbackOnSwapEnd(
        bool,
        uint256,
        uint256,
        uint256,
        ALMReserves memory,
        int24,
        int24,
        // necessary to inform ALM about the last price tick it provided liquidity at
        // this price tick can be different from spotPriceTick post swap
        ALMCachedLiquidityQuote calldata
    ) external {
        PoolLocks memory poolLockStatus = pool.getPoolLockStatus();

        // withdrawals and deposits should be enabled
        assertEq(poolLockStatus.withdrawals.value, 1, 'ALM Swap callback: invalid withdrawal lock');
        assertEq(poolLockStatus.deposit.value, 1, 'ALM Swap callback: invalid deposit lock');

        // swap should still be disabled
        assertEq(poolLockStatus.swap.value, 2, 'ALM Swap callback: invalid swap lock');
    }

    // swap callback
    function universalPoolSwapCallback(address tokenIn, uint256, bytes calldata swapCallbackContext) external {
        uint256 amountToTransfer = abi.decode(swapCallbackContext, (uint256));

        _setupBalanceForUser(address(this), tokenIn, amountToTransfer);

        IERC20(tokenIn).safeTransfer(msg.sender, amountToTransfer);
    }

    // Flashloan Callback
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bytes32) {
        bytes32 CALLBACK_HASH = keccak256('ERC3156FlashBorrower.onFlashLoan');
        (uint256 op, address originator) = abi.decode(data, (uint256, address));

        assertEq(originator, initiator);

        if (op == 0) {
            // return incorrect hash
            return bytes32(uint256(0));
        } else if (op == 2) {
            // Give correct approval
            IERC20(token).safeApprove(msg.sender, amount);
        } else if (op == 3) {
            // Give correct approval but somehow transfer more tokens from pool
            IERC20(token).safeApprove(msg.sender, amount);

            vm.startPrank(address(pool));
            IERC20(token).safeTransfer(address(1), IERC20(token).balanceOf(address(pool)));
            vm.stopPrank();
        }

        return CALLBACK_HASH;
    }

    // ALM deposit liquidity callback
    function onDepositLiquidityCallback(uint256, uint256, bytes memory _data) external {
        (uint256 amount0ToDeposit, uint256 amount1ToDeposit) = abi.decode(_data, (uint256, uint256));

        PoolLocks memory poolLockStatus = pool.getPoolLockStatus();

        // only deposit should be locked
        assertEq(poolLockStatus.deposit.value, 2);

        address DEPOSIT_USER = makeAddr('DEPOSIT');

        _setupBalanceForUser(DEPOSIT_USER, address(token0), amount0ToDeposit);
        _setupBalanceForUser(DEPOSIT_USER, address(token1), amount1ToDeposit);

        vm.startPrank(DEPOSIT_USER);
        token0.safeTransfer(address(pool), amount0ToDeposit);
        token1.safeTransfer(address(pool), amount1ToDeposit);
        vm.stopPrank();
    }

    // swap fee function
    function getSwapFeeInBips(
        bool,
        uint256,
        address,
        bytes memory swapFeeModuleContext
    ) external pure returns (SwapFeeModuleData memory swapFeeModuleData) {
        (swapFeeModuleData) = abi.decode(swapFeeModuleContext, (SwapFeeModuleData));
    }

    function _deployBaseALMForPool(
        bool isCallbackOnSwapEndRequired,
        bool shareQuotes,
        address almFactory,
        bytes memory constructorArgs
    ) internal returns (address almAddress) {
        protocolFactory.addUniversalALMFactory(almFactory);

        almAddress = protocolFactory.deployALMPositionForUniversalPool(address(pool), almFactory, constructorArgs);

        _setBaseALMForPool(isCallbackOnSwapEndRequired, shareQuotes, almAddress);
    }

    function _setBaseALMForPool(bool isCallbackOnSwapEndRequired, bool shareQuotes, address almAddress) internal {
        vm.prank(POOL_MANAGER);
        pool.addALMPosition(false, isCallbackOnSwapEndRequired, shareQuotes, 0, almAddress);
        _addToContractsToApprove(almAddress);
    }

    function _deployMetaALMForPool(
        bool isCallbackOnSwapEndRequired,
        bool shareQuotes,
        uint64 metaALMFeeShare,
        address almFactory,
        bytes memory constructorArgs
    ) internal returns (address almAddress) {
        protocolFactory.addUniversalALMFactory(almFactory);

        almAddress = protocolFactory.deployALMPositionForUniversalPool(address(pool), almFactory, constructorArgs);

        _setMetaALMForPool(isCallbackOnSwapEndRequired, shareQuotes, metaALMFeeShare, almAddress);
    }

    function _setMetaALMForPool(
        bool isCallbackOnSwapEndRequired,
        bool shareQuotes,
        uint64 metaALMFeeShare,
        address almAddress
    ) internal {
        vm.prank(POOL_MANAGER);
        pool.addALMPosition(true, isCallbackOnSwapEndRequired, shareQuotes, metaALMFeeShare, almAddress);
        _addToContractsToApprove(almAddress);
    }

    function _defaultPoolState() internal view returns (PoolState memory poolState) {
        poolState = PoolState(0, 0, 0, 0, 0, block.timestamp, ZERO_ADDRESS, POOL_MANAGER, ZERO_ADDRESS, ZERO_ADDRESS);
    }

    // overwrite storage value helper functions

    function _setPoolManagerFeeBips(uint256 feeBips) internal {
        vm.store(address(pool), bytes32(uint256(4)), bytes32(feeBips));
    }

    function _setProtocolFees(uint256 fee0, uint256 fee1) internal {
        vm.store(address(pool), bytes32(uint256(5)), bytes32(fee0));
        vm.store(address(pool), bytes32(uint256(6)), bytes32(fee1));
    }

    function _setPoolManagerFees(uint256 fee0, uint256 fee1) internal {
        vm.store(address(pool), bytes32(uint256(7)), bytes32(fee0));
        vm.store(address(pool), bytes32(uint256(8)), bytes32(fee1));
    }

    // 0 offset for withdrawal lock, 1 for deposit and 2 for swap
    function _lockPool(uint8 offset) internal {
        vm.store(address(pool), bytes32(uint256(offset)), bytes32(uint256(2)));
    }

    function _unlockPool(uint8 offset) internal {
        vm.store(address(pool), bytes32(uint256(offset)), bytes32(uint256(1)));
    }
}
