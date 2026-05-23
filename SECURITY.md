# Security notes & disclaimers

> **This repository is an educational reference architecture. It is NOT audited, NOT production
> code, and NOT legal, financial, or investment advice.** Do not deploy it with real user funds.

## What this repo is and isn't

- **Is:** a clear, end-to-end illustration of how Chainlink products (Data Feeds, Proof of
  Reserve, Functions + AI, Automation, CCIP, VRF, CRE) compose into a real-world-asset system.
- **Isn't:** a complete RWA platform. Real tokenized real estate involves securities
  registration, KYC/AML, qualified custodians, licensed appraisers, legal wrappers (SPVs),
  and transfer restrictions — none of which a smart contract resolves on its own.

## The trust assumptions you must not forget

The hardest part of any RWA system is **the off-chain attestation pipeline**, not the Solidity:

| On-chain mechanism | Off-chain assumption it depends on |
|---|---|
| Proof of Reserve mint guard | An honest, audited appraiser/custodian actually attesting reserves |
| AI/AVM valuation via Functions | The model and its training data being fair, current, and not gamed |
| Milestone verification via Functions | The inspection data being authentic (not a doctored report) |
| Rental distribution | Off-chain rent actually being collected and bridged on-chain |

Chainlink decentralizes *delivery and computation* of these signals; it does not make a bad
appraisal good. Garbage in, garbage on-chain.

## Smart-contract safety patterns demonstrated (and their limits)

- **Oracle staleness & decimals checks** (`RealEstateNAV`) — guards against frozen/mis-scaled
  feeds, but cannot detect a feed that is fresh yet wrong.
- **Fail-closed PoR** (`PropertyToken`) — minting halts on any feed error; tune the heartbeat
  to your attestation cadence.
- **Bounded AI impact** (`PropertyValuationConsumer`) — `MAX_DEVIATION_BPS` / `MIN_CONFIDENCE`
  cap how much one model run can move NAV; large moves should route to human/multisig review.
- **CCIP allowlisting** (`CrossChainInvestment`) — only trusted source chains/senders accepted.
- **VRF state-machine guards** (`AllocationLottery`) — no acting before fulfilment, no re-rolls.
- **Pull-over-push distribution** (`RentalDistributor`) — avoids unbounded-loop gas griefing.

## Before any real deployment

1. Get a professional audit.
2. Replace mock feeds/routers with the correct **per-network** Chainlink addresses (see
   [deployment.md](./deployment.md) and the official Chainlink docs).
3. Add access control / pausability / upgrade strategy appropriate to your custody model.
4. Resolve the legal & compliance layer with qualified counsel.

## Reporting

This is a reference repo with no production deployment. If you spot a bug in the example code,
please open a GitHub issue.
