import { expect } from 'chai';
import { Signer, ZeroAddress } from 'ethers';
import { ethers } from 'hardhat';
import {
  ALMLib,
  EnumerableALMMap,
  IERC20__factory,
  MockUniversalALM,
  StateLib,
  UniversalPool,
} from '../../typechain-types';
import { SwapParamsStruct } from '../../typechain-types/src/pools/UniversalPool';
import { ALMLiquidityQuoteStruct } from '../../typechain-types/src/ALM/interfaces/IUniversalALM';

describe('Universal Pool', async () => {
  let poolManager: Signer;

  let depositUser: Signer;

  let swapUser: Signer;

  let withdrawUser: Signer;

  const USDT = IERC20__factory.connect('0xdAC17F958D2ee523a2206206994597C13D831ec7');

  const USDC = IERC20__factory.connect('0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48');

  let pool: UniversalPool;
  let alm: MockUniversalALM;
  let almLib: ALMLib;
  let stateLib: StateLib;
  let enumerableMap: EnumerableALMMap;

  before(async () => {
    [poolManager, depositUser, swapUser, withdrawUser] = await ethers.getSigners();

    const EnumerableMapFactory = await ethers.getContractFactory('EnumerableALMMap', poolManager);
    const ALMLibFactory = await ethers.getContractFactory('ALMLib', poolManager);
    const StateLibFactory = await ethers.getContractFactory('StateLib', poolManager);

    enumerableMap = await EnumerableMapFactory.deploy();
    almLib = await ALMLibFactory.deploy();
    stateLib = await StateLibFactory.deploy();

    const PoolFactory = await ethers.getContractFactory('UniversalPool', {
      libraries: {
        EnumerableALMMap: await enumerableMap.getAddress(),
        ALMLib: await almLib.getAddress(),
        StateLib: await stateLib.getAddress(),
      },
      signer: poolManager,
    });
    pool = await PoolFactory.deploy(await USDC.getAddress(), await USDT.getAddress(), ZeroAddress, poolManager, 0);
  });

  it('Deploy checks', async () => {
    const token0 = await pool.token0();
    const token1 = await pool.token1();
    expect(token0).equals(await USDC.getAddress(), 'Invalid token0 set');
    expect(token1).equals(await USDT.getAddress(), 'Invalid token1 set');
    expect((await pool.state()).poolManager).equals(await poolManager.getAddress(), 'Invalid Pool Manager');
  });

  it('Initialize tick', async () => {
    await pool.connect(poolManager).initializeTick(1, {
      poolManagerFeeBips: 0,
      feeProtocol0: 0,
      feeProtocol1: 0,
      feePoolManager0: 0,
      feePoolManager1: 0,
      swapFeeModule: ZeroAddress,
      swapFeeModuleUpdateTimestamp: 0,
      poolManager: await poolManager.getAddress(),
      universalOracle: ZeroAddress,
      gauge: ZeroAddress,
    });
    expect(await pool.spotPriceTick()).equals(1, 'Invalid Spot Price Tick');
  });

  it('Set ALM', async () => {
    const ALMFactory = await ethers.getContractFactory('MockUniversalALM', poolManager);
    alm = await ALMFactory.deploy(await pool.getAddress(), false);

    const almAddress = await alm.getAddress();
    await pool.connect(poolManager).addALMPosition(false, false, false, 0, almAddress);

    const [status] = await pool.getALMPositionAtAddress(almAddress);

    expect(status).equals(1, 'Invalid ALM set');
  });

  it('Deposit Liquidity', async () => {
    const USDT_WHALE_ADDR = '0xD6216fC19DB775Df9774a6E33526131dA7D19a2c';
    const USDC_WHALE_ADDR = '0xD6153F5af5679a75cC85D8974463545181f48772';

    const usdt_whale = await ethers.getImpersonatedSigner(USDT_WHALE_ADDR);
    const usdc_whale = await ethers.getImpersonatedSigner(USDC_WHALE_ADDR);

    /// Prefill whale's addresses with some eth for transfers
    let tx = await poolManager.sendTransaction({ to: USDC_WHALE_ADDR, value: ethers.parseEther('1') });
    await tx.wait();

    tx = await poolManager.sendTransaction({ to: USDT_WHALE_ADDR, value: ethers.parseEther('1') });
    await tx.wait();

    /// Transfer USDT and USDC to deposit user address from whale addresses

    tx = await USDT.connect(usdt_whale).transfer(await depositUser.getAddress(), ethers.parseUnits('1000000', 6));
    await tx.wait();

    tx = await USDC.connect(usdc_whale).transfer(await depositUser.getAddress(), ethers.parseUnits('1000000', 6));
    await tx.wait();

    const almAddress = await alm.getAddress();
    tx = await USDT.connect(depositUser).approve(almAddress, ethers.MaxUint256);
    await tx.wait();

    tx = await USDC.connect(depositUser).approve(almAddress, ethers.MaxUint256);
    await tx.wait();

    const amount0 = ethers.parseUnits('500000', 6);
    const amount1 = ethers.parseUnits('600000', 6);
    tx = await alm.connect(depositUser).depositLiquidity(amount0, amount1);
    await tx.wait();

    const [, almPosition] = await pool.getALMPositionAtAddress(almAddress);

    expect(almPosition.reserve0).equals(amount0, 'Invalid reserve update for token0');
    expect(almPosition.reserve1).equals(amount1, 'Invalid reserve update for token1');
  });

  it('Swap', async () => {
    let tx = await USDC.connect(depositUser).transfer(await swapUser.getAddress(), ethers.parseUnits('100000', 6));
    await tx.wait();
    const amountIn = ethers.parseUnits('10000', 6);

    tx = await USDC.connect(swapUser).approve(await pool.getAddress(), ethers.MaxUint256);
    await tx.wait();

    let quote: ALMLiquidityQuoteStruct = {
      tokenOutAmount: ethers.parseUnits('4000', 6),
      nextLiquidPriceTick: -1,
      internalContext: '0x00',
    };

    quote = {
      tokenOutAmount: ethers.parseUnits('4000', 6),
      nextLiquidPriceTick: -1,
      internalContext: ethers.AbiCoder.defaultAbiCoder().encode(
        ['(uint256 tokenOutAmount, int24 nextLiquidPriceTick, bytes internalContext)'],
        [quote]
      ),
    };

    quote = {
      tokenOutAmount: ethers.parseUnits('100', 6),
      nextLiquidPriceTick: 0,
      internalContext: ethers.AbiCoder.defaultAbiCoder().encode(
        ['(uint256 tokenOutAmount, int24 nextLiquidPriceTick, bytes internalContext)'],
        [quote]
      ),
    };

    const swapParams: SwapParamsStruct = {
      isZeroToOne: true,
      isSwapCallback: false,
      almOrdering: [0],
      amountIn: amountIn,
      deadline: ethers.MaxUint256,
      limitPriceTick: -10,
      amountOutMin: 0,
      recipient: await swapUser.getAddress(),
      swapFeeModuleContext: '0x00',
      swapCallbackContext: '0x00',
      externalContext: [
        ethers.AbiCoder.defaultAbiCoder().encode(
          [
            'bool',
            'bool',
            'uint256',
            'uint256',
            '(uint256 tokenOutAmount, int24 nextLiquidPriceTick, bytes internalContext)',
          ],
          [true, false, 0, 0, quote]
        ),
      ],
    };

    await expect(pool.connect(swapUser).swap(swapParams)).to.emit(pool, 'Swap');

    const usdtBalance = await USDT.connect(swapUser).balanceOf(await swapUser.getAddress());

    expect(usdtBalance).equals(ethers.parseUnits('8100', 6), 'Invalid amount out received');
  });

  it('Withdraw liquidity', async () => {
    const almAddress = await alm.getAddress();

    const [, almPosition] = await pool.getALMPositionAtAddress(almAddress);

    const amount0 = ethers.parseUnits('1000', 6);
    const amount1 = ethers.parseUnits('2000', 6);

    const preUsdtBalance = await USDT.connect(withdrawUser).balanceOf(await withdrawUser.getAddress());
    const preUsdcBalance = await USDC.connect(withdrawUser).balanceOf(await withdrawUser.getAddress());

    const tx = await alm.withdrawLiquidity(amount0, amount1, await withdrawUser.getAddress());
    await tx.wait();

    const [, postALMPosition] = await pool.getALMPositionAtAddress(almAddress);

    expect(almPosition.reserve0 - postALMPosition.reserve0).equals(
      amount0,
      'Amount for token0 not updated post withdraw'
    );
    expect(almPosition.reserve1 - postALMPosition.reserve1).equals(
      amount1,
      'Amount for token1 not updated post withdraw'
    );

    const usdtBalance = await USDT.connect(withdrawUser).balanceOf(await withdrawUser.getAddress());
    const usdcBalance = await USDC.connect(withdrawUser).balanceOf(await withdrawUser.getAddress());

    expect(usdcBalance - preUsdcBalance).equals(amount0, 'Amount not transferred to receipent for token0');
    expect(usdtBalance - preUsdtBalance).equals(amount1, 'Amount not transferred to receipent for token1');
  });
});
