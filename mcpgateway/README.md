# MCP Gateway Service

This service implements a simplified version of the Model Context Protocol (MCP) to standardize how LLMs interact with internal platform resources.

## Overview
The MCP Gateway acts as a translation layer. Instead of LLMs needing specific drivers for every service, they can request resources using a standardized URI format.

### Supported Protocols
- `milvus://`: Interface for vector database searches and metadata.
- `minio://`: Interface for object storage retrieval.

## Deployment

### 1. Build and Push Image
```bash
docker build -t mcp-gateway:latest -f mcpgateway/Dockerfile .
docker push <your-registry>/mcp-gateway:latest
```

### 2. Deploy to OpenShift
```bash
oc apply -f mcpgateway/k8s/manifests.yaml
```

## Usage

### Resource Retrieval
Use the `/resource` endpoint to fetch data from a platform service.

**Example Request:**
```bash
curl -X POST http://<mcp-route>/resource \
-H "Content-Type: application/json" \
-d '{
  "uri": "milvus://search?query=genai-platform"
}'
```

### Testing
Run the provided demo script to verify the integration:
```bash
export MCP_ENDPOINT=http://<your-mcp-route>
python mcpgateway/tests/mcp_demo.py
```

## Implementation Details
- `src/main.py`: The FastAPI entry point handling the HTTP request/response loop.
- `src/handlers/resource_manager.py`: Logic for resolving URIs to specific service handlers.
