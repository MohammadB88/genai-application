// sustained_avg_load.js
// Simulates observed average usage: ~64 req/min over a sustained period
// Target: 961 requests / 15 min window (~64 req/min)
//
// Uses k6/x/sse (auto-resolved by k6 >= v1.2, no custom xk6 build needed)
// to measure real streaming metrics instead of approximating from total
// request duration:
//   1. TTFT              -> time from request start to first SSE content chunk
//   2. Generation tput   -> tokens/sec AFTER the first token (pure decode speed)
//   3. End-to-end tput   -> tokens/sec over the WHOLE request (what the user feels)
//
// Prerequisites:
//   - k6 >= v1.2 in the runner image (k6-operator's K6 CR `image` field)
//   - Outbound network access from runner pods to k6's extension
//     resolution service (first-run only, to provision k6/x/sse)
//   - Endpoint must support stream: true (OpenAI/vLLM-style SSE)
//   - Ideally supports stream_options.include_usage for exact token counts;
//     otherwise falls back to counting content chunks (~1 token/chunk)

import sse from "k6/x/sse";
import { check, sleep } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";
import { SharedArray } from "k6/data";

const TTFT = new Trend("ttft_ms", true);                 // time to first token
const genTokensPerSec = new Trend("gen_tokens_per_sec");  // post-first-token decode speed
const e2eTokensPerSec = new Trend("e2e_tokens_per_sec");  // user-perceived throughput
const totalLatency = new Trend("total_latency_ms", true); // full request wall time
const errorRate = new Rate("error_rate");
const totalTokens = new Counter("total_output_tokens");

// --- CONFIG ---
const BASE_URL = __ENV.BASE_URL || "https://your-model-endpoint";
const API_KEY = __ENV.API_KEY || "your-api-key";
const MODEL = __ENV.MODEL || "gpt-oss-120b";

// Loaded once at init time and shared across all VUs
const PROMPTS = new SharedArray("prompts", function () {
  return JSON.parse(open("./prompts.json"));
});

export const options = {
  scenarios: {
    sustained_load: {
      executor: "constant-arrival-rate",
      rate: 64,           // requests per minute (~average observed)
      timeUnit: "1m",
      duration: "20m",     // run longer than 15 min to capture steady state
      preAllocatedVUs: 80,
      maxVUs: 120,
    },
  },
  thresholds: {
    ttft_ms: ["p(95)<5000"],            // TTFT p95 < 5s
    total_latency_ms: ["p(95)<30000"],  // Total p95 < 30s
    error_rate: ["rate<0.01"],          // < 1% errors
  },
};

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];

  const payload = JSON.stringify({
    model: MODEL,
    messages: [
      { role: "system", content: prompt.system },
      { role: "user", content: prompt.user },
    ],
    max_tokens: 2800,           // matches observed avg output token count
    stream: true,
    stream_options: { include_usage: true }, // exact token counts in final chunk, if supported
  });

  const params = {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${API_KEY}`,
    },
    body: payload,
    timeout: "60s",
  };

  let firstTokenAt = null;
  let usageTokens = 0;
  let sawUsage = false;
  let chunkCount = 0;     // fallback approx token count if no usage block
  let gotAnyContent = false;

  const startedAt = Date.now();

  const res = sse.open(`${BASE_URL}/v1/chat/completions`, params, function (client) {
    client.on("event", function (event) {
      if (!event.data || event.data === "[DONE]") return;

      let chunk;
      try {
        chunk = JSON.parse(event.data);
      } catch (e) {
        return; // skip malformed/partial chunk
      }

      const delta = chunk.choices && chunk.choices[0] && chunk.choices[0].delta;
      if (delta && delta.content) {
        if (firstTokenAt === null) {
          firstTokenAt = Date.now();
          TTFT.add(firstTokenAt - startedAt);
        }
        gotAnyContent = true;
        chunkCount += 1; // ~1 token per chunk for most OpenAI-compatible backends
      }

      if (chunk.usage) {
        usageTokens = chunk.usage.completion_tokens || usageTokens;
        sawUsage = true;
      }
    });

    client.on("error", function (e) {
      console.log("SSE error:", e.error());
    });
  });

  const endedAt = Date.now();
  const ok = check(res, { "status 200": (r) => r && r.status === 200 }) && gotAnyContent;
  errorRate.add(!ok);

  if (ok) {
    const outputTokens = sawUsage ? usageTokens : chunkCount;
    totalTokens.add(outputTokens);

    const totalDuration = endedAt - startedAt;     // TTFT + generation
    const decodeDuration = endedAt - firstTokenAt;  // generation-only window

    totalLatency.add(totalDuration);

    if (decodeDuration > 0 && outputTokens > 1) {
      // first token's time is already captured in TTFT, so measure the
      // remaining tokens over the decode-only window
      genTokensPerSec.add(((outputTokens - 1) / decodeDuration) * 1000);
    }
    if (totalDuration > 0 && outputTokens > 0) {
      e2eTokensPerSec.add((outputTokens / totalDuration) * 1000);
    }
  }

  // Think time: users average <1 req/min — simulate reading/processing time
  sleep(Math.random() * 10 + 5); // 5–15s think time between requests per VU
}
