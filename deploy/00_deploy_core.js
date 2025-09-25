const { ethers } = require("hardhat");

async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with:", deployer.address);

  const WpETH = await ethers.getContractFactory("WpETH");
  const wrapped = await WpETH.deploy();
  await wrapped.waitForDeployment();
  console.log("WpETH:", await wrapped.getAddress());

  const DEXFactory = await ethers.getContractFactory("DEXFactory");
  const factory = await DEXFactory.deploy(await wrapped.getAddress(), deployer.address);
  await factory.waitForDeployment();
  console.log("DEXFactory:", await factory.getAddress());

  const DEXRouter = await ethers.getContractFactory("DEXRouter");
  const router = await DEXRouter.deploy(factory, wrapped);
  await router.waitForDeployment();
  console.log("DEXRouter:", await router.getAddress());

  const LaunchpadFactory = await ethers.getContractFactory("LaunchpadFactory");
  const launchpad = await LaunchpadFactory.deploy(
    deployer.address,
    deployer.address,
    factory,
    wrapped,
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
