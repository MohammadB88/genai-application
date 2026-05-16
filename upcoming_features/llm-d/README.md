# llm-d Distributed Inference Gateway (Phase 1)

This directory contains the first implementation phase of the `llm-d` framework, focusing on the **Inference Gateway (IGW)**.

## Implementation Overview
In this version, `llm-d` acts as a "Smart Proxy" that sits between the user/agent and the LLM backends (vLLM/NIM). Instead of simple load balancing, it uses **Token-Aware Routing**.

### How it Works
The gateway analyzes the length of the input prompt to decide the best backend:
- **Short Prompts (< 100 chars)** $\rightarrow$ Routed to **NVIDIA NIM** (Optimized for low-latency, quick responses).
- **Long Prompts ($\ge$ 100 chars)** $\rightarrow$ Routed to **vLLM** (Optimized for high-throughput and large context windows).

## Deployment

### 1. Build and Push Image
```bash
docker build -t llm-d-gateway:latest -f llm-d/Dockerfile .
docker push <your-registry>/llm-d-gateway:latest
```

### 2. Deploy to OpenShift
```bash
oc apply -f llm-d/k8s/all_resources.yaml
```

## Usage

### Inference Requests
The gateway provides a standard OpenAI-compatible `/v1/chat/completions` endpoint:
```bash
curl -X POST http://<llm-d-route>/v1/chat/completions \
-H "Content-Type: application/json" \
-d '{
  "messages": [{"role": "user", "content": "Hi!"}]
}'
```

### Testing Routing Logic
Use the debug endpoint to verify how a prompt would be routed without actually making an LLM call:
```bash
curl "http://<llm-d-route>/route-debug?prompt=This is a very long prompt that should definitely be routed to vLLM because it exceeds the character limit set in the gateway logic"
```

## Components
- `src/gateway/main.py`: The FastAPI proxy implementing the routing logic.
- `k8s/all_resources.yaml`: Manifests for Namespace, Deployment, Service, and Route.
- `tests/test_routing.py`: Verification script for routing decisions.
