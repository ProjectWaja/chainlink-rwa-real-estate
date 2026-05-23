// ===========================================================================
// Upload the AI/AVM API key to the Chainlink Functions DON as an *encrypted*
// secret, so it is never placed on-chain. Returns the DON-hosted slot/version
// you then pass to PropertyValuationConsumer.setDonHostedSecrets(slotId, version).
//
//   npx hardhat run scripts/upload-functions-secrets.ts --network sepolia
//
// This step uses the Chainlink Functions toolkit, which pulls native crypto
// dependencies and is therefore NOT a default dependency of this repo (so the
// core `npm install` stays build-tool-free). Install it on demand:
//
//   npm install --save-dev @chainlink/functions-toolkit
//
// Then fill in the network's Functions router / DON id / gateway URLs below
// from https://docs.chain.link/chainlink-functions/supported-networks
// ===========================================================================
import { ethers, network } from "hardhat";

async function main() {
  let SecretsManager: any;
  try {
    // Loaded dynamically so the repo compiles/tests without this dependency.
    ({ SecretsManager } = await import("@chainlink/functions-toolkit"));
  } catch {
    console.error(
      "Missing @chainlink/functions-toolkit.\n" +
        "Install it first:  npm install --save-dev @chainlink/functions-toolkit"
    );
    process.exitCode = 1;
    return;
  }

  const apiKey = process.env.AI_VALUATION_API_KEY;
  if (!apiKey) throw new Error("Set AI_VALUATION_API_KEY in your .env");

  // --- network-specific Functions config (fill from the Chainlink docs) -----
  // Example placeholders for Ethereum Sepolia:
  const CONFIG: Record<string, { router: string; donId: string; gateways: string[] }> = {
    sepolia: {
      router: "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0",
      donId: "fun-ethereum-sepolia-1",
      gateways: [
        "https://01.functions-gateway.testnet.chain.link/",
        "https://02.functions-gateway.testnet.chain.link/",
      ],
    },
  };

  const cfg = CONFIG[network.name];
  if (!cfg) throw new Error(`No Functions config for network "${network.name}". Add it to this script.`);

  const [signer] = await ethers.getSigners();
  const secretsManager = new SecretsManager({
    signer,
    functionsRouterAddress: cfg.router,
    donId: cfg.donId,
  });
  await secretsManager.initialize();

  const encrypted = await secretsManager.encryptSecrets({ apiKey });

  const slotId = 0;
  const expirationMinutes = 24 * 60; // 1 day
  const { version } = await secretsManager.uploadEncryptedSecretsToDON({
    encryptedSecretsHexstring: encrypted.encryptedSecrets,
    gatewayUrls: cfg.gateways,
    slotId,
    minutesUntilExpiration: expirationMinutes,
  });

  console.log(`Uploaded DON-hosted secrets:  slotId=${slotId}  version=${version}`);
  console.log("Now call: PropertyValuationConsumer.setDonHostedSecrets(slotId, version)");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
