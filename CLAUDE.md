# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GenAI Application Platform - A production-ready infrastructure for deploying Generative AI applications on OpenShift, featuring multiple LLM serving runtimes, vector databases, object storage, API gateways, web interfaces, monitoring, and comprehensive load testing.

## Architecture Components

- **Model Serving Runtimes**: Ollama (CPU), vLLM (CPU/GPU via OpenShift AI), NVIDIA NIM (GPU)
- **Vector Database**: Milvus for embeddings and similarity search
- **Object Storage**: MinIO (S3-compatible) for model storage and documents
- **API Gateway**: LiteLLM (litemaas) for unified model API access
- **Web GUIs**: AnythingLLM for document management and RAG chat interactions
- **Monitoring**: Grafana dashboards + Prometheus with ServiceMonitor-based metrics
- **Alerting**: Comprehensive Prometheus rules for GPU, NIM (vLLM/TensorRT-LLM) monitoring
- **Load Testing**: k6-operator based test suite (smoke, stress, spike, soak, breakpoint tests)
- **GitOps**: ArgoCD configurations for continuous deployment

## Directory Structure

```
genai-application/
├── env_preparation/              # Environment setup/cleanup scripts
│   ├── argocd_deploy.sh          # Deploy ArgoCD resources
│   ├── argocd_cleanup.sh         # Remove ArgoCD resources
│   ├── kong_deploy.sh            # Deploy Kong AI Gateway
│   ├── kong_cleanup.sh           # Remove Kong AI Gateway
│   ├── litemaas_deploy.sh        # Deploy LiteLLM gateway
│   ├── litemaas_cleanup.sh       # Remove LiteLLM gateway
│   ├── models_deploy.sh          # Deploy LLM models
│   ├── models_cleanup.sh         # Remove LLM models
│   ├── monitoring_deploy.sh      # Deploy monitoring/alerting
│   ├── monitoring_cleanup.sh     # Remove monitoring/alerting
│   ├── web_interfaces_deploy.sh  # Deploy web GUIs
│   ├── web_interfaces_cleanup.sh # Remove web GUIs
│   ├── remove_resources_argocd.sh
│   ├── remove_resources_ns.sh
│   ├── archived/                 # Archived scripts
│   └── README.md
├── gitops/                       # ArgoCD AppProject/Application manifests
│   ├── appproject.yaml          # ArgoCD project definition
│   ├── root-application.yaml    # Root application for gitops
│   ├── anythingllm.yaml         # AnythingLLM deployment
│   ├── llm_llama.yaml           # LLaMA model deployment
│   ├── llm_vllm_granite.yaml    # vLLM Granite model deployment
│   ├── minio.yaml               # MinIO storage deployment
│   └── archive/                 # Archived configurations
├── models/                       # LLM deployments
│   ├── ollama/                  # CPU-based Ollama runtime
│   │   ├── all_resources.yaml
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   ├── startup.sh
│   │   ├── kustomization.yaml
│   │   └── pvc.yaml
│   ├── vllm/                    # vLLM CPU/GPU deployments
│   │   ├── cpu_all_resources.yaml
│   │   ├── gpu_all_resources.yaml
│   │   └── cpu/
│   │       └── granite-318b/    # Granite 3.1 8B model
│   │           ├── deployment.yaml
│   │           ├── service.yaml
│   │           ├── servicemonitor.yaml
│   │           ├── kustomization.yaml
│   │           └── pvc.yaml
│   └── nvidia_nim/              # NVIDIA NIM GPU microservices
│       ├── README.md
│       ├── llama3-2-1b_all_resources.yaml
│       ├── llama3-8b_all_resources.yaml
│       ├── mistral-7b_all_resources.yaml
│       ├── phi-3-mini_all_resources.yaml
│       ├── qwen25-7b_all_resources.yaml
│       ├── deploy_nim_s3/       # NIM with S3 model storage
│       │   ├── curlimages.yaml
│       │   ├── deploy_init_s3_model.yaml
│       │   ├── llama3-2-1b_all_resources.yaml
│       │   └── model_repo_test.yaml
│       ├── llama321b/           # LLaMA 3.2 1B model
│       │   ├── namespace.yaml
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   ├── route.yaml
│       │   ├── secret.yaml
│       │   ├── servicemonitor.yaml
│       │   ├── kustomization.yaml
│       │   └── pvc.yaml
│       └── llama3-8b/           # LLaMA 3 8B model
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── route.yaml
│           ├── servicemonitor.yaml
│           ├── kustomization.yaml
│           └── pvc.yaml
├── vectordb/                    # Vector database deployments
│   └── milvus/                  # Milvus vector DB
│       ├── openshift-values.yaml
│       ├── milvus_manifest_standalone.yaml
│       ├── attu-deployment.yaml  # Milvus UI
│       └── model_list.txt
├── s3_storage/                  # S3-compatible storage
│   └── minio_on_openshift/      # MinIO object storage
│       ├── all_resources.yaml
│       ├── deplyoment.yaml
│       ├── service.yaml
│       ├── route.yaml
│       ├── secret.yaml
│       ├── kustomization.yaml
│       └── pvc.yaml
├── web_interfaces/              # GUI deployments
│   └── anythingllm/             # AnythingLLM GUI
│       ├── all_resources.yaml
│       ├── deplyoment.yaml
│       ├── service.yaml
│       ├── route.yaml
│       ├── kustomization.yaml
│       └── pvc.yaml
├── ai-gateways/                 # API gateway configurations
│   ├── litemaas/                # LiteLLM gateway
│   │   ├── README.md
│   │   ├── oauthclient.yaml
│   │   └── values_oc.yaml
│   └── kong/                    # Kong AI Gateway
│       ├── values.yaml
│       ├── README.md
│       └── test-connectivity.sh
├── monitoring_alerting/         # Monitoring and alerting
│   ├── grafana_openshift/       # Grafana dashboards
│   │   ├── Readme.md
│   │   ├── route.yaml
│   │   ├── gpu_dashboard.json
│   │   └── nim_dashboard_sample.json
│   └── rules_alerting/          # Prometheus rules
│       ├── rules_alers.md
│       ├── gpu_cluster_health.yaml
│       ├── gpu_cost_efficiency.yaml
│       ├── gpu_critical_rules.yaml
│       ├── gpu_warning_rules.yaml
│       ├── nim_tensorrtllm.yaml
│       └── nim_vllm.yaml
├── tests/                        # Testing suites
│   └── last_und_performance/    # k6 load/performance tests
│       ├── README.md
│       ├── smoke_test.js
│       ├── average_load_test.js
│       ├── stress_test.js
│       ├── soak_test.js
│       ├── spike_test.js
│       ├── breakpoint_test.js
│       └── specific_tests/
├── rag_usecase/                  # RAG architecture reference
│   ├── README.md
│   └── images/                  # Documentation images
├── gpu_deployment.md            # GPU deployment guide
├── infra_preparation_auto.sh    # Infrastructure automation script
├── ROADMAP.md                  # Project roadmap
├── LICENSE                     # Apache 2.0 License
└── README.md                   # Main project README
```

## Commands

### Prerequisites
- `oc` or `kubectl` configured for OpenShift 4.x+
- Helm 3.x (for Milvus, k6-operator deployments)
- NGC API key (for NVIDIA NIM deployments)
- GPU nodes (for GPU-based deployments)

### Environment Setup
```sh
# Remove ArgoCD resources (dry-run first)
./env_preparation/remove_resources_argocd.sh

# Remove namespace resources
./env_preparation/remove_resources_ns.sh

# Enable user workload monitoring (required for ServiceMonitors)
oc -n openshift-monitoring create configmap cluster-monitoring-config \
  --from-literal=config.yaml='enableUserWorkload: true'
```

### Deploy/Teardown Scripts
Each component has a dedicated deploy/cleanup pair in `env_preparation/`:
```sh
# Deploy components
./env_preparation/argocd_deploy.sh
./env_preparation/kong_deploy.sh
./env_preparation/litemaas_deploy.sh
./env_preparation/models_deploy.sh
./env_preparation/monitoring_deploy.sh
./env_preparation/web_interfaces_deploy.sh

# Remove components
./env_preparation/argocd_cleanup.sh
./env_preparation/kong_cleanup.sh
./env_preparation/litemaas_cleanup.sh
./env_preparation/models_cleanup.sh
./env_preparation/monitoring_cleanup.sh
./env_preparation/web_interfaces_cleanup.sh
```

### Deploy Components

```sh
# MinIO storage
kubectl apply -f s3_storage/minio_on_openshift/all_resources.yaml

# Milvus vector DB (standalone)
helm template -f vectordb/milvus/openshift-values.yaml vectordb -n milvus \
  --set cluster.enabled=false --set etcd.replicaCount=1 \
  --set minio.mode=standalone milvus/milvus > milvus_manifest_standalone.yaml
kubectl apply -f milvus_manifest_standalone.yaml

# Milvus UI (Attu)
kubectl apply -f vectordb/milvus/attu-deployment.yaml

# Ollama (CPU models)
kubectl apply -f models/ollama/all_resources.yaml
# Then pull models inside pod: ollama pull llama3.2:3b, all-minilm:33m

# vLLM via OpenShift AI UI (models stored in MinIO, served via KServe)
# See models/vllm/README.md for detailed instructions

# NVIDIA NIM (GPU) - LLaMA 3.2 1B
kubectl apply -f models/nvidia_nim/llama321b/

# NVIDIA NIM (GPU) - LLaMA 3 8B
kubectl apply -f models/nvidia_nim/llama3-8b/

# AnythingLLM GUI
kubectl apply -f web_interfaces/anythingllm/all_resources.yaml

# k6 Operator for load testing
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
helm install k6-operator grafana/k6-operator -n k6-operator --create-namespace
```

### Load Testing with k6

```sh
# Deploy test script ConfigMap + TestRun
kubectl apply -f tests/last_und_performance/configmap.yaml
kubectl apply -f tests/last_und_performance/testrun.yaml

# Test types: smoke, average_load, stress, soak, spike, breakpoint
# See tests/last_und_performance/README.md for detailed test strategies
```

### GitOps with ArgoCD

```sh
# Apply ArgoCD AppProject
kubectl apply -f gitops/appproject.yaml

# Apply root application (syncs all gitops resources)
kubectl apply -f gitops/root-application.yaml
```

## Key Configuration Patterns

### GitOps (ArgoCD)
- AppProject `llms` in `openshift-gitops` namespace
- Root application `genai-root` manages all gitops resources
- Source repo: GitHub (MohammadB88/genai-application)
- Deployments target `llms` namespace
- Automated sync with prune and self-heal enabled

### ServiceMonitor Setup
- Metrics endpoint: `/v1/metrics` (NIM models)
- Requires `enableUserWorkload: true` in cluster-monitoring-config
- ServiceMonitor discovers services with matching labels in user namespaces
- Example selector: `matchLabels: {app: llama3-2-1b-instruct}`

### SecurityContext (OpenShift)
- Pods must run as non-root: `runAsNonRoot: true`
- Drop capabilities: `capabilities.drop: ["ALL"]`
- Use `seccompProfile.type: RuntimeDefault` where required
- For Milvus deployments, adjust SecurityContext for:
  - StatefulSets (etcd, pulsar components): set pod securityContext to `{}`
  - MinIO deployment: set pod securityContext to `{}`
  - Container securityContext: `runAsNonRoot: true`, `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`

### Kustomization
Most components use Kustomize for configuration management:
- `models/ollama/kustomization.yaml`
- `models/nvidia_nim/llama321b/kustomization.yaml`
- `models/nvidia_nim/llama3-8b/kustomization.yaml`
- `models/vllm/cpu/granite-318b/kustomization.yaml`
- `s3_storage/minio_on_openshift/kustomization.yaml`
- `web_interfaces/anythingllm/kustomization.yaml`

### Default Credentials
- MinIO: user=`minio`, password=`minio123`
- Milvus: user=`root`, password=`Milvus`

## RAG Architecture Flow

1. User uploads documents via AnythingLLM GUI
2. Documents sent to embedding model (Ollama: `all-minilm:33m`)
3. Embeddings stored in Milvus vector DB
4. Chat queries retrieve relevant vectors + send to LLM
5. LLM generates response with source citations

### LLM Integration Options
- **Ollama**: Use "Ollama" provider in AnythingLLM settings
  - Base URL: `http://ollama.model-ollama.svc.cluster.local:11434`
  - Chat Model: `llama3.2:3b`
- **vLLM (OpenShift AI)**: Use "Generic OpenAI" provider
  - Base URL: `<INFERENCE_ENDPOINT_FROM_OPENSHIFT_AI>/v1`
  - Chat Model Name: configured in OpenShift AI model serving
- **NVIDIA NIM**: Use "Generic OpenAI" provider
  - Base URL: `http://<nim-service>.svc.cluster.local:8000/v1`
  - Chat Model Name: model-specific (e.g., `meta/llama-3.2-1b-instruct`)

## NVIDIA NIM Deployment

Requires NGC API key and GPU nodes:
```sh
# Create image pull secret
oc create secret docker-registry nim-pull-secret \
  --docker-username='$oauthtoken' --docker-server='nvcr.io' \
  --docker-password='nvapi-XXXXX'

# Create NGC API key secret
oc create secret generic ngc-api-key \
  --from-literal=NGC_API_KEY='nvapi-XXXXX'

# Deploy model (update NGC_API_KEY in deployment manifest)
kubectl apply -f models/nvidia_nim/llama321b/
```

### Available NIM Models
- LLaMA 3.2 1B Instruct: `models/nvidia_nim/llama321b/`
- LLaMA 3 8B Instruct: `models/nvidia_nim/llama3-8b/`
- LLaMA 3.2 1B (S3): `models/nvidia_nim/deploy_nim_s3/`
- Mistral 7B: `models/nvidia_nim/mistral-7b_all_resources.yaml`
- Phi-3 Mini: `models/nvidia_nim/phi-3-mini_all_resources.yaml`
- Qwen 2.5 7B: `models/nvidia_nim/qwen25-7b_all_resources.yaml`

## vLLM Deployment with OpenShift AI

vLLM models are deployed via OpenShift AI UI using the vLLM ServingRuntime for KServe:

1. **Prepare Model Storage**:
   - Download model from Huggingface to OpenShift AI workbench
   - Upload to MinIO S3 storage bucket
   - Model path: `s3://<bucket>/<model-name>`

2. **Deploy Model**:
   - Navigate to OpenShift AI → Models
   - Enable "Single-Model Serving"
   - Select "vLLM ServingRuntime for KServe"
   - Configure model server size (requires GPU)
   - Set inference endpoint (no auth for testing - secure in production)

3. **Test Endpoint**:
   ```sh
   curl ${INFERENCE_ENDPOINT_FROM_OPENSHIFT_AI}/v1/chat/completions \
   -H "Content-Type: application/json" \
   -d '{
       "model": "vllm-gpu",
       "messages": [
         {"role": "system", "content": "You are a helpful assistant."},
         {"role": "user", "content": "Hello, who are you?"}
       ]
   }'
   ```

## Monitoring and Alerting

### Grafana Dashboards
- GPU utilization: `monitoring_alerting/grafana_openshift/gpu_dashboard.json` (NVIDIA DCGM Exporter)
- NIM metrics: `monitoring_alerting/grafana_openshift/nim_dashboard_sample.json`
- Prometheus endpoint: `https://thanos-querier.openshift-monitoring.svc.cluster.local:9091`

### Prometheus Rules and Alerts

#### GPU Metrics and Alerts
- **Operator Metrics**: `gpu_operator_gpu_nodes_total`, `gpu_operator_reconciliation_status`
- **Node Status**: `gpu_operator_driver_ready`, `gpu_operator_toolkit_ready`
- **DCGM GPU**: `DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`, `DCGM_FI_DEV_GPU_TEMP`
- **DCGM Health**: `DCGM_FI_DEV_XID_ERRORS`, `DCGM_FI_DEV_ECC_ERRORS`

Key GPU Alerts:
- `DCGMExporterDown` (critical): DCGM exporter not responding
- `GPUDriverNotReady` (critical): GPU driver pod not ready
- `GPUErrorsIncreasing` (critical): XID errors increasing
- `GPUMemoryHigh` (warning): GPU memory > 85%
- `GPUTemperatureHigh` (warning): GPU temp > 80°C
- `GPUUnderutilized` (warning): GPU utilization < 30%

#### NIM vLLM Metrics and Alerts
- **Request**: `vllm:requests_per_second_total`, `vllm:request_duration_seconds`
- **Queue**: `vllm:running_requests`, `vllm:waiting_requests`, `vllm:queue_length`
- **Tokens**: `vllm:prompt_tokens_total`, `vllm:generation_tokens_total`
- **Latency**: `vllm:time_to_first_token`, `vllm:inter_token_latency`
- **GPU**: `gpu_cache_usage_perc`, `vllm:gpu_memory_used_bytes`

Key NIM vLLM Alerts:
- `High P99 latency` (warning): P99 latency > 3s
- `Queue too long` (critical): Waiting requests > 10
- `KV cache high` (critical): KV cache > 90%
- `GPU memory high` (critical): GPU memory > 95%
- `TTFT high` (warning): Time to first token > 2s

#### NIM TensorRT-LLM Metrics and Alerts
- **Inference**: `trtllm:request_count_total`, `trtllm:inference_duration_ms`
- **Throughput**: `trtllm:batch_size`, `trtllm:tokens_per_second`
- **GPU**: `gpu_utilization`, `gpu_memory_used_bytes`
- **Latency**: `trtllm:request_latency_ms`, `trtllm:time_to_first_token_ms`

Key NIM TensorRT-LLM Alerts:
- `NIMEmbeddingHighLatency` (warning): P95 latency > 500ms
- `NIMEmbeddingFailures` (critical): Failure rate > 1%
- `NIMEmbeddingGPUMemoryHigh` (warning): GPU memory > 90%

### Alert Rule Files
- `monitoring_alerting/rules_alerting/gpu_cluster_health.yaml`
- `monitoring_alerting/rules_alerting/gpu_cost_efficiency.yaml`
- `monitoring_alerting/rules_alerting/gpu_critical_rules.yaml`
- `monitoring_alerting/rules_alerting/gpu_warning_rules.yaml`
- `monitoring_alerting/rules_alerting/nim_tensorrtllm.yaml`
- `monitoring_alerting/rules_alerting/nim_vllm.yaml`

## Load Testing with k6

### k6 Executors
- `shared-iterations`: Share N iterations across VUs
- `per-vu-iterations`: Each VU runs exactly N iterations
- `constant-vus`: Fixed VUs for duration
- `ramping-vus`: VUs ramp up/down over stages
- `constant-arrival-rate`: Fixed iterations/second
- `ramping-arrival-rate`: RPS ramps over stages
- `externally-controlled`: Dynamic control via API

### Test Strategies
- **Smoke test**: Verify basic functionality under minimal load
- **Average-load test**: Simulate typical day traffic
- **Stress test**: Gradually increase load beyond normal to find limits
- **Soak test**: Sustain elevated load for long periods (hours/days)
- **Spike test**: Sudden burst of traffic (10x normal)
- **Breakpoint test**: Ramp up until system fails

### Test Scripts
- `tests/last_und_performance/smoke_test.js`
- `tests/last_und_performance/average_load_test.js`
- `tests/last_und_performance/stress_test.js`
- `tests/last_und_performance/soak_test.js`
- `tests/last_und_performance/spike_test.js`
- `tests/last_und_performance/breakpoint_test.js`

### Deploying k6 Tests
```sh
# Create ConfigMap with test script
kubectl create configmap k6-test-script --from-file=test.js

# Create TestRun CRD
kubectl apply -f testrun.yaml
```

## API Gateways

The `ai-gateways/` directory contains configurations for deploying API gateways for accessing multiple LLM providers.

### LiteLLM Gateway
The `ai-gateways/litemaas/` directory contains configurations for deploying LiteLLM as a unified API gateway for accessing multiple LLM providers.

#### Components
- `oauthclient.yaml`: OAuth client configuration
- `values_oc.yaml`: OpenShift-specific values for LiteLLM deployment

### Kong AI Gateway (Standalone)
The `ai-gateways/kong/` directory contains configurations for deploying Kong Gateway as a standalone API Gateway on OpenShift using the `kong/ingress` Helm chart (KIC disabled — OpenShift's built-in router handles ingress).

#### Components
- `values.yaml`: OpenShift-optimized values for `kong/ingress` chart
  - `controller.enabled: false` — KIC not needed, OpenShift router handles ingress
  - `gateway`: Kong Gateway (nginx) — handles proxy traffic in DB-less mode
- `README.md`: Deployment and configuration guide
- `test-connectivity.sh`: Script to verify the deployment

## Infrastructure Automation

### Automated Setup Script
`infra_preparation_auto.sh` - Automated infrastructure preparation script for setting up the GenAI platform components.

## Project Roadmap

See [ROADMAP.md](ROADMAP.md) for planned features and improvements:
- Interactive project showcase
- GUI instruction migration
- vLLM deployment instructions
- Milvus deployment instructions
- NVIDIA NIM deployment instructions
- AstraDB (Cassandra) vector database support
- Additional model provider API endpoints (watsonx.ai, etc.)

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.