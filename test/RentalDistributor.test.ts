import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// Chainlink Automation drives a scheduled, pull-based pro-rata income distribution.
describe("RentalDistributor (Chainlink Automation)", () => {
  const E18 = 10n ** 18n;
  const INTERVAL = 100n;

  async function deploy() {
    const [owner, alice, bob] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MockERC20");
    const shareToken = await Token.deploy("Cornerstone Property A", "CPA", 18);
    const incomeToken = await Token.deploy("USD Coin", "USDC", 18);

    // 60 / 40 ownership split
    await shareToken.mint(alice.address, 60n * E18);
    await shareToken.mint(bob.address, 40n * E18);

    const Dist = await ethers.getContractFactory("RentalDistributor");
    const dist = await Dist.deploy(await shareToken.getAddress(), await incomeToken.getAddress(), INTERVAL);

    // owner deposits 1000 of rental income
    await incomeToken.mint(owner.address, 1000n * E18);
    await incomeToken.approve(await dist.getAddress(), 1000n * E18);
    await dist.depositIncome(1000n * E18);

    return { owner, alice, bob, shareToken, incomeToken, dist };
  }

  it("does not distribute before the interval elapses", async () => {
    const { dist } = await deploy();
    const [needed] = await dist.checkUpkeep("0x");
    expect(needed).to.equal(false);
    await expect(dist.performUpkeep("0x")).to.be.revertedWithCustomError(dist, "NotReady");
  });

  it("distributes pro-rata after the interval and lets holders claim", async () => {
    const { dist, incomeToken, alice, bob } = await deploy();
    await time.increase(Number(INTERVAL) + 10);

    const [needed] = await dist.checkUpkeep("0x");
    expect(needed).to.equal(true);
    await dist.performUpkeep("0x");

    expect(await dist.claimable(alice.address)).to.equal(600n * E18);
    expect(await dist.claimable(bob.address)).to.equal(400n * E18);

    await dist.connect(alice).claim();
    expect(await incomeToken.balanceOf(alice.address)).to.equal(600n * E18);
    // claiming twice yields nothing
    await expect(dist.connect(alice).claim()).to.be.revertedWithCustomError(dist, "NothingToClaim");

    await dist.connect(bob).claim();
    expect(await incomeToken.balanceOf(bob.address)).to.equal(400n * E18);
  });
});
