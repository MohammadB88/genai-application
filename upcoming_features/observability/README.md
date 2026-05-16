# LLM Observability Enhancements

This module leverages the built-in metrics exposed by vLLM and NVIDIA NIM servers to provide enterprise-grade monitoring and alerting.

## Components

### 1. Metric Collection (`k8s/servicemonitors.yaml`)
We use `ServiceMonitor` resources to instruct Prometheus to scrape the `/metrics` endpoint of the LLM servers.
- **vLLM**: Scrapes metrics based on `app: vllm` labels.
- **NIM**: Scrapes metrics based on `app: nim` labels.

### 2. Visualization (`grafana/llm_metrics.json`)
A specialized Grafana dashboard has been designed to track:
- **P99 Latency**: Monitoring a standard SLO of < 3s.
- **Throughput**: Tracking generation tokens per second.
- **KV Cache Usage**: Monitoring GPU memory saturation.

### 3. Alerting (`rules/llm_alerts.yaml`)
Critical alerts are defined to proactively notify operators:
- **HighP99Latency**: Triggered when P99 latency > 3s for 5 mins.
- **KVCacheCritical**: Triggered when KV cache usage exceeds 90%.
- **LLMErrorRateHigh**: Triggered when the error rate exceeds 5%.

## Deployment Instructions

### 1. Apply Namespace and Config
```bash
oc apply -f observability/k8s/namespace.yaml
```

### 2. Enable Metric Scraping
Apply the ServiceMonitors to the cluster:
```bash
oc apply -f observability/k8s/servicemonitors.yaml
```

### 3. Import Dashboard
Import the `observability/grafana/llm_metrics.json` file into your Grafana instance.

### 4. Apply Alerting Rules
Configure Prometheus to load the rules from `observability/rules/llm_alerts.yaml` via your Prometheus operator configuration.
