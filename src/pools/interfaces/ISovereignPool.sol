// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { IValantisPool } from '../interfaces/IValantisPool.sol';
import { PoolLocks } from '../structs/ReentrancyGuardStructs.sol';
import { SovereignPoolSwapContextData, SovereignPoolSwapParams } from '../structs/SovereignPoolStructs.sol';

interface ISovereignPool is IValantisPool {
    event SwapFeeModuleSet(address swapFeeModule);
    event ALMSet(address alm);
    event GaugeSet(address gauge);
    event PoolManagerSet(address poolManager);
    event PoolManagerFeeSet(uint256 poolManagerFeeBips);
    event SovereignOracleSet(address sovereignOracle);
    event PoolManagerFeesClaimed(uint256 amount0, uint256 amount1);
    event DepositLiquidity(uint256 amount0, uint256 amount1);
    event WithdrawLiquidity(address indexed recipient, uint256 amount0, uint256 amount1);
    event Swap(address indexed sender, bool isZeroToOne, uint256 amountIn, uint256 fee, uint256 amountOut);

    function getTokens() external view returns (address[] memory tokens);

    function sovereignVault() external view returns (address);

    function protocolFactory() external view returns (address);

    function gauge() external view returns (address);

    function poolManager() external view returns (address);

    function sovereignOracleModule() external view returns (address);

    function swapFeeModule() external view returns (address);

    function verifierModule() external view returns (address);

    function isLocked() external view returns (bool);

    function isRebaseTokenPool() external view returns (bool);

    function poolManagerFeeBips() external view returns (uint256);

    function defaultSwapFeeBips() external view returns (uint256);

    function alm() external view returns (address);

    function getPoolManagerFees() external view returns (uint256 poolManagerFee0, uint256 poolManagerFee1);

    function getReserves() external view returns (uint256 reserve0, uint256 reserve1);

    function setPoolManager(address _manager) external;

    function setGauge(address _gauge) external;

    function setPoolManagerFeeBips(uint256 _poolManagerFeeBips) external;

    function setSovereignOracle(address sovereignOracle) external;

    function setSwapFeeModule(address _swapFeeModule) external;

    function setALM(address _alm) external;

    function swap(SovereignPoolSwapParams calldata _swapParams) external returns (uint256, uint256);

    function depositLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _sender,
        bytes calldata _verificationContext,
        bytes calldata _depositData
    ) external returns (uint256 amount0Deposited, uint256 amount1Deposited);

    function withdrawLiquidity(
        uint256 _amount0,
        uint256 _amount1,
        address _sender,
        address _recipient,
        bytes calldata _verificationContext
    ) external;
}
