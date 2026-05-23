import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// Proof of Reserve: minting is capped by attested reserves; fail-closed on bad/stale feeds.
describe("PropertyToken (Chainlink Proof of Reserve)", () => {
  const HEARTBEAT = 86400n;
  const DEC = 8;
  const PRICE_PER_TOKEN_USD = 100n; // $100 per token
  // $1,000,000 of reserves -> backs 10,000 tokens at $100 each.
  const RESERVES = 1_000_000n * 10n ** 8n;

  async function deploy() {
    const [owner, alice] = await ethers.getSigners();
    const Feed = await ethers.getContractFactory("MockAggregatorV3");
    const por = await Feed.deploy(DEC, RESERVES, "Cornerstone PoR");
    const Token = await ethers.getContractFactory("PropertyToken");
    const token = await Token.deploy(
      "Cornerstone Property A",
      "CPA",
      await por.getAddress(),
      HEARTBEAT,
      PRICE_PER_TOKEN_USD
    );
    return { owner, alice, por, token };
  }

  it("computes max backed supply from reserves", async () => {
    const { token } = await deploy();
    expect(await token.maxBackedSupply()).to.equal(10_000n * 10n ** 18n);
  });

  it("mints up to the reserve cap and reverts beyond it", async () => {
    const { token, alice } = await deploy();
    const cap = 10_000n * 10n ** 18n;
    await token.mint(alice.address, cap);
    expect(await token.totalSupply()).to.equal(cap);
    await expect(token.mint(alice.address, 1n)).to.be.revertedWithCustomError(token, "ExceedsReserves");
  });

  it("allows more minting after reserves increase", async () => {
    const { token, por, alice } = await deploy();
    await token.mint(alice.address, 10_000n * 10n ** 18n);
    await por.setAnswer(2_000_000n * 10n ** 8n); // reserves doubled
    await token.mint(alice.address, 10_000n * 10n ** 18n); // now 20,000 backed
    expect(await token.totalSupply()).to.equal(20_000n * 10n ** 18n);
  });

  it("blocks minting when the PoR feed is stale", async () => {
    const { token, por, alice } = await deploy();
    const now = BigInt(await time.latest());
    await por.setAnswerWithTimestamp(RESERVES, now - HEARTBEAT - 10n);
    await expect(token.mint(alice.address, 1n)).to.be.revertedWithCustomError(token, "StaleReserves");
  });

  it("blocks minting when paused, and always allows burning", async () => {
    const { token, alice } = await deploy();
    await token.mint(alice.address, 1000n * 10n ** 18n);
    await token.pauseMinting();
    await expect(token.mint(alice.address, 1n)).to.be.revertedWithCustomError(token, "MintingIsPaused");
    // burning is never blocked
    await token.connect(alice).burn(500n * 10n ** 18n);
    expect(await token.totalSupply()).to.equal(500n * 10n ** 18n);
  });
});
