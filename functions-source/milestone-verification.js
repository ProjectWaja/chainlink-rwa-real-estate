// ===========================================================================
// Chainlink Functions source — AI construction-milestone verification
// ---------------------------------------------------------------------------
// Runs OFF-CHAIN on the Chainlink DON. Sends an inspection report to an LLM /
// vision model and asks a single, structured question: is the claimed
// construction milestone actually complete? The verdict gates fund release in
// ConstructionEscrow.sol.
//
// Inputs:
//   args[0] = projectId            (string)
//   args[1] = milestoneIndex       (string -> number)
//   args[2] = milestoneTitle       (string, e.g. "Foundation poured & cured")
//   args[3] = reportUrl            (string, link to inspection notes/photos JSON)
//   secrets.apiKey                 (LLM provider key, encrypted on the DON)
//
// Output: a single uint256:
//   bits   0..127  -> verdict       (1 = complete, 0 = not complete)
//   bits 128..255  -> confidence    (0..100)
//
// DETERMINISM: LLMs are non-deterministic by default. We pin temperature: 0,
// demand a strict JSON schema, and round the score — so independent DON nodes
// converge on identical bytes. Without this the request fails DON consensus.
// ===========================================================================

const projectId = args[0];
const milestoneIndex = Number(args[1]);
const milestoneTitle = args[2];
const reportUrl = args[3];

if (!secrets.apiKey) {
  throw Error("Missing LLM apiKey secret");
}

// --- 1. Fetch the inspection report ---------------------------------------
const reportReq = Functions.makeHttpRequest({ url: reportUrl, method: "GET", timeout: 5000 });
const report = await reportReq;
if (report.error) {
  throw Error("Failed to fetch inspection report");
}
const inspection = JSON.stringify(report.data).slice(0, 6000); // bound prompt size

// --- 2. Ask the model, constrained to a strict JSON verdict ---------------
const prompt =
  `You are a strict construction inspector. Milestone "${milestoneTitle}" ` +
  `(index ${milestoneIndex}) for project ${projectId} is claimed complete.\n` +
  `Given this inspection data, decide if it is genuinely complete.\n\n` +
  `INSPECTION:\n${inspection}\n\n` +
  `Respond with ONLY compact JSON: {"complete": <true|false>, "confidence": <0..1>}.`;

const llmReq = Functions.makeHttpRequest({
  url: "https://api.example-llm.com/v1/chat/completions",
  method: "POST",
  headers: {
    Authorization: `Bearer ${secrets.apiKey}`,
    "Content-Type": "application/json",
  },
  data: {
    model: "reasoning-model-v1",
    temperature: 0, // determinism across DON nodes
    response_format: { type: "json_object" },
    messages: [
      { role: "system", content: "You output only valid JSON. No prose." },
      { role: "user", content: prompt },
    ],
  },
  timeout: 9000,
});

const llmRes = await llmReq;
if (llmRes.error) {
  throw Error("LLM request failed");
}

// --- 3. Parse the structured verdict --------------------------------------
let parsed;
try {
  const content = llmRes.data.choices[0].message.content;
  parsed = JSON.parse(content);
} catch (e) {
  throw Error("LLM returned non-JSON content");
}

const verdict = parsed.complete === true ? 1 : 0;
const confidence = Math.max(0, Math.min(100, Math.round((parsed.confidence ?? 0) * 100)));

// --- 4. Pack (confidence << 128) | verdict --------------------------------
const packed = (BigInt(confidence) << 128n) | BigInt(verdict);

return Functions.encodeUint256(packed);
