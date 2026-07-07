import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';
const ENDPOINT = __ENV.SM_ENDPOINT || '/v1/completions';
const MODEL = __ENV.SM_MODEL || 'meta/llama-3.2-1b-instruct';
const PROMPT = __ENV.SM_PROMPT || 'Hello, how are you?';
const MAX_TOKENS = __ENV.SM_MAX_TOKENS ? parseInt(__ENV.SM_MAX_TOKENS) : 50;
const VUS = __ENV.SM_VUS ? parseInt(__ENV.SM_VUS) : 3;
const DURATION = __ENV.SM_DURATION || '30s';
const API_KEY = __ENV.API_KEY || '';   // placeholder for auth

export const options = {
  scenarios: {
    smoke: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
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
