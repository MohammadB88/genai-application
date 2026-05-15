#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
RELEASE_NAME="${2:-kong}"

echo "##############################################################"
echo "Deploying Kong AI Gateway to namespace: ${NAMESPACE}"
echo "Release name: ${RELEASE_NAME}"
echo "##############################################################"

# Create namespace if it doesn't exist
echo "Checking if namespace ${NAMESPACE} exists..."
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

# Add Kong Helm repository if not present
echo "Checking for Kong Helm repository..."
if ! helm repo list | grep -q "kong"; then
  echo "Adding Kong Helm repository..."
  helm repo add kong https://charts.konghq.com
  helm repo update
else
  echo "Kong Helm repository already exists."
  helm repo update
fi

# Deploy Kong using Helm chart
echo "Deploying Kong AI Gateway..."
helm upgrade --install "${RELEASE_NAME}" ./ai-gateways/kong \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values.yaml \
  -f ai-gateways/kong/values-openshift.yaml \
  --wait --timeout 5m

echo "##############################################################"
echo "Kong AI Gateway deployed successfully!"
echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "##############################################################"

echo "To access Kong Admin API:"
echo "  http://\$(oc get route -n ${NAMESPACE} ${RELEASE_NAME}-kong-admin -o jsonpath='{.spec.host}')"
echo ""
echo "To access Kong Proxy:"
echo "  http://\$(oc get route -n ${NAMESPACE} ${RELEASE_NAME}-kong-proxy -o jsonpath='{.spec.host}')"
echo ""
echo "To verify deployment:"
echo "  ./ai-gateways/kong/test-connectivity.sh"