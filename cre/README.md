# CRE workflow scaffold

This folder contains a **conceptual** Chainlink Runtime Environment (CRE) workflow for
Cornerstone's NAV update. See [`../docs/cre.md`](../docs/cre.md) for the why.

> ⚠️ **The CRE SDK is new and its API is evolving.** The file here is a heavily-annotated
> *scaffold*: each step is labelled with its **intent** (`TRIGGER`, `HTTP FETCH`, `COMPUTE`,
> `EVM WRITE`) so you can map it onto whatever the current CRE SDK names these primitives.
> It is intentionally not pinned to a specific SDK version and is not wired into the Hardhat
> build. Check the official CRE docs for the exact, current imports and runner.

## What the workflow does

It expresses, as a *single* program, the multi-step NAV refresh that this repo otherwise
implements across separate Functions + Data Feeds + Automation contracts:

1. **TRIGGER** — a cron schedule (e.g. weekly) fires the workflow.
2. **HTTP FETCH** — call the AI/AVM valuation API for each tracked property.
3. **HTTP FETCH** — read the latest attested reserve figure.
4. **COMPUTE** — validate: is the new NAV within tolerance of the last NAV? Reserves ≥ supply?
5. **EVM WRITE** — write the new NAV to `RealEstateNAV` on the primary chain.
6. **EVM WRITE** — if reserves fall short, call `pauseMinting()` on `PropertyToken` across chains.

## Compare the two approaches

| | "Wire it yourself" (implemented) | CRE workflow (this scaffold) |
|---|---|---|
| Trigger | `RentalDistributor`/Automation upkeep | workflow `cron` trigger |
| AI call | `PropertyValuationConsumer` + DON | `http` capability in-workflow |
| Validation | Solidity in the consumer | plain TypeScript in the workflow |
| On-chain write | `fulfillRequest` callback | `evm.write` capability |
| Cross-chain action | separate CCIP message | another `evm` target, same workflow |

The mature, runnable-today version lives in the `contracts/` tree; this scaffold shows how the
same logic collapses into one orchestrated workflow once you adopt CRE.
