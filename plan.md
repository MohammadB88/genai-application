# Kong AI Gateway Implementation Plan

## Overview
This plan outlines the implementation of Kong AI Gateway (open source) alongside the existing LiteLLM deployment, using the current Ollama deployment as the backend service on OpenShift.

## Objectives
- Deploy Kong AI Gateway as a separate API gateway solution
- Integrate with existing Ollama deployment for LLM services
- Provide advanced AI capabilities (prompt engineering, semantic caching, observability)
- Ensure coexistence with existing LiteLLM deployment
- Follow OpenShift best practices for security and observability

## Prerequisites
- OpenShift 4.x+ cluster with `oc` or `kubectl` configured
- Helm 3.x installed
- Existing Ollama deployment in `llms` namespace (from models/ollama/kustomization.yaml)
- Existing LiteLLM deployment in `ai-gateways/litemaas/`
- Access to Kong Helm charts repository

## Architecture
```
Existing Components:
- Ollama Service: ollama.llms.svc.cluster.local:11434 (in llms namespace)
- LiteLLM Gateway: Deployed in ai-gateways/litemaas/

New Components:
- Kong AI Gateway: Deployed in kong-ai-gateway namespace
- Integrates with existing Ollama service
- Provides AI-specific routing and plugins
```

## Implementation Steps

### 1. Environment Preparation
```bash
# Add Kong Helm repository
helm repo add kong https://charts.konghq.com
helm repo update

# Create dedicated namespace
kubectl create namespace kong-ai-gateway
```

### 2. Deploy Kong Gateway
```bash
# Deploy using Helm with OpenShift-specific values
helm install kong-gateway ai-gateways/kong \
  --namespace kong-ai-gateway \
  -f ai-gateways/kong/values-openshift.yaml
```

### 3. Verify Deployment
```bash
# Check deployment status
kubectl get all -n kong-ai-gateway

# Verify pods are running
kubectl get pods -n kong-ai-gateway

# Check services
kubectl get svc -n kong-ai-gateway

# Check route (OpenShift)
kubectl get route -n kong-ai-gateway
```

### 4. Test Connectivity
```bash
# Use the provided test script
./ai-gateways/kong/test-connectivity.sh
```

## Key Configuration Details

### Kong Deployment Characteristics
- **Deployment Mode**: DB-less (no external database required)
- **Replica Count**: 1 (adjustable via values.yaml)
- **Security Context**: 
  - runAsNonRoot: true
  - runAsUser: 1000
  - fsGroup: 1000
  - Capabilities: drop ALL
- **Plugins Enabled**: ai-proxy, ai-proxy-advanced, prometheus

### Service Configuration
- **Proxy Service**: Port 80 (HTTP) and 443 (HTTPS)
- **Admin API**: Port 8001 (HTTP) and 8444 (HTTPS)
- **Status Endpoint**: Port 8100 (for metrics)
- **Service Type**: ClusterIP (internal) with OpenShift Route for external access

### AI Proxy Configuration for Ollama
```yaml
aiProxy:
  enabled: true
  config:
    route_type: llm/v1/chat
    model:
      provider: ollama
      name: llama3.2:3b  # Adjust based on pulled models
      options:
        upstream_url: http://ollama.llms.svc.cluster.local:11434
```

### Monitoring Setup
- Prometheus plugin enabled in Kong
- ServiceMonitor created for automatic scraping by Prometheus Operator
- Metrics available at :8100/metrics endpoint

## Coexistence with LiteLLM
- **LiteLLM Gateway**: Continues serving at its existing endpoint
- **Kong AI Gateway**: New AI-focused gateway at kong-gateway.kong-ai-gateway.svc.cluster.local:8000
- **Separate Namespaces**: Prevents resource contention and provides isolation
- **Independent Scaling**: Each gateway can be scaled independently based on demand
- **Shared Backend**: Both gateways can access the same Ollama service

## Validation Checklist
- [ ] Kong pods running in kong-ai-gateway namespace
- [ ] Services created and accessible internally
- [ ] OpenShift Route created for external access
- [ ] Admin API responding on port 8001
- [ ] Proxy AI endpoint responding on port 8000
- [ ] Metrics endpoint available at :8100/metrics
- [ ] No port conflicts with existing LiteLLM deployment
- [ ] Ollama service reachable from Kong pods
- [ ] AI Proxy plugin correctly routing to Ollama

## Maintenance and Operations

### Upgrades
```bash
# Upgrade Kong deployment
helm upgrade kong-gateway ai-gateways/kong \
  --namespace kong-ai-gateway \
  -f ai-gateways/kong/values-openshift.yaml \
  --set image.tag=<new_version>
```

### Rollbacks
```bash
# List releases
helm list -n kong-ai-gateway

# Rollback to previous revision
helm rollback kong-gateway <REVISION> -n kong-ai-gateway
```

### Configuration Changes
```bash
# Update values and upgrade
helm upgrade kong-gateway ai-gateways/kong \
  --namespace kong-ai-gateway \
  -f ai-gateways/kong/values-openshift.yaml \
  --reuse-values \
  --set <key>=<value>
```

## File Structure
All implementation files are stored under:
```
ai-gateways/kong/
├── Chart.yaml
├── values.yaml
├── values-openshift.yaml
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── route.yaml
│   └── servicemonitor.yaml
└── test-connectivity.sh
```

## Estimated Timeline
- **Day 1**: Environment preparation and basic Kong deployment
- **Day 2**: AI plugin configuration and Ollama integration testing
- **Day 3**: Monitoring setup, security validation, and route configuration
- **Day 4**: Comprehensive testing, validation, and documentation
- **Day 5**: Knowledge transfer and cleanup

## Notes
1. The implementation uses Helm for easy upgrades, rollbacks, and configuration management
2. Security context is specifically configured for OpenShift compatibility
3. Route uses edge termination for OpenShift router compatibility
4. Monitoring leverages Kong's built-in Prometheus plugin
5. No changes required to existing LiteLLM or Ollama deployments