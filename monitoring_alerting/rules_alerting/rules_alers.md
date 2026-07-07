## Metrics - GPU
| Category         | Examples                                                                                                   |
| ---------------- | ---------------------------------------------------------------------------------------------------------- |
| Operator         | gpu_operator_gpu_nodes_total, gpu_operator_reconciliation_status, gpu_operator_reconciliation_failed_total |
| Node Status      | gpu_operator_driver_ready, gpu_operator_toolkit_ready, gpu_operator_cuda_ready                             |
| DCGM GPU         | DCGM_FI_DEV_GPU_UTIL, DCGM_FI_DEV_FB_USED, DCGM_FI_DEV_GPU_TEMP, DCGM_FI_DEV_POWER_USAGE                   |
| DCGM Health      | DCGM_FI_DEV_XID_ERRORS, DCGM_FI_DEV_ECC_ERRORS, DCGM_FI_DEV_FB_FREE                                        |
| DCGM PCIe/NVLink | DCGM_FI_DEV_PCIE_TX_THROUGHPUT, DCGM_FI_DEV_NVLink_THROUGHPUT                                              |

### Prometheus Ruls and Alerts - GPU

| Alert                   | Expression                                                                         | For         | Severity |
| ----------------------- | ---------------------------------------------------------------------------------- | ----------- | -------- |
| DCGMExporterDown        | up{job=~".*dcgm.*\|.*gpu.*"} == 0                                                  | 5m          | critical |
| GPUDriverNotReady       | kube_pod_container_status_ready{namespace="gpu-operator", pod=~".*driver.*"} == 0  | 10m         | critical |
| GPUToolkitNotReady      | kube_pod_container_status_ready{namespace="gpu-operator", pod=~".*toolkit.*"} == 0 | 10m         | warning  |
| GPUNodeNotReady         | kube_node_status_condition{condition="Ready", status="true"} == 0                  | 5m          | critical |
| GPUErrorsIncreasing     | increase(DCGM_FI_DEV_XID_ERRORS[10m]) > 0                                          | 0m          | critical |
| GPUMemoryHigh           | DCGM_FI_DEV_FB_USED / (DCGM_FI_DEV_FB_USED + DCGM_FI_DEV_FB_FREE) > 0.85           | 10m         | warning  |
| GPUTemperatureHigh      | DCGM_FI_DEV_GPU_TEMP > 80                                                          | 5m          | warning  |
| GPUUtilizationHigh      | DCGM_FI_DEV_GPU_UTIL > 90                                                          | 10m         | warning  |
| GPUPowerNearLimit       | DCGM_FI_DEV_POWER_USAGE / DCGM_FI_DEV_POWER_LIMIT > 0.9                            | 5m          | warning  |
| GPUUnderutilized        | DCGM_FI_DEV_GPU_UTIL < 30                                                          | 15m/30m/45m | warning  |
| GPUMemoryHighComputeLow | (DCGM_FI_DEV_FB_USED / total > 0.80) and (DCGM_FI_DEV_GPU_UTIL < 40)               | 20m         | warning  |
| GPUImbalanceDetected    | max(DCGM_FI_DEV_GPU_UTIL) - min(DCGM_FI_DEV_GPU_UTIL) > 50                         | 15m         | warning  |
| GPUPowerInefficient     | (power_usage > 0.85) and (DCGM_FI_DEV_GPU_UTIL < 50)                               | 20m         | warning  |

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

## Metrics - NIM Container with TensorRT-LLM
| Metric Category | Examples                                                               |
| --------------- | ---------------------------------------------------------------------- |
| Inference       | trtllm:request_count_total, trtllm:inference_duration_ms               |
| Throughput      | trtllm:batch_size, trtllm:tokens_per_second                            |
| GPU             | gpu_utilization, gpu_memory_used_bytes, gpu_cache_usage_perc           |
| Latency         | trtllm:request_latency_ms, trtllm:time_to_first_token_ms               |
| Embedding       | embedding_requests_total, embedding_tokens_total, embedding_latency_ms |
| Errors          | trtllm:request_failures_total                                          |

## Prometheus Ruls and Alerts - NIM Container with TensorRT-LLM
| Alert                     | Expression                                                                 | For | Severity |
| ------------------------- | -------------------------------------------------------------------------- | --- | -------- |
| NIMEmbeddingHighLatency   | histogram_quantile(0.95, rate(trtllm_request_latency_ms_bucket[5m])) > 500 | 2m  | warning  |
| NIMEmbeddingFailures      | rate(trtllm_request_failures_total[5m]) > 0.01                             | 1m  | critical |
| NIMEmbeddingGPUMemoryHigh | gpu_memory_used_bytes / gpu_memory_total_bytes > 0.9                       | 5m  | warning  |
| NIMEmbeddingLowThroughput | rate(embedding_requests_total[5m]) < 50                                    | 10m | warning  |
| NIMEmbeddingGPUUtilHigh   | gpu_utilization > 95                                                       | 10m | warning  |
