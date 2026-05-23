import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import * as dotenv from "dotenv";

dotenv.config();

const {
  SEPOLIA_RPC_URL,
  ARBITRUM_SEPOLIA_RPC_URL,
  BASE_SEPOLIA_RPC_URL,
  PRIVATE_KEY,
  ETHERSCAN_API_KEY,
} = process.env;

// Only attach accounts if a key is present, so `npm test` works with no .env.
const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : [];

const config: HardhatUserConfig = {
  solidity: {
    // Chainlink CCIP/VRF/Functions contracts target 0.8.19+; 0.8.24 covers all.
    compilers: [
      {
        version: "0.8.24",
        settings: {
          optimizer: { enabled: true, runs: 200 },
          evmVersion: "paris", // broad cross-chain compatibility (pre-PUSH0)
        },
      },
    ],
  },
  networks: {
    hardhat: {},
    sepolia: {
      url: SEPOLIA_RPC_URL ?? "",
      accounts,
      chainId: 11155111,
    },
    arbitrumSepolia: {
      url: ARBITRUM_SEPOLIA_RPC_URL ?? "",
      accounts,
      chainId: 421614,
    },
    baseSepolia: {
      url: BASE_SEPOLIA_RPC_URL ?? "",
      accounts,
      chainId: 84532,
    },
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY ?? "",
  },
  mocha: {
    timeout: 120000,
  },
};

export default config;
