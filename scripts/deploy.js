/*
  Deployment script for Pod.fun launchpad ecosystem.
  Usage: npx hardhat run --network <network> scripts/deploy.js
*/

const fs = require('fs');
const hre = require('hardhat');
const { ethers } = hre;

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log('Deploying with', deployer.address);

  const guardian = process.env.protocol_guardian_address || deployer.address;

  const DEXFactory = await ethers.getContractFactory('DEXFactory');
  const ProtocolTreasury = await ethers.getContractFactory('ProtocolTreasury');
  const DEXRouter = await ethers.getContractFactory('DEXRouter');
  const LaunchpadFactory = await ethers.getContractFactory('LaunchpadFactory');

  const dummyTreasury = await ProtocolTreasury.deploy(deployer.address, guardian);
  await dummyTreasury.deployed();

  const dexFactory = await DEXFactory.deploy(dummyTreasury.address, deployer.address);
  await dexFactory.deployed();

  const router = await DEXRouter.deploy(dexFactory.address);
  await router.deployed();

  const launchpad = await LaunchpadFactory.deploy(
    deployer.address,
    dexFactory.address,
    router.address,
    guardian
  );
  await launchpad.deployed();

  const artifacts = {
    dexFactory: dexFactory.address,
    router: router.address,
    launchpad: launchpad.address,
    treasury: (await launchpad.treasury()).toString()
  };
  fs.writeFileSync('deployment.json', JSON.stringify(artifacts, null, 2));
  console.log('Deployment complete:', artifacts);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
