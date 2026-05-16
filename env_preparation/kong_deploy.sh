#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
RELEASE="${2:-kong}"

echo "##############################################################"
echo "Deploying Kong AI Gateway to namespace: ${NAMESPACE}"
echo "Helm release: ${RELEASE}"
echo "##############################################################"

# Create namespace if it doesn't exist
echo "Checking if namespace ${NAMESPACE} exists..."
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

# Add Kong Helm repository
echo "Adding Kong Helm repository..."
helm repo add kong https://charts.konghq.com
helm repo update

# Deploy Kong Gateway (KIC disabled — OpenShift router handles ingress)
echo "=============================================="
echo "Deploying Kong Gateway..."
echo "=============================================="
helm upgrade --install "${RELEASE}" kong/ingress \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values.yaml \
  --wait --timeout 5m

# Update SCC — allow the gateway service account to run with assigned UID
echo "Updating SCC policy..."
SA_NAME="${RELEASE}-gateway-kong"
oc adm policy add-scc-to-user nonroot-v2 -z "${SA_NAME}" -n "${NAMESPACE}" 2>/dev/null || true

# Create OpenShift Routes (the chart creates ClusterIP services only)
echo "Creating OpenShift Routes..."
oc create route edge "${RELEASE}-proxy" \
  --service="${RELEASE}-${RELEASE}-gateway-proxy" --port=443 \
  -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

oc create route edge "${RELEASE}-admin" \
  --service="${RELEASE}-${RELEASE}-gateway-admin" --port=8001 \
  -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo ""
echo "##############################################################"
echo "Kong AI Gateway deployed successfully!"
echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE}"
echo "##############################################################"
echo ""
echo "Proxy URL:"
echo "  https://$(oc get route -n "${NAMESPACE}" "${RELEASE}-proxy" -o jsonpath='{.spec.host}' 2>/dev/null)"
echo ""
echo "Admin API URL:"
echo "  https://$(oc get route -n "${NAMESPACE}" "${RELEASE}-admin" -o jsonpath='{.spec.host}' 2>/dev/null)"
echo ""
echo "To verify:"
echo "  curl -sk https://$(oc get route -n "${NAMESPACE}" "${RELEASE}-proxy" -o jsonpath='{.spec.host}' 2>/dev/null)/status"
