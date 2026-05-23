import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { time } from "@nomicfoundation/hardhat-network-helpers";

// Data Feeds: USD <-> crypto conversion + per-property NAV, with staleness handling.
describe("RealEstateNAV (Chainlink Data Feeds)", () => {
  const HEARTBEAT = 3600n;
  const DEC = 8;
  const ETH_PRICE = 2000n * 10n ** 8n; // $2000 with 8 decimals

  async function deploy() {
    const [owner, updater, stranger] = await ethers.getSigners();
    const Feed = await ethers.getContractFactory("MockAggregatorV3");
    const ethUsd = await Feed.deploy(DEC, ETH_PRICE, "ETH / USD");
    const NAV = await ethers.getContractFactory("RealEstateNAV");
    const nav = await NAV.deploy(await ethUsd.getAddress(), HEARTBEAT);
    return { owner, updater, stranger, ethUsd, nav };
  }

  it("reads ETH/USD with the right value and decimals", async () => {
    const { nav } = await deploy();
    const [price, decimals] = await nav.getEthUsdPrice();
    expect(price).to.equal(ETH_PRICE);
    expect(decimals).to.equal(DEC);
  });

  it("converts USD <-> wei correctly", async () => {
    const { nav } = await deploy();
    // $2000 == 1 ETH at this price
    expect(await nav.usdToWei(2000n)).to.equal(10n ** 18n);
    expect(await nav.weiToUsd(10n ** 18n)).to.equal(2000n);
  });

  it("reverts on a stale price (fail-closed)", async () => {
    const { nav, ethUsd } = await deploy();
    const now = BigInt(await time.latest());
    await ethUsd.setAnswerWithTimestamp(ETH_PRICE, now - HEARTBEAT - 10n);
    await expect(nav.getEthUsdPrice()).to.be.revertedWithCustomError(nav, "StalePrice");
  });

  it("reverts on a non-positive price", async () => {
    const { nav, ethUsd } = await deploy();
    await ethUsd.setAnswer(0);
    await expect(nav.getEthUsdPrice()).to.be.revertedWithCustomError(nav, "InvalidPrice");
  });

  it("only lets the valuation updater or owner set property NAV", async () => {
    const { nav, owner, updater, stranger } = await deploy();
    const propertyId = ethers.id("PROP-1");

    await expect(nav.connect(stranger).setPropertyValueUsd(propertyId, 500000n))
      .to.be.revertedWithCustomError(nav, "NotValuationUpdater");

    await nav.setValuationUpdater(updater.address);
    await nav.connect(updater).setPropertyValueUsd(propertyId, 500000n);
    expect(await nav.propertyValueUsd(propertyId)).to.equal(500000n);

    // owner can also set
    await nav.connect(owner).setPropertyValueUsd(propertyId, 600000n);
    expect(await nav.propertyValueUsd(propertyId)).to.equal(600000n);
  });
});
