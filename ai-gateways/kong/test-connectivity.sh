#!/bin/bash

echo "Testing Kong AI Gateway connectivity..."

NAMESPACE="${1:-kong}"
RELEASE="${2:-kong}"

# Get proxy route host
PROXY_ROUTE=$(oc get route "${RELEASE}-proxy" -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$PROXY_ROUTE" ]; then
  PROXY_SVC="${RELEASE}-${RELEASE}-gateway-proxy"
  PROXY_URL="http://${PROXY_SVC}.${NAMESPACE}.svc.cluster.local:8000"
  echo "Using in-cluster proxy URL: $PROXY_URL"
else
  PROXY_URL="https://${PROXY_ROUTE}"
  echo "Using route proxy URL: $PROXY_URL"
fi

# Get admin route host
ADMIN_ROUTE=$(oc get route "${RELEASE}-admin" -n "${NAMESPACE}" -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$ADMIN_ROUTE" ]; then
  ADMIN_SVC="${RELEASE}-${RELEASE}-gateway-admin"
  ADMIN_URL="http://${ADMIN_SVC}.${NAMESPACE}.svc.cluster.local:8001"
  echo "Using in-cluster admin URL: $ADMIN_URL"
else
  ADMIN_URL="https://${ADMIN_ROUTE}"
  echo "Using route admin URL: $ADMIN_URL"
fi

# Test Kong proxy status endpoint
echo -e "\n=== Testing Kong Proxy Status ==="
curl -sk "${PROXY_URL}/status" | head -c 200
echo ""

# Test Admin API
echo -e "\n=== Testing Kong Admin API ==="
curl -sk "${ADMIN_URL}/status" | head -c 200
echo ""

# List configured services (verify Admin API is functional)
echo -e "\n=== Kong Services ==="
curl -sk "${ADMIN_URL}/services" | head -c 300
echo ""

echo "Connectivity test completed."
