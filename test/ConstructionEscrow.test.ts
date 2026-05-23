import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// Chainlink Functions verdict + Automation deadlines on a milestone construction escrow.
describe("ConstructionEscrow (Functions verdict + Automation)", () => {
  const USDC = (n: number | bigint) => BigInt(n) * 10n ** 6n;

  async function deploy() {
    const [owner, builder, verifier, funder] = await ethers.getSigners();
    const Token = await ethers.getContractFactory("MockERC20");
    const usdc = await Token.deploy("USD Coin", "USDC", 6);
    const Escrow = await ethers.getContractFactory("ConstructionEscrow");
    const escrow = await Escrow.deploy(await usdc.getAddress(), builder.address, verifier.address);
    return { owner, builder, verifier, funder, usdc, escrow };
  }

  async function setupAndFund() {
    const ctx = await deploy();
    const { escrow, usdc, funder } = ctx;
    const now = BigInt(await time.latest());
    await escrow.addMilestone("Foundation poured", USDC(100), now + 1_000_000n);
    await escrow.addMilestone("Framing inspected", USDC(50), now + 100n);

    await usdc.mint(funder.address, USDC(150));
    await usdc.connect(funder).approve(await escrow.getAddress(), USDC(150));
    await escrow.connect(funder).fund();
    return ctx;
  }

  it("locks funds, confirms a milestone, and releases to the builder", async () => {
    const { escrow, usdc, builder, verifier } = await setupAndFund();
    expect(await usdc.balanceOf(await escrow.getAddress())).to.equal(USDC(150));

    await escrow.connect(verifier).confirmMilestone(0, 92);
    await escrow.releaseMilestone(0);
    expect(await usdc.balanceOf(builder.address)).to.equal(USDC(100));
  });

  it("rejects confirmation from a non-verifier", async () => {
    const { escrow, funder } = await setupAndFund();
    await expect(escrow.connect(funder).confirmMilestone(0, 99))
      .to.be.revertedWithCustomError(escrow, "NotVerifier");
  });

  it("flags an overdue milestone via Automation and lets the funder reclaim", async () => {
    const { escrow, usdc, funder } = await setupAndFund();

    // before the deadline, no upkeep is needed
    let [needed] = await escrow.checkUpkeep("0x");
    expect(needed).to.equal(false);

    await time.increase(500); // past the framing milestone (index 1) deadline
    let performData: string;
    [needed, performData] = await escrow.checkUpkeep("0x");
    expect(needed).to.equal(true);

    await escrow.performUpkeep(performData);
    const m = await escrow.milestones(1);
    expect(m.state).to.equal(3); // State.Overdue

    const before = await usdc.balanceOf(funder.address);
    await escrow.connect(funder).reclaim(1);
    expect(await usdc.balanceOf(funder.address)).to.equal(before + USDC(50));
  });
});
