# Deployment & live-testnet guide

The repo runs fully **locally** (`npm test`) with no external services. Taking it to a public
testnet means swapping mocks for real Chainlink services and addresses. This guide is the map.

## 0. Prerequisites

- A funded **testnet** account (Sepolia ETH from a faucet). Use a throwaway key.
- An RPC endpoint (Alchemy/Infura) per network.
- Testnet **LINK** (faucet: <https://faucets.chain.link>) for Functions, VRF, CCIP fees.
- `cp .env.example .env` and fill it in. **Never commit `.env`.**

## 1. Per-network Chainlink addresses

Every Chainlink service has a different address on each chain. **Do not hard-code them** — look
them up in the official docs and pass them at deploy time:

| Service | Where to find the address |
|---|---|
| Data Feeds (ETH/USD, …) | <https://docs.chain.link/data-feeds/price-feeds/addresses> |
| Proof of Reserve feeds | <https://docs.chain.link/data-feeds/proof-of-reserve/addresses> |
| Functions Router + DON ID | <https://docs.chain.link/chainlink-functions/supported-networks> |
| Automation Registry | <https://docs.chain.link/chainlink-automation/overview/supported-networks> |
| CCIP Router + chain selectors | <https://docs.chain.link/ccip/directory> |
| VRF 2.5 Coordinator + key hash | <https://docs.chain.link/vrf/v2-5/supported-networks> |

## 2. Set up the off-chain subscriptions

| Service | Action |
|---|---|
| **Functions** | Create a subscription at <https://functions.chain.link>, fund with LINK, add the deployed `PropertyValuationConsumer` as a consumer. Put the sub id in `.env`. |
| **VRF** | Create a subscription at <https://vrf.chain.link> (v2.5), fund it, add `AllocationLottery` as a consumer. |
| **Automation** | Register a custom-logic upkeep at <https://automation.chain.link> for `RentalDistributor` and `ConstructionEscrow`. |

## 3. Deploy

```bash
npm run build
# example (scripts/ are wired with network config):
npx hardhat run scripts/deploy-core.ts --network sepolia
```

Deploy order matters (later contracts take earlier addresses as constructor args):
1. `RealEstateNAV` (needs ETH/USD + NAV feed addresses)
2. `PropertyToken` (needs the PoR feed address)
3. `PropertyValuationConsumer` (needs Functions router + DON id; gets `RealEstateNAV`)
4. `ConstructionEscrow`, `RentalDistributor`
5. `CrossChainInvestment` (needs CCIP router), `AllocationLottery` (needs VRF coordinator)

## 4. Upload Functions secrets (AI API key)

The AI/AVM API key must live on the DON, **not on-chain**:

```bash
npx hardhat run scripts/upload-functions-secrets.ts --network sepolia
```

This encrypts `AI_VALUATION_API_KEY` and uploads it to the DON gateway, returning a slot/version
your requests reference.

## 5. CCIP across two chains

CCIP needs the contract deployed on **both** the source and destination chains, with each side
allowlisting the other's chain selector and address. Fund the sender with LINK for fees. See
[ccip.md](./ccip.md).

## 6. Going to production

Re-read [`SECURITY.md`](../SECURITY.md). Short version: get audited, resolve the legal/compliance
layer, and replace every mock and assumption with a real, accountable counterpart.
