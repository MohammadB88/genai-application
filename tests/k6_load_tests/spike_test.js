import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const ENDPOINT = __ENV.SPIKE_ENDPOINT || '/v1/completions';
const MODEL = __ENV.SPIKE_MODEL || 'meta/llama-3.2-1b-instruct';
const PROMPT = __ENV.SPIKE_PROMPT || 'Hello, how are you?';
const MAX_TOKENS = __ENV.SPIKE_MAX_TOKENS ? parseInt(__ENV.SPIKE_MAX_TOKENS) : 50;
const NORMAL_VUS = __ENV.SPIKE_NORMAL_VUS ? parseInt(__ENV.SPIKE_NORMAL_VUS) : 10;
const SPIKE_VUS = __ENV.SPIKE_SPIKE_VUS ? parseInt(__ENV.SPIKE_SPIKE_VUS) : 500;
const BEFORE_SPIKE = __ENV.SPIKE_BEFORE || '30s';
const DURING_SPIKE = __ENV.SPIKE_DURING || '30s';
const AFTER_SPIKE = __ENV.SPIKE_AFTER || '30s';
const API_KEY = __ENV.API_KEY || '';   // placeholder for auth

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-vus',
      startVUs: NORMAL_VUS,
      stages: [
        { duration: BEFORE_SPIKE, target: NORMAL_VUS },
        { duration: DURING_SPIKE, target: SPIKE_VUS },
        { duration: AFTER_SPIKE, target: NORMAL_VUS },
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

  sleep(1);
}
