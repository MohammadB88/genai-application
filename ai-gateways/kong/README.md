# Kong AI Gateway — OpenShift Deployment

This directory contains configuration for deploying Kong Gateway as a
standalone API Gateway on OpenShift using the `kong/ingress` Helm chart
(with the Kong Ingress Controller disabled — OpenShift's built-in router
handles ingress).

## Architecture

Only the **gateway** pod runs — Kong Gateway (nginx) in DB-less mode,
configured via its Admin API or declarative config.

OpenShift Routes expose the proxy and admin services externally.

```
                    Kong Gateway (nginx)
                    ┌────────────────────┐
                    │  Proxy :8000/8443  │  ─── OpenShift Route
                    │  Admin :8001/8444  │  ─── OpenShift Route
                    │  Status:8100       │
                    └────────────────────┘
```

## Deployment

### Quick Deploy

```bash
./env_preparation/kong_deploy.sh [namespace] [release-name]
```

Defaults: `namespace=kong`, `release-name=kong`

### Manual Deployment

```bash
# 1. Add Kong Helm repository
helm repo add kong https://charts.konghq.com
helm repo update

# 2. Install Kong Gateway (KIC disabled)
helm install kong kong/ingress \
  --namespace kong --create-namespace \
  -f ai-gateways/kong/values.yaml \
  --wait --timeout 5m

# 3. OpenShift SCC — allow the gateway to run with assigned UID
oc adm policy add-scc-to-user nonroot-v2 -z kong-gateway-kong -n kong

# 4. Create OpenShift Routes (the chart creates ClusterIP services only)
oc create route edge kong-proxy --service=kong-kong-gateway-proxy --port=443 -n kong
oc create route edge kong-admin --service=kong-kong-gateway-admin --port=8001 -n kong
```

## Usage — Configuring Routes via Admin API

Once deployed, configure AI service routes via the Admin API:

```bash
ADMIN_URL="https://$(oc get route kong-admin -n kong -o jsonpath='{.spec.host}')"

# Add an upstream service (e.g. Ollama)
curl -sk -X POST "${ADMIN_URL}/upstreams" \
  -H "Content-Type: application/json" \
  -d '{"name": "ollama-upstream"}'

# Add a target
curl -sk -X POST "${ADMIN_URL}/upstreams/ollama-upstream/targets" \
  -H "Content-Type: application/json" \
  -d '{"target": "ollama.model-ollama.svc.cluster.local:11434", "weight": 100}'

# Add a service
curl -sk -X POST "${ADMIN_URL}/services" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ollama-service",
    "host": "ollama-upstream",
    "port": 11434,
    "protocol": "http"
  }'

# Add a route
curl -sk -X POST "${ADMIN_URL}/services/ollama-service/routes" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ollama-route",
    "paths": ["/ollama"]
  }'
```

## Verification

```bash
# Check pods
oc get pods -n kong

# Test proxy health
curl -sk https://$(oc get route kong-proxy -n kong -o jsonpath='{.spec.host}')/status

# Test Admin API
curl -sk https://$(oc get route kong-admin -n kong -o jsonpath='{.spec.host}')/status

# List configured services
curl -sk https://$(oc get route kong-admin -n kong -o jsonpath='{.spec.host}')/services
```

## Uninstalling

```bash
# Quick cleanup
./env_preparation/kong_cleanup.sh [namespace] [release-name]

# Manual
helm uninstall kong -n kong
oc delete route kong-proxy kong-admin -n kong --ignore-not-found
```

## References

- [Kong Gateway on OpenShift](https://docs.konghq.com/gateway/latest/install/openshift/)
- [kong/ingress chart](https://github.com/Kong/charts/tree/main/charts/ingress)
- [Kong Admin API](https://docs.konghq.com/gateway/latest/admin-api/)
