/**
 * ===========================================================================
 * Cornerstone — NAV update workflow (CRE scaffold)
 * ---------------------------------------------------------------------------
 * CONCEPTUAL, NOT PINNED TO A SPECIFIC CRE SDK VERSION.
 *
 * Each step is tagged with its INTENT so you can map it onto the current CRE
 * SDK primitives:
 *   [TRIGGER]    something starts the workflow (cron / on-chain log)
 *   [HTTP FETCH] off-chain network call (AI/AVM, reserve attestation)
 *   [COMPUTE]    plain off-chain logic / validation
 *   [EVM WRITE]  a verified write back to a chain
 *
 * Replace the `cre.*` placeholder calls below with the real SDK equivalents
 * from the official CRE documentation.
 * ===========================================================================
 */

// NOTE: placeholder import — swap for the real CRE SDK package/exports.
// import { cre, Runner } from "@chainlink/cre-sdk";
declare const cre: any;

// ---- Configuration (would come from the workflow's config file) ----------
interface NavConfig {
  properties: { id: string; address: string; sqft: number; beds: number; baths: number }[];
  avmUrl: string;
  reserveUrl: string;
  navContract: { chainSelector: string; address: string };
  propertyToken: { chainSelector: string; address: string }[]; // possibly multi-chain
  maxDeviationBps: number; // e.g. 1000 = 10%
}

/** [COMPUTE] Bound how far a single update may move the recorded NAV. */
function withinTolerance(prev: bigint, next: bigint, maxBps: number): boolean {
  if (prev === 0n) return true; // first observation
  const diff = next > prev ? next - prev : prev - next;
  return (diff * 10_000n) / prev <= BigInt(maxBps);
}

/**
 * The workflow handler. In CRE this is registered against a trigger and run by
 * the runtime; here it reads as a straight-line async function for clarity.
 */
async function onNavUpdate(config: NavConfig, runtime: any) {
  let totalNavUsd = 0n;

  for (const property of config.properties) {
    // [HTTP FETCH] Ask the AI/AVM model for a fresh valuation.
    const avm = await cre.http.fetch(runtime, {
      url: config.avmUrl,
      method: "POST",
      body: JSON.stringify({
        address: property.address,
        squareFeet: property.sqft,
        bedrooms: property.beds,
        bathrooms: property.baths,
      }),
      // secrets (API keys) are referenced from the secure store, never inlined:
      headers: { Authorization: `Bearer ${cre.secrets.get("AVM_API_KEY")}` },
    });

    const valuationUsd = BigInt(Math.round(avm.json().valuationUsd));

    // [COMPUTE] Read the last on-chain NAV for this property to bound the move.
    const prevNav = await cre.evm.read(runtime, {
      chainSelector: config.navContract.chainSelector,
      address: config.navContract.address,
      function: "propertyValueUsd",
      args: [property.id],
    });

    if (!withinTolerance(BigInt(prevNav), valuationUsd, config.maxDeviationBps)) {
      // [COMPUTE] Out-of-tolerance move: flag for human/multisig review instead
      // of auto-applying. Skip writing this property this cycle.
      runtime.log(`Property ${property.id} NAV move exceeds tolerance — flagged.`);
      continue;
    }

    // [EVM WRITE] Persist the validated valuation on the primary chain.
    await cre.evm.write(runtime, {
      chainSelector: config.navContract.chainSelector,
      address: config.navContract.address,
      function: "setPropertyValueUsd",
      args: [property.id, valuationUsd.toString()],
    });

    totalNavUsd += valuationUsd;
  }

  // [HTTP FETCH] Pull the attested reserve figure.
  const reserve = await cre.http.fetch(runtime, { url: config.reserveUrl, method: "GET" });
  const attestedReservesUsd = BigInt(Math.round(reserve.json().reservesUsd));

  // [COMPUTE] Solvency check across the portfolio.
  if (attestedReservesUsd < totalNavUsd) {
    // [EVM WRITE] Reserves no longer cover NAV — pause minting everywhere.
    for (const token of config.propertyToken) {
      await cre.evm.write(runtime, {
        chainSelector: token.chainSelector,
        address: token.address,
        function: "pauseMinting",
        args: [],
      });
    }
    runtime.log("Reserves < NAV: minting paused on all chains.");
  }
}

/**
 * [TRIGGER] Register the handler against a cron trigger. The exact registration
 * API depends on the CRE SDK version — this shows the intent.
 */
export function initWorkflow(config: NavConfig) {
  return cre.workflow({
    triggers: [cre.cron({ schedule: "0 9 * * 1" })], // every Monday 09:00 UTC
    handler: (runtime: any) => onNavUpdate(config, runtime),
  });
}
