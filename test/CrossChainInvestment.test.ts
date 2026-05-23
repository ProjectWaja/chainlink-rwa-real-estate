import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";

// Chainlink CCIP: cross-chain investment carrying tokens + data, gated by allowlists.
describe("CrossChainInvestment (Chainlink CCIP)", () => {
  const DEST_SELECTOR = 1n;
  const SOURCE_SELECTOR = 2n;
  const FEE = 10n ** 18n; // 1 LINK
  const USDC = (n: number | bigint) => BigInt(n) * 10n ** 6n;
  const PROPERTY = ethers.id("PROP-CCIP");

  async function deploy() {
    const [owner, alice] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    const link = await Token.deploy("Chainlink", "LINK", 18);
    const usdc = await Token.deploy("USD Coin", "USDC", 6);

    const Router = await ethers.getContractFactory("MockCCIPRouter");
    const router = await Router.deploy(FEE);
    await router.setSourceChainSelector(SOURCE_SELECTOR);

    const CCI = await ethers.getContractFactory("CrossChainInvestment");
    const source = await CCI.deploy(await router.getAddress(), await link.getAddress());
    const dest = await CCI.deploy(await router.getAddress(), await link.getAddress());

    // configure allowlists
    await source.allowlistDestinationChain(DEST_SELECTOR, true);
    await dest.allowlistSourceChain(SOURCE_SELECTOR, true);
    await dest.allowlistSender(await source.getAddress(), true);

    // fund the source with LINK for fees; give alice USDC to invest
    await link.mint(await source.getAddress(), FEE);
    await usdc.mint(alice.address, USDC(1000));
    await usdc.connect(alice).approve(await source.getAddress(), USDC(1000));

    return { owner, alice, link, usdc, router, source, dest };
  }

  it("delivers tokens + data cross-chain and credits the beneficiary", async () => {
    const { alice, link, usdc, router, source, dest } = await deploy();

    await source
      .connect(alice)
      .sendInvestment(DEST_SELECTOR, await dest.getAddress(), await usdc.getAddress(), USDC(1000), PROPERTY, alice.address);

    expect(await dest.pendingInvestment(PROPERTY, alice.address)).to.equal(USDC(1000));
    expect(await usdc.balanceOf(await dest.getAddress())).to.equal(USDC(1000));
    expect(await link.balanceOf(await router.getAddress())).to.equal(FEE); // fee collected
  });

  it("reverts when sending to a non-allowlisted destination chain", async () => {
    const { alice, usdc, source, dest } = await deploy();
    await expect(
      source
        .connect(alice)
        .sendInvestment(99n, await dest.getAddress(), await usdc.getAddress(), USDC(10), PROPERTY, alice.address)
    ).to.be.revertedWithCustomError(source, "DestinationChainNotAllowlisted");
  });

  it("reverts on receive when the sender is not allowlisted", async () => {
    const { owner, alice, link, usdc, router } = await deploy();
    const CCI = await ethers.getContractFactory("CrossChainInvestment");
    const source2 = await CCI.deploy(await router.getAddress(), await link.getAddress());
    const dest2 = await CCI.deploy(await router.getAddress(), await link.getAddress());

    await source2.allowlistDestinationChain(DEST_SELECTOR, true);
    await dest2.allowlistSourceChain(SOURCE_SELECTOR, true);
    // NOTE: deliberately not allowlisting source2 as a sender on dest2

    await link.mint(await source2.getAddress(), FEE);
    await usdc.mint(alice.address, USDC(10));
    await usdc.connect(alice).approve(await source2.getAddress(), USDC(10));

    await expect(
      source2
        .connect(alice)
        .sendInvestment(DEST_SELECTOR, await dest2.getAddress(), await usdc.getAddress(), USDC(10), PROPERTY, alice.address)
    ).to.be.revertedWithCustomError(dest2, "SenderNotAllowlisted");
  });
});
