import { ethers } from 'hardhat';

async function main() {
  const [_signer] = await ethers.getSigners();

  const SovereignPoolFactoryDeployer = await ethers.getContractFactory('SovereignPoolFactory');

  const sovereignPoolFactory = await SovereignPoolFactoryDeployer.deploy();
  await sovereignPoolFactory.waitForDeployment();
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
