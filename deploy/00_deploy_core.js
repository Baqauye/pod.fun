const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const DEXFactory = await ethers.getContractFactory("DEXFactory");
  const factory = await DEXFactory.deploy(await deployer.getAddress());
  await factory.waitForDeployment();
  console.log("DEXFactory:", await factory.getAddress());

  const DEXRouter = await ethers.getContractFactory("DEXRouter");
  const router = await DEXRouter.deploy(factory);
  await router.waitForDeployment();
  console.log("DEXRouter:", await router.getAddress());

  const LaunchpadFactory = await ethers.getContractFactory("LaunchpadFactory");
  const launchpad = await LaunchpadFactory.deploy(
    deployer.address,
    deployer.address,
    factory,
    ethers.parseEther("4"),
    400,
    500,
    100
  );
  await launchpad.waitForDeployment();
  console.log("LaunchpadFactory:", await launchpad.getAddress());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
