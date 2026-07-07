# Last and Performance Tests

For load and performance testing of API endpoints (including LLMs), several established tools are commonly used, such as JMeter, k6, Locust, Gatling, Artillery, LoadRunner, Vegeta, and various SaaS-based load testing services. These tools provide capabilities to simulate concurrent users, generate traffic patterns, and measure key performance indicators like latency, throughput, and error rates.

In our context, we will use k6 because it integrates naturally into the existing Grafana observability landscape, enabling unified visualization and correlation of test metrics with system metrics and logs. Additional reasons for choosing k6 include its developer-friendly scripting model (JavaScript-based), its suitability for automation and CI/CD pipelines, and its lightweight, efficient execution engine that scales well for modern cloud-native environments.

# K6 offers different executors
k6 executors define how virtual users (VUs) and iterations are scheduled during load tests, controlling traffic shape, volume, and duration to simulate real-world scenarios like steady load, spikes, or stress tests for your LLM endpoints. They enable complex multi-stage profiles (e.g., ramping to 256 VU for gpt-oss-120b benchmarking) within the `scenarios` configuration.

# Installation options for k6 on container platforms
There are some options to run tests using k6 on Kubernetes, from which we focus on these two:

**Option 1: Single k6 Image Deployment**

Deploy the official grafana/k6 Docker image as a simple Kubernetes Deployment or Job with your test script mounted via ConfigMap or PersistentVolume. This lightweight approach runs tests directly without additional overhead, suitable for quick, one-off tests.

**Option 2: k6 Operator Deployment**

*Bundle Manifest*

The bundle manifest method provides the quickest way to deploy the official k6 Operator release using a single command-line operation.
```sh
curl -O https://raw.githubusercontent.com/grafana/k6-operator/main/bundle.yaml 
kubectl apply -f - bundle.yaml --namespace k6-operator
```

This deploys the latest official release into the k6-operator namespace with default manifests.

*Helm Chart*

The Helm chart approach offers declarative management, easy upgrades, and customization through values.yaml files for tailored deployments. This fits very well in out gitops setup and simplifies installation.

```sh
helm repo add grafana https://grafana.github.io/helm-charts

helm repo update

helm show values grafana/k6-operator --version <chart-version> > k6-operator-values.yaml
```

For our environment, we set these values:

```yaml
global:
  image:
    registry: "REPO"

metrics:
  serviceMonitor:
    enabled: true

manager:
  containerSecurityContext:
    runAsUser: 1000
    runAsGroup: 1000
```

Finally, we deploy the tool with helm and test that the pods are running:

```sh
helm install k6-operator grafana/k6-operator --version <chart-version> --namespace k6-operator --create-namespace

kubectl get pods -n k6-operator
```

## Executor Types

### By number of iterations.

* `shared-iterations`

**Description**: Shares N total iterations across VUs; ends after all complete. Efficient for completing N requests quickly; VU iteration count varies.  

**Example**:
```js
scenarios: { test: { executor: 'shared-iterations', vus: 10, iterations: 100 } }
```

* `per-vu-iterations`

**Description**: Each VU runs exactly N iterations. Predictable per-user behavior; total iterations = VUs × N.

**Example**:
```js
scenarios: { test: { executor: 'per-vu-iterations', vus: 10, iterations: 5 } }
```

### By number of VUs

* `constant-vus`

**Description**: Fixed VUs run indefinitely for duration (e.g., 50 VUs × 5m). Simulates steady user load.

**Example**:
```js
scenarios: { test: { executor: 'constant-vus', vus: 50, duration: '2m' } }
```

* `ramping-vus`

**Description**: VUs ramp up/down over stages (e.g., 10→50→10 VUs). Tests system under growing/shrinking load.

**Example**:
```js
scenarios: { test: { executor: 'ramping-vus', startVUs: 10, stages: [{ duration: '1m', target: 50 }] } }
```

### By iteration rate 

* `constant-arrival-rate`

**Description**: Fixed iterations/second (RPS), auto-adjusting VUs. RPS unaffected by system slowdowns.

**Example**:
```js
scenarios: { test: { executor: 'constant-arrival-rate', rate: 100, duration: '2m' } }
```

* `ramping-arrival-rate`

**Description**: RPS ramps over stages (e.g., 10→100 RPS). Realistic traffic spikes for your LLM endpoints.

**Example**:
```js
scenarios: { test: { executor: 'ramping-arrival-rate', startRate: 50, stages: [{ duration: '1m', target: 200 }] } }
```

* `externally-controlled`

**Description**: Dynamic control via API/CLI (pause, scale VUs). For interactive or orchestrated production tests.

**Example**:
```js
scenarios: { test: { executor: 'externally-controlled', duration: '10m', preAllocatedVUs: 20 } }
```

# API Load STesting Strategies
[API Load Testing - k6 Blog](https://grafana.com/blog/api-load-testing/)

API load testing strategies are a set of planned, targeted scenarios that expose your API to different kinds of traffic patterns (light, normal, peak, or extreme) to understand how it behaves under real‑world conditions. By combining strategies like smoke, average‑load, stress, soak, spike, and breakpoint tests, teams systematically build confidence that their API will stay responsive, stable, and consistent across typical usage and unexpected traffic spikes.

### Smoke test

A smoke test verifies that your API is basically functional under a very light, minimal load (often just a few concurrent users or a small number of requests). The goal is to check that endpoints respond correctly after a deployment or config change, not to measure performance under real traffic.

[smoke_test.js](./smoke_test.js)

### Average‑load test

An average‑load test runs your API under a load that reflects typical‑day traffic, based on your real‑world usage or SLA expectations. You validate that response times, error rates, and throughput stay within acceptable limits under “normal” conditions.

[average_load_test.js](./average_load_test.js)

### Stress test

A stress test gradually increases the load beyond normal or peak expectations to see how the system behaves under heavy strain. You look for performance degradation, error spikes, or loss of functionality to identify the system’s upper limits and weak points.

[stress_test.js](./stress_test.js)

### Soak test

A soak test sustains an elevated load (often slightly above average) for a long period, such as hours or days, to detect issues that only appear over time, like memory leaks, resource exhaustion, or gradual performance degradation.

[soak_test.js](./soak_test.js)

### Spike test

A spike test suddenly injects a massive burst of traffic (for example, ten‑fold your normal load) to see how the API recovers from a short‑lived surge. The focus is on resilience, auto‑scaling behavior, and how quickly performance stabilizes once the spike passes.

[spike_test.js](./spike_test.js)

### Breakpoint test

A breakpoint test progressively ramps up traffic until the system starts to fail or its performance drops below acceptable thresholds; this “breaking point” helps you define realistic capacity limits and safety buffers. It is often used to tune autoscaling and capacity planning.

[breakpoint_test.js](./breakpoint_test.js)

# Last and Performance Test with k6-Operator

Load and Performance Tests with k6 Operator involves preparing test artifacts like a 'test.js' script and 'testrun.yaml' CRD, then deploying them to execute distributed load tests across Kubernetes pods for scalable API endpoint validation.

**Simple test script:**

```js
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8000';

export const options = {
  vus: 10,
  duration: '30s',
};

export default function () {
  const res = http.get(`${BASE_URL}/v1/models`);

  check(res, {
    'status is 200':         (r) => r.status === 200,
    'response time < 500ms': (r) => r.timings.duration < 500,
    'body is not empty':     (r) => r.body.length > 0,
  });

  sleep(1);
}
```

**ConfigMap for the test script:**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: k6-test-script
data:
  test.js: |-
    [paste the test.js content above]

```

Simple testrun manifest:

```yaml
apiVersion: k6.io/v1alpha1
kind: TestRun
metadata:
  name: simple-load-test
spec:
  parallelism: 2
  script:
    configMap:
      name: k6-test-script
      file: test.js
  runner:
    image: REPO/grafana/k6:latest
```

First configmap and then the test should be deployed.

```sh
kubectl apply -f configmap.yaml

kubectl apply -f testrun.yaml
```
