import "@nomicfoundation/hardhat-chai-matchers";
import { expect } from "chai";
import { ethers } from "hardhat";

// Chainlink VRF: verifiably fair allocation of an oversubscribed sale.
describe("AllocationLottery (Chainlink VRF)", () => {
  const KEY_HASH = ethers.id("key-hash");
  const SUB_ID = 1n;
  const NUM_WINNERS = 2n;

  async function deploy() {
    const signers = await ethers.getSigners();
    const [owner, alice, bob, carol, dave] = signers;

    const Coord = await ethers.getContractFactory("MockVRFCoordinator");
    const coord = await Coord.deploy();

    const Lottery = await ethers.getContractFactory("AllocationLottery");
    const lottery = await Lottery.deploy(await coord.getAddress(), KEY_HASH, SUB_ID, NUM_WINNERS);

    return { owner, alice, bob, carol, dave, coord, lottery };
  }

  it("runs an end-to-end fair draw from a verified seed", async () => {
    const { alice, bob, carol, dave, coord, lottery } = await deploy();

    for (const s of [alice, bob, carol, dave]) {
      await lottery.connect(s).enter();
    }
    expect(await lottery.entrantCount()).to.equal(4n);

    await lottery.closeAndDraw();
    const requestId = await lottery.lastRequestId();
    await coord.fulfillWithWord(requestId, 123_456_789n);

    expect(await lottery.seeded()).to.equal(true);
    const winners = await lottery.drawWinners();
    expect(winners.length).to.equal(2);
    expect(winners[0]).to.not.equal(winners[1]); // distinct winners

    const entrants = [alice.address, bob.address, carol.address, dave.address];
    for (const w of winners) {
      expect(entrants).to.include(w);
    }
    expect(await lottery.isWinner(winners[0])).to.equal(true);
  });

  it("blocks entry after the draw is closed and blocks double entry", async () => {
    const { alice, bob, lottery } = await deploy();
    await lottery.connect(alice).enter();
    await expect(lottery.connect(alice).enter()).to.be.revertedWithCustomError(lottery, "AlreadyEntered");

    await lottery.closeAndDraw();
    await expect(lottery.connect(bob).enter()).to.be.revertedWithCustomError(lottery, "WrongPhase");
  });

  it("is deterministic: the same seed yields the same winners", async () => {
    const { alice, bob, carol, dave, coord, lottery } = await deploy();
    for (const s of [alice, bob, carol, dave]) {
      await lottery.connect(s).enter();
    }
    await lottery.closeAndDraw();
    await coord.fulfillWithWord(await lottery.lastRequestId(), 42n);
    const first = await lottery.drawWinners();
    const second = await lottery.drawWinners();
    expect(first).to.deep.equal(second);
  });
});
