import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";

// Chainlink Functions + AI: an off-chain valuation result is delivered, validated, and applied.
describe("PropertyValuationConsumer (Chainlink Functions + AI)", () => {
  const SUB_ID = 1n;
  const DON_ID = ethers.id("don-1");
  const GAS_LIMIT = 300_000;
  const SOURCE = "return Functions.encodeUint256(0);"; // placeholder; the DON runs the real source
  const PROPERTY = ethers.id("PROP-1");
  const ARGS = ["PROP-1", "123 Main St", "2000", "3", "2"];
  const coder = ethers.AbiCoder.defaultAbiCoder();

  function packResponse(valuationUsd: bigint, confidence: bigint): string {
    const packed = (confidence << 128n) | valuationUsd;
    return coder.encode(["uint256"], [packed]);
  }

  async function deploy() {
    const Feed = await ethers.getContractFactory("MockAggregatorV3");
    const ethUsd = await Feed.deploy(8, 2000n * 10n ** 8n, "ETH / USD");
    const NAV = await ethers.getContractFactory("RealEstateNAV");
    const nav = await NAV.deploy(await ethUsd.getAddress(), 3600n);
    const Router = await ethers.getContractFactory("MockFunctionsRouter");
    const router = await Router.deploy();
    const Consumer = await ethers.getContractFactory("PropertyValuationConsumer");
    const consumer = await Consumer.deploy(
      await router.getAddress(),
      await nav.getAddress(),
      SUB_ID,
      DON_ID,
      GAS_LIMIT,
      SOURCE
    );
    await nav.setValuationUpdater(await consumer.getAddress());
    return { nav, router, consumer };
  }

  async function request(consumer: any) {
    const tx = await consumer.requestValuation(PROPERTY, ARGS);
    await tx.wait();
    const events = await consumer.queryFilter(consumer.filters.ValuationRequested());
    return events[events.length - 1].args.requestId as string;
  }

  it("applies a valid, high-confidence valuation to the NAV", async () => {
    const { nav, router, consumer } = await deploy();
    const requestId = await request(consumer);
    await router.fulfill(requestId, packResponse(500_000n, 85n), "0x");

    expect(await nav.propertyValueUsd(PROPERTY)).to.equal(500_000n);
    const v = await consumer.latestValuation(PROPERTY);
    expect(v.applied).to.equal(true);
    expect(v.confidence).to.equal(85n);
  });

  it("rejects a low-confidence valuation", async () => {
    const { nav, router, consumer } = await deploy();
    const requestId = await request(consumer);
    await expect(router.fulfill(requestId, packResponse(500_000n, 50n), "0x"))
      .to.emit(consumer, "ValuationRejected");
    expect(await nav.propertyValueUsd(PROPERTY)).to.equal(0n);
  });

  it("rejects a fulfilment that carries an error", async () => {
    const { nav, router, consumer } = await deploy();
    const requestId = await request(consumer);
    await router.fulfill(requestId, "0x", ethers.toUtf8Bytes("AVM down"));
    expect(await nav.propertyValueUsd(PROPERTY)).to.equal(0n);
  });

  it("flags an out-of-tolerance move for review, then applies on approval", async () => {
    const { nav, router, consumer } = await deploy();

    // first valuation establishes the baseline NAV
    let requestId = await request(consumer);
    await router.fulfill(requestId, packResponse(500_000n, 90n), "0x");
    expect(await nav.propertyValueUsd(PROPERTY)).to.equal(500_000n);

    // +40% move exceeds MAX_DEVIATION_BPS (20%) -> flagged, NAV unchanged
    requestId = await request(consumer);
    await expect(router.fulfill(requestId, packResponse(700_000n, 90n), "0x"))
      .to.emit(consumer, "ValuationFlagged");
    expect(await nav.propertyValueUsd(PROPERTY)).to.equal(500_000n);
    expect(await consumer.flaggedValuationUsd(PROPERTY)).to.equal(700_000n);

    // owner/multisig approves the flagged value
    await consumer.applyFlaggedValuation(PROPERTY);
    expect(await nav.propertyValueUsd(PROPERTY)).to.equal(700_000n);
  });
});
