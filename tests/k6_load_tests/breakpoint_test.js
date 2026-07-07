import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const ENDPOINT = __ENV.BP_ENDPOINT || '/v1/completions';
const MODEL = __ENV.BP_MODEL || 'meta/llama-3.2-1b-instruct';
const PROMPT = __ENV.BP_PROMPT || 'Hello, how are you?';
const MAX_TOKENS = __ENV.BP_MAX_TOKENS ? parseInt(__ENV.BP_MAX_TOKENS) : 50;
const MAX_VUS = __ENV.BP_MAX_VUS ? parseInt(__ENV.BP_MAX_VUS) : 2000;
const STEP_VUS = __ENV.BP_STEP_VUS ? parseInt(__ENV.BP_STEP_VUS) : 200;
const STEP_DURATION = __ENV.BP_STEP_DURATION || '2m';
const SLO_MS = __ENV.BP_SLO_MS ? parseInt(__ENV.BP_SLO_MS) : 2000;
const MAX_ERROR_RATE = __ENV.BP_ERROR_RATE ? parseFloat(__ENV.BP_ERROR_RATE) : 0.05;
const API_KEY = __ENV.API_KEY || '';   // placeholder for auth

// Build stages from 0 to MAX_VUS in steps
const stages = [];
for (let vus = STEP_VUS; vus <= MAX_VUS; vus += STEP_VUS) {
  stages.push({ duration: STEP_DURATION, target: vus });
}

export const options = {
  thresholds: {
    http_req_duration: [`p(95) < ${SLO_MS}`],
    http_req_failed: [`rate<${MAX_ERROR_RATE}`],
  },
  scenarios: {
    breakpoint: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: stages,
    },
  },
};

export default function () {
  const url = `${BASE_URL}${ENDPOINT}`;

  const payload = JSON.stringify({
    model: MODEL,
    prompt: PROMPT,
    max_tokens: MAX_TOKENS,
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
      Authorization: API_KEY ? `Bearer ${API_KEY}` : undefined,
    },
  };

  const res = http.post(url, payload, params);

  check(res, {
    'status is 200':         (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'body is not empty':     (r) => r.body.length > 0,
  });

  sleep(Math.random() * 0.5);
}
