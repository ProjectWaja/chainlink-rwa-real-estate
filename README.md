# Chainlink × RWA: Real Estate & Construction Reference

A hands-on reference architecture showing **how to combine Chainlink products to build a
real-world-asset (RWA) system** — using tokenized real estate and construction finance as a
single, coherent example. Instead of isolated demos, every contract plays a role in one
believable platform: **Cornerstone**.

> ⚠️ **Educational reference only.** Not audited, not production code, and not legal/financial
> advice. See [`SECURITY.md`](./SECURITY.md). Real RWA issuance involves securities law, KYC/AML,
> custody, and licensed appraisers far beyond what any smart contract handles.

---

## What it demonstrates

| Chainlink product | Where it's used in Cornerstone | Contract | Guide |
|---|---|---|---|
| **Data Feeds** | USD ⇆ crypto conversion, NAV denomination | `oracle/RealEstateNAV.sol` | [data-feeds.md](./docs/data-feeds.md) |
| **Proof of Reserve** | Block minting of unbacked property tokens | `token/PropertyToken.sol` | [proof-of-reserve.md](./docs/proof-of-reserve.md) |
| **Functions + AI** | AI/AVM property valuation & milestone checks | `functions/PropertyValuationConsumer.sol` | [functions-and-ai.md](./docs/functions-and-ai.md) |
| **Automation** | Scheduled rent payouts, milestone deadlines | `distribution/RentalDistributor.sol`, `escrow/ConstructionEscrow.sol` | [automation.md](./docs/automation.md) |
| **CCIP** | Cross-chain investment (tokens + data) | `ccip/CrossChainInvestment.sol` | [ccip.md](./docs/ccip.md) |
| **VRF** | Fair allocation of oversubscribed sales | `vrf/AllocationLottery.sol` | [vrf.md](./docs/vrf.md) |
| **Data Streams** | Low-latency settlement (upgrade path) | — (documented) | [data-streams.md](./docs/data-streams.md) |
| **CRE** | Orchestrate the whole NAV workflow | `cre/` (scaffold) | [cre.md](./docs/cre.md) |

The AI angle lives in [`functions-source/`](./functions-source) — the off-chain JavaScript the
Chainlink DON runs to call an AVM/LLM, with the determinism and safety notes that make calling
an AI model from a contract actually work.

---

## The example: Cornerstone

Cornerstone tokenizes income-producing real estate **and** finances the construction that
creates it. Both halves depend on trustworthy off-chain truth — valuations, reserve
attestations, milestone completion, FX rates — which is exactly what Chainlink provides.

```
  ORIGINATION ───► CONSTRUCTION ───► VALUATION ───► OPERATION
  PoR caps the     escrow releases   AI/AVM via      rent streamed pro-rata
  token mint       on AI-verified    Functions →     (Automation); cross-chain
  to reserves      milestones        on-chain NAV    investors via CCIP; fair
                   (Automation        (Data Feeds)   sales via VRF
                    deadlines)
```

Read the full narrative in [`docs/use-case.md`](./docs/use-case.md) and the system design in
[`docs/architecture.md`](./docs/architecture.md).

---

## Quickstart

```bash
# 1. Install
npm install

# 2. Compile the contracts
npm run build

# 3. Run the test suite (fully local — no testnet or API keys needed)
npm test
```

The tests use lightweight mocks that invoke the Chainlink callbacks directly, so the whole
suite runs offline. To deploy against **real** Chainlink services on a testnet, copy
`.env.example` to `.env`, fill it in, and follow [`docs/deployment.md`](./docs/deployment.md).

---

## Repository layout

```
contracts/        Solidity, one product area per folder (token, oracle, functions,
                  escrow, distribution, ccip, vrf) + mocks/
functions-source/ Off-chain JS the Chainlink DON runs (the "AI" calls)
cre/              Chainlink Runtime Environment workflow scaffold (conceptual)
scripts/          Deploy & ops scripts
test/             One test suite per contract
docs/             One guide per Chainlink product
```

---

## Learning path

New to this? Read in order:

1. [`docs/use-case.md`](./docs/use-case.md) — the business problem and why oracles are needed
2. [`docs/proof-of-reserve.md`](./docs/proof-of-reserve.md) — the core RWA honesty mechanism
3. [`docs/data-feeds.md`](./docs/data-feeds.md) — reading prices safely
4. [`docs/functions-and-ai.md`](./docs/functions-and-ai.md) — bringing AI/off-chain data on-chain
5. [`docs/automation.md`](./docs/automation.md) → [`ccip.md`](./docs/ccip.md) → [`vrf.md`](./docs/vrf.md)
6. [`docs/cre.md`](./docs/cre.md) — orchestrating it all

---

## Disclaimer & license

This project is unaffiliated with Chainlink Labs. "Chainlink" and product names belong to their
owners. Provided for educational purposes under the [MIT License](./LICENSE) with no warranty.
See [`SECURITY.md`](./SECURITY.md) before doing anything beyond learning.
