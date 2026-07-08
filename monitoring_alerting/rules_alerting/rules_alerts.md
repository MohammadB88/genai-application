## Metrics - GPU

GPU driver/toolkit/node readiness comes from `kube_pod_container_status_ready` /
`kube_node_status_condition` (kube-state-metrics), not the GPU Operator itself — the
GPU Operator does not expose a `gpu_operator_*`-prefixed Prometheus endpoint; its
readiness is surfaced via `ClusterPolicy` CR status and node labels
(`nvidia.com/gpu.deploy.driver`, etc.), not metrics.

| Category         | Examples                                                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------- |
| Node Status       | kube_pod_container_status_ready, kube_node_status_condition, kube_node_status_capacity{resource="nvidia_com_gpu"} |
| DCGM GPU         | DCGM_FI_DEV_GPU_UTIL, DCGM_FI_DEV_FB_USED, DCGM_FI_DEV_FB_FREE, DCGM_FI_DEV_GPU_TEMP, DCGM_FI_DEV_POWER_USAGE |
| DCGM Health      | DCGM_FI_DEV_XID_ERRORS, DCGM_FI_DEV_ECC_SBE_VOL_TOTAL, DCGM_FI_DEV_ECC_DBE_VOL_TOTAL                        |
| DCGM Power Limit | DCGM_FI_DEV_POWER_MGMT_LIMIT — **not in dcgm-exporter's default counters; requires a custom counters file** |
| DCGM PCIe/NVLink | DCGM_FI_PROF_PCIE_TX_BYTES, DCGM_FI_DEV_NVLINK_BANDWIDTH_TOTAL                                              |

### Prometheus Ruls and Alerts - GPU

| Alert                   | Expression                                                                         | For         | Severity |
| ----------------------- | ---------------------------------------------------------------------------------- | ----------- | -------- |
| DCGMExporterDown        | up{job=~".*dcgm.*\|.*gpu.*"} == 0                                                  | 5m          | critical |
| GPUDriverNotReady       | kube_pod_container_status_ready{namespace="gpu-operator", pod=~".*driver.*"} == 0  | 10m         | critical |
| GPUToolkitNotReady      | kube_pod_container_status_ready{namespace="gpu-operator", pod=~".*toolkit.*"} == 0 | 10m         | warning  |
| GPUNodeNotReady         | kube_node_status_condition{condition="Ready", status="true"} == 0 and on(node) kube_node_status_capacity{resource="nvidia_com_gpu"} > 0 | 5m          | critical |
| GPUErrorsIncreasing     | increase(DCGM_FI_DEV_XID_ERRORS[10m]) > 0                                          | 0m          | critical |
| GPUMemoryHigh           | DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.85           | 10m         | warning  |
| GPUTemperatureHigh      | DCGM_FI_DEV_GPU_TEMP > 80                                                          | 5m          | warning  |
| GPUUtilizationHigh      | DCGM_FI_DEV_GPU_UTIL > 90                                                          | 10m         | warning  |
| GPUPowerNearLimit       | DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_POWER_MGMT_LIMIT > 0.9                       | 5m          | warning  |
| GPUUnderutilized        | DCGM_FI_DEV_GPU_UTIL < 30                                                          | 15m/30m     | warning  |
| GPUMemoryHighComputeLow | (DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.80) and (DCGM_FI_DEV_GPU_UTIL < 40) | 20m | warning  |
| GPUImbalanceDetected    | max by (node) (DCGM_FI_DEV_GPU_UTIL) - min by (node) (DCGM_FI_DEV_GPU_UTIL) > 50   | 15m         | warning  |
| GPUPowerInefficient     | (DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_POWER_MGMT_LIMIT > 0.85) and (DCGM_FI_DEV_GPU_UTIL < 50) | 20m | warning  |
| IdleGPUOnExpensiveNode  | DCGM_FI_DEV_GPU_UTIL < 20                                                          | 45m         | warning  |
| GPUMemoryCritical       | DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.95           | 5m          | critical |
| GPUTemperatureCritical  | DCGM_FI_DEV_GPU_TEMP > 85                                                          | 3m          | critical |
| GPUPowerCritical        | DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_POWER_MGMT_LIMIT > 0.95                      | 3m          | critical |
| GPUXIDErrorDetected     | DCGM_FI_DEV_XID_ERRORS > 0                                                         | 1m          | critical |
| GPUUnhealthy            | absent(DCGM_FI_DEV_GPU_TEMP)                                                       | 1m          | critical |

> `GPUUnderutilized` is defined twice at different thresholds: `for: 15m` in
> `gpu_warning_rules.yaml` and `for: 30m` in `gpu_cost_efficiency.yaml` (same
> expression, two different alert names in different rule groups — not a conflict).

*****************************************
*****************************************

## Metrics - NIM Container with vLLM

| Metric Category | Examples                                                                                     |
| --------------- | -------------------------------------------------------------------------------------------- |
| Request         | vllm:request_success_total, vllm:e2e_request_latency_seconds                                 |
| Queue           | vllm:num_requests_running, vllm:num_requests_waiting, vllm:request_queue_time_seconds        |
| Tokens          | vllm:prompt_tokens_total, vllm:generation_tokens_total                                       |
| Latency         | vllm:time_to_first_token_seconds, vllm:inter_token_latency_seconds                           |
| Cache/GPU       | vllm:kv_cache_usage_perc (v0: vllm:gpu_cache_usage_perc); GPU memory via DCGM_FI_DEV_FB_USED |
| Scheduling      | vllm:num_preemptions_total                                                                   |

### Prometheus Ruls and Alerts - NIM Container with vLLM

| Alert            | Expression                                                                       | For | Severity |
| ---------------- | --------------------------------------------------------------------------------- | --- | -------- |
| High P99 latency | histogram_quantile(0.99, rate(vllm:e2e_request_latency_seconds_bucket[5m])) > 3  | 2m  | warning  |
| Queue too long   | vllm:num_requests_waiting > 10                                                   | 1m  | critical |
| KV cache high    | (vllm:kv_cache_usage_perc or vllm:gpu_cache_usage_perc) > 0.9                    | 5m  | critical |
| GPU memory high  | DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.95         | 5m  | critical |
| Preemptions high | rate(vllm:num_preemptions_total[5m]) > 0.1                                       | 2m  | warning  |
| TTFT high        | histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m])) > 2  | 2m  | warning  |
| Low throughput   | rate(vllm:generation_tokens_total[5m]) < 10                                      | 10m | warning  |
| Requests failing | rate(vllm:request_success_total{finished_reason="abort"}[5m]) > 0.01             | 1m  | critical |


*****************************************
*****************************************

## Metrics - NIM Container with TensorRT-LLM / Embedding (Triton-based)

The embedding NIM (NeMo Retriever) runs on Triton Inference Server; latency metrics are
cumulative counters in microseconds, and `nv_gpu_utilization` is a 0.0-1.0 gauge.

| Metric Category | Examples                                                                  |
| --------------- | -------------------------------------------------------------------------- |
| Inference       | nv_inference_request_success, nv_inference_count, nv_inference_exec_count |
| Latency         | nv_inference_request_duration_us, nv_inference_queue_duration_us          |
| GPU             | nv_gpu_utilization, nv_gpu_memory_used_bytes, nv_gpu_memory_total_bytes   |
| Errors          | nv_inference_request_failure                                              |

## Prometheus Ruls and Alerts - NIM Container with TensorRT-LLM
| Alert                     | Expression                                                                                   | For | Severity |
| ------------------------- | --------------------------------------------------------------------------------------------- | --- | -------- |
| NIMEmbeddingHighLatency   | rate(nv_inference_request_duration_us[5m]) / rate(nv_inference_request_success[5m]) > 500000 | 2m  | warning  |
| NIMEmbeddingFailures      | rate(nv_inference_request_failure[5m]) > 0.01                                                | 1m  | critical |
| NIMEmbeddingGPUMemoryHigh | nv_gpu_memory_used_bytes / nv_gpu_memory_total_bytes > 0.9                                   | 5m  | warning  |
| NIMEmbeddingLowThroughput | rate(nv_inference_request_success[5m]) < 50                                                  | 10m | warning  |
| NIMEmbeddingGPUUtilHigh   | nv_gpu_utilization > 0.95                                                                    | 10m | warning  |
