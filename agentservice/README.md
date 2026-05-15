# System Health Agent Service

This service provides a LangChain-powered agent designed to monitor and report the health of an OpenShift cluster.

## Features
- **Cluster Health Reporting**: Analysis of CPU and Memory usage.
- **Pod Monitoring**: Status checks for specific namespaces.
- **FastAPI Interface**: Simple REST API for chatting with the agent.

## Architecture
- **Framework**: LangChain
- **LLM Interface**: Direct OpenAI-compatible endpoint (e.g., vLLM, NIM)
- **API**: FastAPI

## Deployment Instructions

### 1. Build and Push Image
The deployment manifests expect an image named `genai-agent-service:latest`.
```bash
# Build the image
docker build -t genai-agent-service:latest -f agentservice/Dockerfile .

# Push to your internal registry
docker push <your-registry>/genai-agent-service:latest
```
*(Note: Update the image name in `k8s/manifests.yaml` to match your registry path)*

### 2. Deploy to OpenShift
Apply the Kubernetes manifests to create the `agents` namespace and deploy the service:
```bash
oc apply -f agentservice/k8s/manifests.yaml
```

### 3. Configure Environment Variables
Ensure the following environment variables are set in the Deployment manifest:
- `MODEL_URL`: The URL of your LLM endpoint (e.g., `http://vllm-service.llms.svc.cluster.local/v1`).
- `MODEL_API_KEY`: API key for the model (if required).

## Usage

### API Endpoint
The agent is accessible via the `/chat` endpoint.

**Request:**
```bash
curl -X POST http://<agent-route>/chat \
-H "Content-Type: application/json" \
-d '{
  "input": "How is the cluster health overall?",
  "chat_history": []
}'
```

### Testing
To run the automated test suite, set the `AGENT_ENDPOINT` variable and run the test script:
```bash
export AGENT_ENDPOINT=http://<your-agent-route>
python agentservice/tests/test_api.py
```

## Project Structure
- `src/main.py`: FastAPI application entry point.
- `src/agents/health_agent.py`: LangChain agent definition and tool implementations.
- `k8s/manifests.yaml`: OpenShift deployment, service, and route configurations.
- `tests/test_api.py`: Integration test script.
