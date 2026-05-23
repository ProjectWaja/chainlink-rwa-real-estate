// ===========================================================================
// Deploy the full Cornerstone system for a LOCAL demo (mock oracles included).
//
//   npx hardhat run scripts/deploy-core.ts                 # in-process hardhat network
//   npx hardhat run scripts/deploy-core.ts --network sepolia
//
// For a real testnet you should replace the *mock* feed/router/coordinator
// deployments below with the official Chainlink addresses for your network
// (see docs/deployment.md). The contract wiring stays identical — only the
// oracle addresses change.
// ===========================================================================
import { ethers, network } from "hardhat";

async function main() {
  const [deployer, builder] = await ethers.getSigners();
  console.log(`Network:  ${network.name}`);
  console.log(`Deployer: ${deployer.address}\n`);

  // --- 1. Oracles (mocks for local; swap for real addresses on a testnet) ---
  const Agg = await ethers.getContractFactory("MockAggregatorV3");
  const ethUsd = await Agg.deploy(8, 2000n * 10n ** 8n, "ETH / USD");
  const por = await Agg.deploy(8, 1_000_000n * 10n ** 8n, "Cornerstone PoR");
  await ethUsd.waitForDeployment();
  await por.waitForDeployment();

  // --- 2. Data Feeds consumer (NAV) -----------------------------------------
  const NAV = await ethers.getContractFactory("RealEstateNAV");
  const nav = await NAV.deploy(await ethUsd.getAddress(), 3600n);
  await nav.waitForDeployment();

  // --- 3. Proof-of-Reserve-gated property token -----------------------------
  const Token = await ethers.getContractFactory("PropertyToken");
  const token = await Token.deploy(
    "Cornerstone Property A",
    "CPA",
    await por.getAddress(),
    86400n,
    100n // $100 per token
  );
  await token.waitForDeployment();

  // --- 4. Chainlink Functions + AI valuation consumer -----------------------
  const FRouter = await ethers.getContractFactory("MockFunctionsRouter");
  const functionsRouter = await FRouter.deploy();
  await functionsRouter.waitForDeployment();

  const Consumer = await ethers.getContractFactory("PropertyValuationConsumer");
  const consumer = await Consumer.deploy(
    await functionsRouter.getAddress(),
    await nav.getAddress(),
    1n, // subscriptionId (placeholder for local)
    ethers.id("fun-ethereum-sepolia-1"),
    300_000,
    "return Functions.encodeUint256(0); // replace with functions-source/property-valuation.js"
  );
  await consumer.waitForDeployment();
  await (await nav.setValuationUpdater(await consumer.getAddress())).wait();

  // --- 5. Stablecoin used for escrow + rent ---------------------------------
  const ERC20 = await ethers.getContractFactory("MockERC20");
  const usdc = await ERC20.deploy("USD Coin", "USDC", 6);
  await usdc.waitForDeployment();

  // --- 6. Construction escrow (Functions verdict + Automation) --------------
  const Escrow = await ethers.getContractFactory("ConstructionEscrow");
  const escrow = await Escrow.deploy(await usdc.getAddress(), builder.address, deployer.address);
  await escrow.waitForDeployment();

  // --- 7. Rental distributor (Automation, pull-based) -----------------------
  const Dist = await ethers.getContractFactory("RentalDistributor");
  const distributor = await Dist.deploy(await token.getAddress(), await usdc.getAddress(), 30n * 24n * 3600n);
  await distributor.waitForDeployment();

  // --- 8. CCIP cross-chain investment ---------------------------------------
  const CRouter = await ethers.getContractFactory("MockCCIPRouter");
  const ccipRouter = await CRouter.deploy(10n ** 17n);
  await ccipRouter.waitForDeployment();
  const link = await ERC20.deploy("Chainlink", "LINK", 18);
  await link.waitForDeployment();
  const CCI = await ethers.getContractFactory("CrossChainInvestment");
  const crossChain = await CCI.deploy(await ccipRouter.getAddress(), await link.getAddress());
  await crossChain.waitForDeployment();

  // --- 9. VRF allocation lottery --------------------------------------------
  const VRF = await ethers.getContractFactory("MockVRFCoordinator");
  const vrf = await VRF.deploy();
  await vrf.waitForDeployment();
  const Lottery = await ethers.getContractFactory("AllocationLottery");
  const lottery = await Lottery.deploy(await vrf.getAddress(), ethers.id("key-hash"), 1n, 100n);
  await lottery.waitForDeployment();

  // --- summary --------------------------------------------------------------
  console.log("Deployed Cornerstone contracts:");
  const out: Record<string, string> = {
    "ETH/USD feed (mock)": await ethUsd.getAddress(),
    "PoR feed (mock)": await por.getAddress(),
    RealEstateNAV: await nav.getAddress(),
    PropertyToken: await token.getAddress(),
    "FunctionsRouter (mock)": await functionsRouter.getAddress(),
    PropertyValuationConsumer: await consumer.getAddress(),
    "USDC (mock)": await usdc.getAddress(),
    ConstructionEscrow: await escrow.getAddress(),
    RentalDistributor: await distributor.getAddress(),
    "CCIPRouter (mock)": await ccipRouter.getAddress(),
    CrossChainInvestment: await crossChain.getAddress(),
    "VRFCoordinator (mock)": await vrf.getAddress(),
    AllocationLottery: await lottery.getAddress(),
  };
  for (const [name, addr] of Object.entries(out)) {
    console.log(`  ${name.padEnd(28)} ${addr}`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
