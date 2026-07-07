import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://llama3-2-1b-instruct.llms.svc.cluster.local:8000';
const ENDPOINT = __ENV.HEALTH_ENDPOINT || '/v1/models';
const VUS = __ENV.HEALTH_VUS ? parseInt(__ENV.HEALTH_VUS) : 10;
const DURATION = __ENV.HEALTH_DURATION || '30s';

export const options = {
  scenarios: {
    health: {
      executor: 'constant-vus',
      vus: VUS,
      duration: DURATION,
    },
  },
};

export default function () {
  const res = http.get(`${BASE_URL}${ENDPOINT}`);

  check(res, {
    'status is 200':         (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'body is not empty':     (r) => r.body.length > 0,
  });

  sleep(1);
}


// import http from 'k6/http';
// import { check, sleep } from 'k6';

// const BASE_URL = __ENV.BASE_URL || 'http://llama3-2-1b-instruct.llms.svc.cluster.local:8000';

// export const options = {
//   vus: 10,
//   duration: '30s',
// };

// export default function () {
//   const res = http.get(`${BASE_URL}/v1/models`);

//   check(res, {
//     'status is 200':         (r) => r.status === 200,
//     'response time < 500ms': (r) => r.timings.duration < 500,
//     'body is not empty':     (r) => r.body.length > 0,
//   });

//   sleep(1);
// }
