const { expect } = require("chai");
const { ethers } = require("hardhat");

async function deployCore() {
  const [deployer, alice, bob] = await ethers.getSigners();
  const WpETH = await ethers.getContractFactory("WpETH");
  const wrapped = await WpETH.deploy();
  const DEXFactory = await ethers.getContractFactory("DEXFactory");
  const factory = await DEXFactory.deploy(await wrapped.getAddress(), await deployer.getAddress());
  const LaunchpadFactory = await ethers.getContractFactory("LaunchpadFactory");
  const launchpad = await LaunchpadFactory.deploy(
    await deployer.getAddress(),
    await deployer.getAddress(),
    factory,
    wrapped,
    ethers.parseEther("4"),
    400,
    500,
    100
  );
  const DEXRouter = await ethers.getContractFactory("DEXRouter");
  const router = await DEXRouter.deploy(factory, wrapped);
  await factory.setFeeRecipient(await deployer.getAddress());
  return { deployer, alice, bob, wrapped, factory, launchpad, router };
}

describe("Launchpad end-to-end", function () {
  it("bootstraps a launch and triggers graduation", async function () {
    const { deployer, alice, launchpad, factory } = await deployCore();
    const tx = await launchpad.connect(alice).createLaunch("Alpha", "ALPHA", { value: ethers.parseEther("5") });
    const receipt = await tx.wait();
    const event = receipt.logs.find((log) => log.fragment?.name === "LaunchCreated");
    const launchId = event.args[0];
    const token = await ethers.getContractAt("LaunchToken", event.args[2]);
    const curve = await ethers.getContractAt("BondingCurve", event.args[3]);

    await expect(curve.connect(alice).buy(0, await alice.getAddress(), { value: ethers.parseEther("1") }))
      .to.emit(curve, "Buy");

    await token.connect(alice).approve(await curve.getAddress(), ethers.MaxUint256);
    await expect(curve.connect(alice).sell(ethers.parseEther("1"), 0, await alice.getAddress()))
      .to.emit(curve, "Sell");

    // Force graduation via buys
    await curve.connect(deployer).buy(0, await deployer.getAddress(), { value: ethers.parseEther("3") });
    await expect(curve.connect(alice).manualGraduate()).to.emit(curve, "Graduated");

    const pairAddress = await factory.getPair(await token.getAddress());
    expect(pairAddress).to.not.equal(ethers.ZeroAddress);
    expect(await token.tradingEnabled()).to.equal(true);
    await expect(launchpad.notifyGraduation(launchId)).to.be.revertedWith("OnlyCurve");
  });
});
