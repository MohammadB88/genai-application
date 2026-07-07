import http from 'k6/http';
import { check, sleep } from 'k6';

// Environment‑overridable variables
const BASE_URL = __ENV.BASE_URL || 'http://llama3-2-1b-instruct.llms.svc.cluster.local:8000';
const ENDPOINT = __ENV.COMPLETIONS_ENDPOINT || '/v1/completions';
const MODEL = __ENV.MODEL || 'meta/llama-3.2-1b-instruct';
const PROMPT = __ENV.PROMPT || 'Say something short.';
const MAX_TOKENS = __ENV.MAX_TOKENS ? parseInt(__ENV.MAX_TOKENS) : 30;

// Stress scenario
const STRESS_START_VUS = __ENV.STRESS_START_VUS ? parseInt(__ENV.STRESS_START_VUS) : 50;
const STRESS_TARGET = __ENV.STRESS_TARGET ? parseInt(__ENV.STRESS_TARGET) : 500;
const STRESS_FIRST_DURATION = __ENV.STRESS_FIRST_DURATION || '30s';
const STRESS_STEADY_DURATION = __ENV.STRESS_STEADY_DURATION || '5m';
const STRESS_GRACEFUL_RAMP_DOWN = __ENV.STRESS_GRACEFUL_RAMP_DOWN || '30s';

// Spike scenario
const SPIKE_START_VUS = __ENV.SPIKE_START_VUS ? parseInt(__ENV.SPIKE_START_VUS) : 200;
const SPIKE_TARGET = __ENV.SPIKE_TARGET ? parseInt(__ENV.SPIKE_TARGET) : 500;
const SPIKE_RAMP_UP = __ENV.SPIKE_RAMP_UP || '10s';
const SPIKE_HOLD = __ENV.SPIKE_HOLD || '40s';
const SPIKE_RAMP_DOWN = __ENV.SPIKE_RAMP_DOWN || '10s';
const SPIKE_GRACEFUL_RAMP_DOWN = __ENV.SPIKE_GRACEFUL_RAMP_DOWN || '30s';

// Request timeout
const TIMEOUT = __ENV.REQUEST_TIMEOUT || '120s';

// Auth (if needed)
const API_KEY = __ENV.API_KEY || '';

export const options = {
  scenarios: {
    stress: {
      executor: 'ramping-vus',
      startVUs: STRESS_START_VUS,
      stages: [
        { duration: STRESS_FIRST_DURATION, target: STRESS_TARGET },
        { duration: STRESS_STEADY_DURATION, target: STRESS_TARGET },
      ],
      gracefulRampDown: STRESS_GRACEFUL_RAMP_DOWN,
    },
    spike: {
      executor: 'ramping-vus',
      startVUs: SPIKE_START_VUS,
      stages: [
        { duration: SPIKE_RAMP_UP, target: SPIKE_TARGET },
        { duration: SPIKE_HOLD, target: SPIKE_TARGET },
        { duration: SPIKE_RAMP_DOWN, target: SPIKE_START_VUS },
      ],
      gracefulRampDown: SPIKE_GRACEFUL_RAMP_DOWN,
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
    timeout: TIMEOUT,
  };

  const res = http.post(url, payload, params);

  check(res, {
    'status is 200':     (r) => r.status === 200,
    'body is not empty': (r) => typeof r.body === 'string' && r.body.length > 0,
  });

  sleep(0.5);
}


// import http from 'k6/http';
// import { check, sleep } from 'k6';

// export const options = {
//   scenarios: {
//     stress: {
//       executor: 'ramping-vus',
//       startVUs: 50,
//       stages: [
//         { duration: '30s', target: 500 },
//         { duration: '5m',  target: 500 },
//       ],
//       gracefulRampDown: '30s',
//     },
//     spike: {
//       executor: 'ramping-vus',
//       startVUs: 200,
//       stages: [
//         { duration: '10s', target: 500 },   // very fast spike up
//         { duration: '40s', target: 500 },   // hold peak
//         { duration: '10s', target: 200 },   // ramp down
//       ],
//       gracefulRampDown: '30s',
//     },
//   },
// };

// export default function () {
//   const BASE_URL = __ENV.BASE_URL || 'http://llama3-2-1b-instruct.llms.svc.cluster.local:8000';
//   const url = `${BASE_URL}/v1/completions`;

//   const payload = JSON.stringify({
//     model: 'meta/llama-3.2-1b-instruct',
//     prompt: 'Say something short.',
//     max_tokens: 30,
//   });

//   const params = {
//     headers: {
//       'Content-Type': 'application/json',
//     },
//     timeout: '120s',
//   };

//   const res = http.post(url, payload, params);

//   check(res, {
//     'status is 200':     (r) => r.status === 200,
//     'body is not empty': (r) => typeof r.body === 'string' && r.body.length > 0,
//   });

//   sleep(0.5);
// }
