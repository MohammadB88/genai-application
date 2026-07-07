import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const ENDPOINT = __ENV.STRESS_ENDPOINT || '/v1/completions';
const MODEL = __ENV.STRESS_MODEL || 'meta/llama-3.2-1b-instruct';
const PROMPT = __ENV.STRESS_PROMPT || 'Hello, how are you?';
const MAX_TOKENS = __ENV.STRESS_MAX_TOKENS ? parseInt(__ENV.STRESS_MAX_TOKENS) : 50;
const MAX_VUS = __ENV.STRESS_MAX_VUS ? parseInt(__ENV.STRESS_MAX_VUS) : 1000;
const RAMP_UP = __ENV.STRESS_RAMP || '10m';
const STEADY = __ENV.STRESS_STEADY || '5m';
const API_KEY = __ENV.API_KEY || '';   // placeholder for auth

export const options = {
  scenarios: {
    stress: {
      executor: 'ramping-vus',
      startVUs: 10,
      stages: [
        { duration: RAMP_UP, target: MAX_VUS },
        { duration: STEADY, target: MAX_VUS },
      ],
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

  sleep(0.1 + Math.random() * 0.9);
}
