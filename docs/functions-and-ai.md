# Chainlink Functions + AI for property valuation

This is where "AI" enters the Cornerstone architecture. Smart contracts cannot call an HTTP
API or run a machine-learning model. **Chainlink Functions** lets a contract request that a
*Decentralized Oracle Network (DON)* run some JavaScript off-chain — including calling an AI
or Automated Valuation Model (AVM) API — and deliver the result back on-chain, with the API
key kept secret on the DON rather than exposed on-chain.

## The pattern

```
  PropertyValuationConsumer.sol            Chainlink DON                 AI / AVM provider
  (on-chain)                               (off-chain)                   (off-chain HTTP API)
        │                                       │                               │
        │  requestValuation(propertyId)         │                               │
        ├──────────────────────────────────────►│                               │
        │   sends JS source + encrypted secrets  │   runs functions-source/      │
        │                                        │   property-valuation.js       │
        │                                        ├──────────────────────────────►│
        │                                        │   POST address + features     │
        │                                        │◄──────────────────────────────┤
        │                                        │   { valuationUsd, confidence }│
        │  fulfillRequest(valuationUsd)          │                               │
        │◄───────────────────────────────────────┤                              │
        │  store + push to RealEstateNAV          │                              │
        ▼                                                                         
```

## Two AI use cases in Cornerstone

### 1. Automated property valuation (AVM)
`functions-source/property-valuation.js` POSTs a property's features (address, square footage,
beds/baths, recent comparable sales) to an AI valuation model and returns a USD figure plus a
confidence score. The contract rejects low-confidence results and bounds how far a single
update may move NAV (a guard against a bad model run or a compromised API).

### 2. Construction-progress verification
`functions-source/milestone-verification.js` sends an inspection report (or the URL of
inspection photos) to a vision/LLM model that returns a structured judgement: *is the claimed
milestone actually complete?* `ConstructionEscrow` only releases milestone funds when this
returns a positive, high-confidence verdict.

## Why this is safe-ish (and where it isn't)

Functions returns the result of a **single DON's** computation. For high-value RWA decisions
you should treat an AI valuation as **one input, not gospel**:

- **Bound the impact.** `PropertyValuationConsumer` caps per-update NAV movement and requires
  a minimum confidence — see `MAX_DEVIATION_BPS` and `MIN_CONFIDENCE` in the contract.
- **Keep humans/multisig in the loop** for large deltas (the contract can flag rather than
  auto-apply a >X% change).
- **Don't put secrets on-chain.** The AI API key is uploaded to the DON as an encrypted
  secret; `.env`'s `AI_VALUATION_API_KEY` is only used by the deploy script to upload it.
- AI output is **non-deterministic**. The JS pins model parameters (temperature 0, a strict
  JSON schema) so independent DON nodes converge on the same answer; without that, nodes may
  disagree and the request fails consensus. This is the single most important thing to get
  right when calling an LLM from Functions.

## Files

| File | Role |
|---|---|
| `contracts/functions/PropertyValuationConsumer.sol` | On-chain `FunctionsClient`: sends the request, validates and stores the result |
| `functions-source/property-valuation.js` | Off-chain source the DON runs to call the AVM/AI API |
| `functions-source/milestone-verification.js` | Off-chain source for AI construction-progress checks |
| `scripts/upload-functions-secrets.ts` | Uploads the encrypted API key to the DON |

See [data-feeds.md](./data-feeds.md) for how the resulting valuation is consumed as NAV.
