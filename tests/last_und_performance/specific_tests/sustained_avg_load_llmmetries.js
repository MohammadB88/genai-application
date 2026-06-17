// sustained_llm_load_streaming.js
//
// Sustained LLM load test
// Measures:
// 1. TTFT
// 2. Pure generation tokens/sec
// 3. End-to-end tokens/sec
//
// Target: ~64 requests/min sustained

import http from "k6/http";
import { check, sleep } from "k6";
import { Trend, Rate, Counter } from "k6/metrics";
import { SharedArray } from "k6/data";


// -------------------------
// Metrics
// -------------------------

const llmTTFT = new Trend("llm_ttft_ms", true);
const generationTokensPerSec = new Trend("llm_generation_tokens_per_sec", true);
const e2eTokensPerSec = new Trend("llm_e2e_tokens_per_sec", true);
const errorRate = new Rate("llm_error_rate");
const totalOutputTokens = new Counter("llm_total_output_tokens");

// -------------------------
// Config
// -------------------------

const BASE_URL = __ENV.BASE_URL || "https://your-model-endpoint";
const API_KEY = __ENV.API_KEY || "your-api-key";
const MODEL = __ENV.MODEL || "gpt-oss-120b";

// -------------------------
// Prompts
// -------------------------

const PROMPTS = new SharedArray("prompts", function () {
    return JSON.parse(open("./prompts.json"));
  });

// -------------------------
// Load profile
// -------------------------

export const options = {
  scenarios: {
    sustained_load: {
      executor: "constant-arrival-rate",
      rate: 64,
      timeUnit: "1m",
      duration: "20m",
      preAllocatedVUs: 80,
      maxVUs: 120,
    },
  },

  thresholds: { 
    llm_ttft_ms: ["p(95)<5000"], 
    http_req_duration: ["p(95)<30000"], 
    llm_error_rate: ["rate<0.01"] },
};

// -------------------------
// Test function
// -------------------------

export default function () {
  const prompt = PROMPTS[Math.floor(Math.random() * PROMPTS.length)];

  const payload = JSON.stringify({
    model: MODEL,
    messages: [
      { role: "system", content: prompt.system },
      { role: "user", content: prompt.user },
    ],
    max_tokens: 1400,
    // IMPORTANT
    stream: true
  });

  const params = {
    headers: {
      "Content-Type": "application/json",
      Authorization:  `Bearer ${API_KEY}`
    },
    timeout: "60s"
  };

  const requestStart = Date.now();
  const res = http.post(`${BASE_URL}/v1/chat/completions`, payload, params);

  const requestEnd = Date.now();

  const ok = check(res, {
    "status 200": (r) => r.status === 200,
    "has choices": (r) => {
      try { return JSON.parse(r.body).choices?.length > 0; } catch { return false; }
    },
  });

  errorRate.add(!ok);

  if (!ok) {return;}

  let firstTokenTime = null;
  let lastTokenTime = null;
  let outputTokens = 0;

  // -------------------------
  // Parse SSE stream
  // -------------------------

  const lines =
    res.body.split("\n");

  for (const line of lines) {
    if (!line.startsWith("data:")) { continue; }
    if (line.includes("[DONE]")) { continue; }

    const now = Date.now();

    if (!firstTokenTime) {
      firstTokenTime = now;
    }

    lastTokenTime = now;

    try {
      const chunk = JSON.parse(line.replace("data:", "").trim());
      const delta = chunk?.choices?.[0]?.delta?.content;

      if (delta) outputTokens++; // approximation: one streamed chunk ~= token

    }

    catch(e) {
      // ignore malformed chunks
    }
  }

  // -------------------------
  // Metrics
  // -------------------------

  if (
    firstTokenTime &&
    lastTokenTime &&
    outputTokens > 0

  ) {

    const ttft = firstTokenTime - requestStart;
    llmTTFT.add(ttft);

    const generationTime = lastTokenTime - firstTokenTime;
    if (generationTime > 0) {
      generationTokensPerSec.add((outputTokens / generationTime) * 1000);
    }

    const totalTime = requestEnd - requestStart;
    e2eTokensPerSec.add((outputTokens / totalTime) * 1000);

    totalOutputTokens.add(outputTokens);

  }

  // only controls VU reuse
  sleep(Math.random() * 10 + 5);

}
