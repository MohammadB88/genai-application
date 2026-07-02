# GenAI Application Platform

A comprehensive platform for deploying and managing Generative AI applications on OpenShift, featuring multiple model serving runtimes, vector databases, object storage, API gateways, web interfaces, monitoring, and load testing.

## Features

- **Multiple LLM Backends**: Ollama (CPU), vLLM (CPU/GPU), NVIDIA NIM (GPU)
- **Vector Database**: Milvus for embeddings and similarity search
- **Object Storage**: MinIO S3-compatible storage
- **API Gateways**: LiteLLM and Kong for unified model access
- **Web GUIs**: AnythingLLM and Open WebUI for document management and chat
- **Monitoring**: Grafana dashboards + Prometheus metrics/alerting
- **Load Testing**: k6-based test suite (smoke, stress, spike, soak, breakpoint)
- **GitOps**: ArgoCD for continuous deployment

## Prerequisites

- OpenShift 4.x+ cluster
- `oc` or `kubectl` configured
- Sufficient storage (PVCs) and compute (CPU/GPU nodes as needed)
- NGC API key for NVIDIA NIM deployments

## Quick Start

```sh
# Enable user workload monitoring (required for ServiceMonitors)
oc -n openshift-monitoring create configmap cluster-monitoring-config \
  --from-literal=config.yaml='enableUserWorkload: true'

# Deploy individual components via scripts
./env_preparation/argocd_deploy.sh
./env_preparation/models_deploy.sh
./env_preparation/monitoring_deploy.sh
./env_preparation/web_interfaces_deploy.sh

# Or deploy via ArgoCD (GitOps)
kubectl apply -f gitops/appproject.yaml
kubectl apply -f gitops/root-application.yaml
```

See `env_preparation/` for per-component deploy/cleanup scripts.

## Project Structure

```
genai-application/
├── env_preparation/          # Setup and cleanup scripts
├── gitops/                   # ArgoCD manifests
├── models/                   # LLM deployments (ollama, vllm, nvidia_nim)
├── vectordb/milvus/          # Vector database
├── s3_storage/minio/         # S3-compatible object storage
├── databases/postgres/       # PostgreSQL database
├── ai-gateways/              # LiteLLM and Kong gateways
├── web_interfaces/           # AnythingLLM, Open WebUI
├── monitoring_alerting/      # Grafana dashboards + Prometheus rules
├── tests/last_und_performance/  # k6 load/performance tests
├── rag_usecase/              # RAG architecture docs
├── docs/                     # Documentation and diagrams
└── ROADMAP.md                # Project roadmap
```

## RAG Flow

1. Upload documents via AnythingLLM → 2. Embed via Ollama (`all-minilm:33m`) → 3. Store in Milvus → 4. Query retrieves vectors + LLM → 5. Response with citations

## LLM Provider Config (AnythingLLM)

| Provider | Base URL | Chat Model |
|---|---|---|
| Ollama | `http://ollama.model-ollama.svc:11434` | `llama3.2:3b` |
| vLLM (OpenShift AI) | `<INFERENCE_ENDPOINT>/v1` | configured in OS AI |
| NVIDIA NIM | `http://<nim-service>.svc:8000/v1` | model-specific |

## Key Patterns

- **Namespaces**: per-component (`model-ollama`, `milvus`, `k6-operator`), ArgoCD in `llms`
- **SecurityContext**: `runAsNonRoot: true`, `capabilities.drop: ["ALL"]`
- **ServiceMonitor**: metrics at `/v1/metrics`, requires `enableUserWorkload: true`
- **Default creds**: MinIO `minio/minio123`, Milvus `root/Milvus`
- **Kustomize**: most components have a `kustomization.yaml`

## License

Apache 2.0 - see [LICENSE](LICENSE)

## Acknowledgments

This project builds upon components from:
- [Milvus on OpenShift](https://github.com/rh-aiservices-bu/llm-on-openshift/tree/main/vector-databases/milvus)
- [AnythingLLM on OpenShift](https://github.com/rh-aiservices-bu/llm-on-openshift/blob/main/llm-clients/anythingllm/)
- [Ollama and Open WebUI](https://gautam75.medium.com/deploy-ollama-and-open-webui-on-openshift-c88610d3b5c7)
- [MinIO on OpenShift](https://ai-on-openshift.io/tools-and-applications/minio/minio/)
