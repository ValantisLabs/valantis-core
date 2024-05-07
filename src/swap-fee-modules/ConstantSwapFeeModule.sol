// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import { SwapFeeModuleData } from './interfaces/ISwapFeeModule.sol';
import { IConstantSwapFeeModule } from './interfaces/IConstantSwapFeeModule.sol';

contract ConstantSwapFeeModule is IConstantSwapFeeModule {
    /************************************************
     *  CUSTOM ERRORS
     ***********************************************/

    error ConstantSwapFeeModule__onlyPool();
    error ConstantSwapFeeModule__onlyFeeModuleManager();
    error ConstantSwapFeeModule__invalidSwapFeeBips();

    /************************************************
     *  CONSTANTS
     ***********************************************/

    uint256 public constant MAX_SWAP_FEE_BIPS = 10_000;

    /************************************************
     *  IMMUTABLES
     ***********************************************/

    address public immutable pool;

    /************************************************
     *  STORAGE
     ***********************************************/

    address public feeModuleManager;

    uint256 public swapFeeBips;

    /************************************************
     *  MODIFIERS
     ***********************************************/

    function _onlyPool() private view {
        if (msg.sender != pool) {
            revert ConstantSwapFeeModule__onlyPool();
        }
    }

    function _onlyFeeModuleManager() private view {
        if (msg.sender != feeModuleManager) {
            revert ConstantSwapFeeModule__onlyFeeModuleManager();
        }
    }

    modifier onlyPool() {
        _onlyPool();
        _;
    }

    modifier onlyFeeModuleManager() {
        _onlyFeeModuleManager();
        _;
    }

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(address _pool, address _feeModuleManager, uint256 _swapFeeBips) {
        if (_swapFeeBips > MAX_SWAP_FEE_BIPS) {
            revert ConstantSwapFeeModule__invalidSwapFeeBips();
        }

        pool = _pool;
        feeModuleManager = _feeModuleManager;
        swapFeeBips = _swapFeeBips;
    }

    /************************************************
     *  EXTERNAL FUNCTIONS
     ***********************************************/

    /**
        @notice Update address of Swap Fee Module manager.
        @dev Only callable by `feeModuleManager`.
        @param _feeModuleManager Address of new `feeModuleManager`. 
     */
    function setFeeModuleManager(address _feeModuleManager) external onlyFeeModuleManager {
        feeModuleManager = _feeModuleManager;
    }

    /**
        @notice Update constant swap fee in basis points.
        @dev Only callable by `feeModuleManager.
        @param _swapFeeBips New constant swap fee in basis points. 
     */
    function setSwapFeeBips(uint256 _swapFeeBips) external onlyFeeModuleManager {
        if (_swapFeeBips > MAX_SWAP_FEE_BIPS) {
            revert ConstantSwapFeeModule__invalidSwapFeeBips();
        }

        swapFeeBips = _swapFeeBips;
    }

    /**
        @notice Calculate swap fee for Sovereign Pool.
        @dev Only callable by `pool`.
        @return swapFeeModuleData Swap Fee Module data. 
     */
    function getSwapFeeInBips(
        address,
        address,
        uint256,
        address,
        bytes memory
    ) external view override onlyPool returns (SwapFeeModuleData memory swapFeeModuleData) {
        swapFeeModuleData.feeInBips = swapFeeBips;
        swapFeeModuleData.internalContext = new bytes(0);
    }

    /**
        @notice Callback after the swap is ended for Universal Pool.
        @dev Not applicable for this Swap Fee Module. 
     */
    function callbackOnSwapEnd(uint256, int24, uint256, uint256, SwapFeeModuleData memory) external override {}

    /**
        @notice Callback after the swap is ended for SovereignPool
        @dev Not applicable for this Swap Fee Module. 
     */
    function callbackOnSwapEnd(uint256, uint256, uint256, SwapFeeModuleData memory) external override {}
}
