// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import { ERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol';
import { IERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol';
import { SafeERC20 } from 'lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol';

import { ALMLiquidityQuoteInput, ALMLiquidityQuote } from 'src/ALM/structs/SovereignALMStructs.sol';
import { SovereignPoolConstructorArgs } from 'src/pools/structs/SovereignPoolStructs.sol';
import { SovereignPool } from 'src/pools/SovereignPool.sol';
import { ProtocolFactory } from 'src/protocol-factory/ProtocolFactory.sol';
import { SwapFeeModuleData } from 'src/swap-fee-modules/interfaces/ISwapFeeModule.sol';

import { Base } from 'test/base/Base.sol';
import { SovereignPoolDeployer } from 'test/deployers/SovereignPoolDeployer.sol';

contract SovereignPoolBase is Base, SovereignPoolDeployer {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    /************************************************
     *  ENUMS
     ***********************************************/

    enum AccessType {
        SWAP,
        DEPOSIT,
        WITHDRAW
    }

    struct TokenData {
        bool isTokenRebase;
        uint256 tokenAbsErrorTolerance;
        uint256 tokenMinAmount;
    }

    struct CustomConstructorArgsParams {
        TokenData token0Data;
        TokenData token1Data;
        address sovereignVault;
        address verifierModule;
        uint256 defaultFeeBips;
    }

    ProtocolFactory public protocolFactory;
    SovereignPool public pool;
    bytes32 emptyConstructorArgsHash;

    function setUp() public {
        _setupBase();

        SovereignPoolConstructorArgs memory constructorArgs = _generateDefaultConstructorArgs();

        pool = this.deploySovereignPool(constructorArgs);

        protocolFactory = ProtocolFactory(pool.protocolFactory());

        SovereignPoolConstructorArgs memory emptyBytes;

        emptyConstructorArgsHash = keccak256(abi.encode(emptyBytes));

        _addToContractsToApprove(address(pool));
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
        } else if (op == 1) {
            // return without giving approval to pull out token
        } else if (op == 2) {
            // Give correct approval
            IERC20(token).safeApprove(msg.sender, amount);
        } else if (op == 3) {
            // Give correct approval but somehow transfer more tokens from pool
            IERC20(token).safeApprove(msg.sender, amount);

            vm.startPrank(address(pool));
            token0.safeTransfer(address(1), token0.balanceOf(address(pool)));
            vm.stopPrank();
        }

        return CALLBACK_HASH;
    }

    // Deposit Callback
    function onDepositLiquidityCallback(uint256, uint256, bytes memory _data) external {
        assertEq(address(pool), msg.sender);

        (, uint256 amount0, uint256 amount1) = abi.decode(_data, (uint256, uint256, uint256));

        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);
    }

    // Verifier Module callback
    function verify(
        address user,
        bytes calldata data,
        uint8 accessType
    ) external returns (bool success, bytes memory returnData) {
        if (accessType == uint8(AccessType.SWAP) && user == makeAddr('SWAP')) {
            return (true, new bytes(0));
        }

        if (accessType == uint8(AccessType.DEPOSIT) && user == makeAddr('DEPOSIT')) {
            return (true, new bytes(0));
        }

        if (accessType == uint8(AccessType.WITHDRAW) && user == makeAddr('WITHDRAW')) {
            return (true, new bytes(0));
        }

        if (data.length > 0) {
            (success) = abi.decode(data, (bool));
        }
    }

    // Swap Fee Module function
    function getSwapFeeInBips(
        bool,
        uint256,
        address,
        bytes memory data
    ) external pure returns (SwapFeeModuleData memory swapFeeModuleData) {
        (uint256 swapFeeBips, bytes memory internalContext) = abi.decode(data, (uint256, bytes));
        swapFeeModuleData.feeInBips = swapFeeBips;
        swapFeeModuleData.internalContext = internalContext;
    }

    function getLiquidityQuote(
        ALMLiquidityQuoteInput memory,
        bytes calldata externalContext,
        bytes calldata
    ) external returns (ALMLiquidityQuote memory liquidityQuote) {
        assertEq(msg.sender, address(pool));

        (liquidityQuote) = abi.decode(externalContext, (ALMLiquidityQuote));
    }

    function sovereignPoolSwapCallback(address _tokenIn, uint256, bytes calldata _swapCallbackContext) external {
        uint256 amountIn = abi.decode(_swapCallbackContext, (uint256));

        _setupBalanceForUser(address(pool), _tokenIn, amountIn);
    }

    function _generateDefaultConstructorArgs()
        internal
        view
        returns (SovereignPoolConstructorArgs memory constructorArgs)
    {
        constructorArgs = SovereignPoolConstructorArgs(
            address(token0),
            address(token1),
            ZERO_ADDRESS,
            POOL_MANAGER,
            ZERO_ADDRESS,
            ZERO_ADDRESS,
            false,
            false,
            0,
            0,
            0,
            0,
            0
        );
    }

    function _generatCustomConstructorArgs(
        CustomConstructorArgsParams memory customParams
    ) internal view returns (SovereignPoolConstructorArgs memory constructorArgs) {
        constructorArgs = _generateDefaultConstructorArgs();
        if (customParams.sovereignVault != ZERO_ADDRESS) {
            constructorArgs.sovereignVault = customParams.sovereignVault;
        }

        if (customParams.verifierModule != ZERO_ADDRESS) {
            constructorArgs.verifierModule = customParams.verifierModule;
        }

        if (customParams.defaultFeeBips != 0) {
            constructorArgs.defaultSwapFeeBips = customParams.defaultFeeBips;
        }

        TokenData memory emptyData;

        if (keccak256(abi.encode(emptyData)) != keccak256(abi.encode(customParams.token0Data))) {
            constructorArgs.isToken0Rebase = customParams.token0Data.isTokenRebase;
            constructorArgs.token0AbsErrorTolerance = customParams.token0Data.tokenAbsErrorTolerance;
            constructorArgs.token0MinAmount = customParams.token0Data.tokenMinAmount;
        }

        if (keccak256(abi.encode(emptyData)) != keccak256(abi.encode(customParams.token1Data))) {
            constructorArgs.isToken1Rebase = customParams.token1Data.isTokenRebase;
            constructorArgs.token1AbsErrorTolerance = customParams.token1Data.tokenAbsErrorTolerance;
            constructorArgs.token1MinAmount = customParams.token1Data.tokenMinAmount;
        }
    }

    function _deployALMForPool(
        address almFactory,
        bytes calldata constructorArgs
    ) internal returns (address almAddress) {
        protocolFactory.addSovereignALMFactory(almFactory);

        almAddress = protocolFactory.deployALMPositionForSovereignPool(address(pool), almFactory, constructorArgs);

        _setALMForPool(almAddress);
    }

    function _setALMForPool(address almAddress) internal {
        vm.prank(POOL_MANAGER);
        pool.setALM(almAddress);
        _addToContractsToApprove(almAddress);
    }

    function _depositLiquidity(
        uint256 amount0,
        uint256 amount1,
        address user,
        bytes memory verificationContext,
        bytes memory depositData
    ) internal returns (uint256, uint256) {
        return pool.depositLiquidity(amount0, amount1, user, verificationContext, depositData);
    }

    function _setReservesForPool(uint256 reserve0, uint256 reserve1) internal {
        if (pool.sovereignVault() != address(pool)) {
            _setupBalanceForUser(pool.sovereignVault(), address(token0), reserve0);
            _setupBalanceForUser(pool.sovereignVault(), address(token1), reserve1);
            return;
        }

        if (pool.isToken0Rebase()) {
            _setupBalanceForUser(address(pool), address(token0), reserve0);
        } else {
            vm.store(address(pool), bytes32(uint256(9)), bytes32(reserve0));
            _setupBalanceForUser(address(pool), address(token0), reserve0);
        }

        if (pool.isToken1Rebase()) {
            _setupBalanceForUser(address(pool), address(token1), reserve1);
        } else {
            vm.store(address(pool), bytes32(uint256(10)), bytes32(reserve1));
            _setupBalanceForUser(address(pool), address(token1), reserve1);
        }
    }

    // overwrite storage value helper functions
    // to get corresponding slots use `forge inspect SovereignPool storageLayout --pretty`

    function _setPoolManagerFeeBips(uint256 poolManagerFeeBips) internal {
        vm.store(address(pool), bytes32(uint256(4)), bytes32(poolManagerFeeBips));
    }

    function _setPoolManagerFees(uint256 fees0, uint256 fees1) internal {
        vm.store(address(pool), bytes32(uint256(5)), bytes32(fees0));
        vm.store(address(pool), bytes32(uint256(6)), bytes32(fees1));
    }

    function _setProtocolFees(uint256 fee0, uint256 fee1) internal {
        vm.store(address(pool), bytes32(uint256(7)), bytes32(fee0));
        vm.store(address(pool), bytes32(uint256(8)), bytes32(fee1));
    }

    function _setReserves(uint256 reserve0, uint256 reserve1) internal {
        vm.store(address(pool), bytes32(uint256(9)), bytes32(reserve0));
        vm.store(address(pool), bytes32(uint256(10)), bytes32(reserve1));
    }

    function _setPoolManager(address poolManager) internal {
        vm.store(address(pool), bytes32(uint256(3)), bytes32(uint256(uint160(poolManager))));
    }

    function _setALM(address alm) internal {
        vm.store(address(pool), bytes32(uint256(1)), bytes32(uint256(uint160(alm))));
    }

    function _setOracleModule(address oracleModule) internal {
        vm.store(address(pool), bytes32(uint256(11)), bytes32(uint256(uint160(oracleModule))));
    }

    function _setSwapFeeModule(address swapFeeModule) internal {
        vm.store(address(pool), bytes32(uint256(12)), bytes32(uint256(uint160(swapFeeModule))));
    }
}
