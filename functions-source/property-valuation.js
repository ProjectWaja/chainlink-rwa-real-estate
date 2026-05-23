// ===========================================================================
// Chainlink Functions source — AI / AVM property valuation
// ---------------------------------------------------------------------------
// This JavaScript runs OFF-CHAIN on every node of the Chainlink DON. It calls
// an Automated Valuation Model (AVM) / AI pricing API and returns a USD
// valuation plus a confidence score back to PropertyValuationConsumer.sol.
//
// Inputs (provided by the requesting contract):
//   args[0] = propertyId           (string, for logging/traceability)
//   args[1] = addressLine          (string)
//   args[2] = squareFeet           (string -> number)
//   args[3] = beds                 (string -> number)
//   args[4] = baths                (string -> number)
//   secrets.apiKey                 (uploaded encrypted to the DON, NEVER on-chain)
//
// Output: a single uint256 packing two values so the contract can decode both:
//   bits   0..127  -> valuationUsd  (whole US dollars)
//   bits 128..255  -> confidence    (0..100)
//
// DETERMINISM NOTE: every DON node runs this independently and must agree on
// the bytes returned, or the request fails consensus. We round to integers and
// avoid any non-deterministic input (timestamps, randomness, floating noise).
// ===========================================================================

const propertyId = args[0];
const addressLine = args[1];
const squareFeet = Number(args[2]);
const beds = Number(args[3]);
const baths = Number(args[4]);

if (!secrets.apiKey) {
  throw Error("Missing AVM apiKey secret");
}
if (!addressLine || Number.isNaN(squareFeet)) {
  throw Error("Invalid property inputs");
}

// --- Call the AVM / AI valuation provider ---------------------------------
// Replace the URL/shape with your provider (HouseCanary, Quantarium, an
// in-house model, etc.). The example assumes a JSON POST returning
// { valuationUsd: number, confidence: number(0..1) }.
const avmRequest = Functions.makeHttpRequest({
  url: "https://api.example-avm.com/v1/valuation",
  method: "POST",
  headers: {
    Authorization: `Bearer ${secrets.apiKey}`,
    "Content-Type": "application/json",
  },
  data: {
    address: addressLine,
    squareFeet: squareFeet,
    bedrooms: beds,
    bathrooms: baths,
  },
  timeout: 9000,
});

const avmResponse = await avmRequest;

if (avmResponse.error) {
  throw Error(`AVM request failed: ${avmResponse.status ?? "no status"}`);
}

const data = avmResponse.data ?? {};
if (typeof data.valuationUsd !== "number" || typeof data.confidence !== "number") {
  throw Error("AVM returned an unexpected payload shape");
}

// --- Normalise to deterministic integers ----------------------------------
const valuationUsd = Math.round(data.valuationUsd); // whole dollars
const confidence = Math.max(0, Math.min(100, Math.round(data.confidence * 100)));

if (valuationUsd <= 0) {
  throw Error("Non-positive valuation");
}

// --- Pack (confidence << 128) | valuationUsd into one uint256 --------------
const packed = (BigInt(confidence) << 128n) | BigInt(valuationUsd);

return Functions.encodeUint256(packed);
