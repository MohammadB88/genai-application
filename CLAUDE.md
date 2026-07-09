# CLAUDE.md

GenAI Application Platform - OpenShift infrastructure for LLM serving, vector DBs, object storage, API gateways, web UIs, monitoring, and load testing.

## Directory Layout

```
env_preparation/     Deploy/cleanup scripts per component
gitops/              ArgoCD AppProject + Application manifests
models/{ollama,vllm,nvidia_nim/llama321b,nvidia_nim/llama3-8b}
vectordb/milvus/     Helm values + Attu UI
s3_storage/minio_on_openshift/
databases/postgres/
web_interfaces/anythingllm/
ai-gateways/{litemaas,kong}/
monitoring_alerting/{grafana_openshift,rules_alerting}/
tests/last_und_performance/  k6 test scripts
rag_usecase/                 RAG architecture docs + images
```

## Commands

```sh
# Deploy individual components
kubectl apply -f s3_storage/minio_on_openshift/all_resources.yaml
helm template -f vectordb/milvus/openshift-values.yaml vectordb -n milvus --set cluster.enabled=false --set etcd.replicaCount=1 --set minio.mode=standalone milvus/milvus | kubectl apply -f -
kubectl apply -f vectordb/milvus/attu-deployment.yaml
kubectl apply -f models/ollama/all_resources.yaml    # then: ollama pull llama3.2:3b, all-minilm:33m
kubectl apply -f models/nvidia_nim/llama321b/
kubectl apply -f models/nvidia_nim/llama3-8b/

# Automated model deployment (interactive without args; -y for CI). Creates secrets
# in-cluster, patches storage class in a temp copy, waits on rollout status.
NGC_API_KEY=nvapi-... STORAGE_CLASS=<sc> ./env_preparation/models_deploy.sh nvidia_nim/llama321b -y
HUGGING_FACE_HUB_TOKEN=hf_... ./env_preparation/models_deploy.sh vllm/gpu/mistral-7b -y
./env_preparation/models_cleanup.sh --all -y
kubectl apply -f web_interfaces/anythingllm/all_resources.yaml
kubectl apply -f databases/postgres/
./env_preparation/postgresql_deploy.sh

# GitOps
kubectl apply -f gitops/appproject.yaml
kubectl apply -f gitops/root-application.yaml

# Monitoring (enable user workload monitoring first)
oc -n openshift-monitoring create configmap cluster-monitoring-config --from-literal=config.yaml='enableUserWorkload: true'

# k6 load testing
helm install k6-operator grafana/k6-operator -n k6-operator --create-namespace
kubectl create configmap k6-test-script --from-file=tests/last_und_performance/<test>.js
kubectl apply -f testrun.yaml
```

Use `env_preparation/*_deploy.sh` / `env_preparation/*_cleanup.sh` for full component lifecycle.

## Key Patterns

- **Namespace**: `llms` (ArgoCD), `model-ollama`, `milvus`, `k6-operator` per component
- **SecurityContext**: `runAsNonRoot: true`, `capabilities.drop: ["ALL"]`; for Milvus StatefulSets set pod securityContext to `{}`
- **ServiceMonitor**: metrics at `/v1/metrics`, labels `{app: <model-name>}`, requires `enableUserWorkload: true`
- **Default creds**: MinIO `minio/minio123`, Milvus `root/Milvus`
- **Kustomize** paths: `models/**/kustomization.yaml` (each sets its target `namespace:`; `models_deploy.sh` discovers models by these files), `s3_storage/minio_on_openshift/kustomization.yaml`, `web_interfaces/anythingllm/kustomization.yaml`

## RAG Flow

1. Upload docs via AnythingLLM → 2. Embed via Ollama (`all-minilm:33m`) → 3. Store in Milvus → 4. Query retrieves vectors + sends to LLM → 5. Response with citations

### LLM Provider Config (AnythingLLM settings)
| Provider | Base URL | Chat Model |
|---|---|---|
| Ollama | `http://ollama.model-ollama.svc.cluster.local:11434` | `llama3.2:3b` |
| vLLM (OpenShift AI) | `<INFERENCE_ENDPOINT>/v1` | configured in OS AI |
| NVIDIA NIM | `http://<nim-service>.svc.cluster.local:8000/v1` | model-specific |

## NVIDIA NIM (requires NGC API key + GPU nodes)

```sh
oc create secret docker-registry nim-pull-secret --docker-username='$oauthtoken' --docker-server='nvcr.io' --docker-password='nvapi-XXXXX'
oc create secret generic ngc-api-key --from-literal=NGC_API_KEY='nvapi-XXXXX'
kubectl apply -f models/nvidia_nim/<model-dir>/
```

Models: llama321b, llama3-8b, deploy_nim_s3, mistral-7b, phi-3-mini, qwen25-7b

## vLLM (via OpenShift AI UI)

1. Download model from HF → upload to MinIO bucket → 2. OpenShift AI → Models → "Single-Model Serving" → select vLLM ServingRuntime → 3. Test via curl `<endpoint>/v1/chat/completions`

## Alerting Rules

`monitoring_alerting/rules_alerting/` - GPU cluster health, cost efficiency, critical/warning rules, NIM vLLM, NIM TensorRT-LLM

## k6 Test Types

| Test | Strategy |
|---|---|
| smoke | Minimal load, verify basic functionality |
| average_load | Simulate typical traffic |
| stress | Ramp beyond normal to find limits |
| soak | Sustained load over hours/days |
| spike | Sudden 10x burst |
| breakpoint | Ramp until failure |

## ROADMAP

See [ROADMAP.md](ROADMAP.md) - astraDB, watsonx.ai endpoints, interactive showcase, deployment docs.

## License

Apache 2.0 - see [LICENSE](LICENSE)
