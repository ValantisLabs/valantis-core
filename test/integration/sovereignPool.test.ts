import { expect } from 'chai';
import { Signer, ZeroAddress } from 'ethers';
import { ethers } from 'hardhat';
import { IERC20__factory, MockSovereignALM, SovereignPool } from '../../typechain-types';
import {
  SovereignPoolSwapContextDataStruct,
  SovereignPoolSwapParamsStruct,
} from '../../typechain-types/src/pools/SovereignPool';

describe('Sovereign Pool', async () => {
  let poolManager: Signer;

  let depositUser: Signer;

  let swapUser: Signer;

  let withdrawUser: Signer;

  const USDT = IERC20__factory.connect('0xdAC17F958D2ee523a2206206994597C13D831ec7');
  const stETH = IERC20__factory.connect('0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84');

  let pool: SovereignPool;
  let alm: MockSovereignALM;

  before(async () => {
    [poolManager, depositUser, swapUser, withdrawUser] = await ethers.getSigners();

    const constructorArgs = {
      token0: await USDT.getAddress(),
      token1: await stETH.getAddress(),
      protocolFactory: ethers.ZeroAddress,
      poolManager: poolManager,
      sovereignVault: ZeroAddress,
      verifierModule: ZeroAddress,
      isToken0Rebase: false,
      isToken1Rebase: true,
      token0AbsErrorTolerance: 0,
      token1AbsErrorTolerance: 7,
      defaultSwapFeeBips: 100,
    };

    const PoolFactory = await ethers.getContractFactory('SovereignPool', poolManager);
    pool = await PoolFactory.deploy(constructorArgs);
  });

  it('Deploy correctly', async () => {
    const token0 = await pool.token0();
    const token1 = await pool.token1();
    expect(token0).equals(await USDT.getAddress(), 'Invalid token0 set');
    expect(token1).equals(await stETH.getAddress(), 'Invalid token1 set');
    expect(await pool.getAddress()).equals(await pool.sovereignVault(), 'Invalid sovereign vault');
  });

  it('Set ALM correctly', async () => {
    const ALMFactory = await ethers.getContractFactory('MockSovereignALM', poolManager);
    alm = await ALMFactory.deploy(await pool.getAddress());
    await alm.setSovereignVault();

    const almAddress = await alm.getAddress();
    await pool.connect(poolManager).setALM(almAddress);
    expect(almAddress).equals(await pool.alm(), 'Invalid ALM set');
  });

  it('Deposit liquidity correctly', async () => {
    const USDT_WHALE_ADDR = '0xD6216fC19DB775Df9774a6E33526131dA7D19a2c';
    const stETH_WHALE_ADDR = '0xd8d041705735cd770408AD31F883448851F2C39d';

    const usdt_whale = await ethers.getImpersonatedSigner(USDT_WHALE_ADDR);
    const steth_whale = await ethers.getImpersonatedSigner(stETH_WHALE_ADDR);

    /// Prefill whale's addresses with some eth for transfers
    let tx = await poolManager.sendTransaction({ to: stETH_WHALE_ADDR, value: ethers.parseEther('1') });
    await tx.wait();

    tx = await poolManager.sendTransaction({ to: USDT_WHALE_ADDR, value: ethers.parseEther('1') });
    await tx.wait();

    /// Transfer USDT and stETH to deposit user address from whale addresses
    tx = await USDT.connect(usdt_whale).transfer(await depositUser.getAddress(), ethers.parseUnits('1000000', 6));
    await tx.wait();

    tx = await stETH.connect(steth_whale).transfer(await depositUser.getAddress(), ethers.parseEther('2000'));
    await tx.wait();

    const almAddress = await alm.getAddress();
    tx = await USDT.connect(depositUser).approve(almAddress, ethers.MaxUint256);
    await tx.wait();

    tx = await stETH.connect(depositUser).approve(almAddress, ethers.MaxUint256);
    await tx.wait();

    const amount0 = ethers.parseUnits('1000000', 6);
    const amount1 = ethers.parseEther('2000');
    await expect(alm.connect(depositUser).depositLiquidity(amount0, amount1, '0x00')).to.emit(pool, 'DepositLiquidity');

    const reserves = await pool.getReserves();
    expect(amount0).equals(reserves[0], 'Invalid reserves for token0 post deposit');

    /// Since token1 is rebase token, got to account for delta
    expect(amount1).approximately(reserves[1], 7, 'Invalid reserves for token1 post deposit');
  });

  it('Swap correctly', async () => {
    const USDT_WHALE_ADDR = '0xD6216fC19DB775Df9774a6E33526131dA7D19a2c';
    const usdt_whale = await ethers.getImpersonatedSigner(USDT_WHALE_ADDR);

    /// Transfer USDT to swap user address from whale addresses
    let tx = await USDT.connect(usdt_whale).transfer(await swapUser.getAddress(), ethers.parseUnits('10000', 6));
    await tx.wait();

    tx = await USDT.connect(swapUser).approve(await pool.getAddress(), ethers.MaxUint256);
    await tx.wait();

    const amountIn = ethers.parseUnits('10000', 6);
    const swapContext: SovereignPoolSwapContextDataStruct = {
      externalContext: '0x00',
      swapCallbackContext: '0x00',
      swapFeeModuleContext: '0x00',
      verifierContext: '0x00',
    };
    const swapParam: SovereignPoolSwapParamsStruct = {
      isSwapCallback: false,
      isZeroToOne: true,
      amountIn: amountIn,
      amountOutMin: 0,
      deadline: ethers.MaxUint256,
      recipient: await swapUser.getAddress(),
      swapContext: swapContext,
      swapTokenOut: await stETH.getAddress(),
    };

    let reserves = await pool.getReserves();

    const expectedAmountInMinusFee = (amountIn * BigInt(10000)) / BigInt(10100);

    const expectedAmountOut = reserves[1] - (reserves[0] * reserves[1]) / (reserves[0] + expectedAmountInMinusFee);

    const expectedFee = amountIn - expectedAmountInMinusFee;

    const expectedReserve0 = reserves[0] + amountIn;
    const expectedReserve1 = reserves[1] - expectedAmountOut;

    await expect(pool.connect(swapUser).swap(swapParam))
      .to.emit(pool, 'Swap')
      .withArgs(await swapUser.getAddress(), true, amountIn, expectedFee, expectedAmountOut);

    reserves = await pool.getReserves();

    expect(expectedReserve0).equals(reserves[0], 'Invalid reserve0 after swap');
    expect(expectedReserve1).approximately(reserves[1], 7, 'Invalid reserve1 after swap');

    expect(expectedFee).equals(await alm.fee0(), 'Invalid fee in ALM after swap');

    const usdtBalance = await USDT.connect(swapUser).balanceOf(await swapUser.getAddress());
    const stethBalance = await stETH.connect(swapUser).balanceOf(await swapUser.getAddress());
    expect(expectedAmountOut).approximately(stethBalance, 7, 'Recipient balance did not increase after swap');
    expect(0).equals(usdtBalance, "User's balance didn't decrease after swap");
  });

  it('Withdraw liquidity correctly', async () => {
    let reserves = await pool.getReserves();

    const amount0 = ethers.parseUnits('10000', 6);
    const amount1 = ethers.parseEther('20');

    const expectedReserve0 = reserves[0] - amount0;
    const expectedReserve1 = reserves[1] - amount1;

    await expect(
      alm.connect(withdrawUser).withdrawLiquidity(amount0, amount1, 0, 0, await withdrawUser.getAddress(), '0x00')
    )
      .to.emit(pool, 'WithdrawLiquidity')
      .withArgs(await withdrawUser.getAddress(), amount0, amount1);

    reserves = await pool.getReserves();

    expect(expectedReserve0).equals(reserves[0], 'Invalid reserve for token0 after withdraw liquidity');
    expect(expectedReserve1).approximately(reserves[1], 7, 'Invalid reserve for token0 after withdraw liquidity');

    const usdtBalance = await USDT.connect(withdrawUser).balanceOf(await withdrawUser.getAddress());
    const stethBalance = await stETH.connect(withdrawUser).balanceOf(await withdrawUser.getAddress());

    expect(amount0).equals(usdtBalance, "User's balance didn't increase after withdraw liquidity");

    expect(amount1).approximately(stethBalance, 7, 'Recipient balance did not increase after withdraw liquidity');
  });
});
