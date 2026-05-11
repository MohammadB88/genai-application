#!/bin/bash

echo "Testing Kong AI Gateway connectivity..."

NAMESPACE="kong-ai-gateway"

# Get Kong proxy service
PROXY_SERVICE=$(kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=kong -o jsonpath='{.items[0].metadata.name}')
if [ -z "$PROXY_SERVICE" ]; then
    echo "Error: Could not find Kong proxy service"
    exit 1
fi

# Get Kong admin service
ADMIN_SERVICE=$(kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=kong -o jsonpath='{.items[1].metadata.name}')
if [ -z "$ADMIN_SERVICE" ]; then
    echo "Error: Could not find Kong admin service"
    exit 1
fi

echo "Found Kong services:"
echo "  Proxy: $PROXY_SERVICE"
echo "  Admin: $ADMIN_SERVICE"

# Test Admin API
echo -e "\n=== Testing Kong Admin API ==="
ADMIN_URL="http://$ADMIN_SERVICE.$NAMESPACE.svc.cluster.local:8001"
curl -s "$ADMIN_URL" | head -c 200
echo ""

# Test Proxy endpoint
echo -e "\n=== Testing Kong Proxy AI Endpoint ==="
PROXY_URL="http://$PROXY_SERVICE.$NAMESPACE.svc.cluster.local:8000/ai/chat"
curl -s -X POST "$PROXY_URL" \
  -H "Content-Type: application/json" \
  -d '{"messages": [{"role": "user", "content": "Hello, how are you?"}]}' | head -c 200
echo ""

# Test Metrics endpoint (if prometheus plugin enabled)
echo -e "\n=== Testing Kong Metrics Endpoint ==="
METRICS_URL="http://$PROXY_SERVICE.$NAMESPACE.svc.cluster.local:8100/metrics"
curl -s "$METRICS_URL" | head -c 200
echo ""

echo "Connectivity test completed."