#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
RELEASE_NAME="${2:-kong}"

echo "##############################################################"
echo "Deploying Kong Gateway (Official Chart) to namespace: ${NAMESPACE}"
echo "Release name: ${RELEASE_NAME}"
echo "##############################################################"

# Ask for CLUSTER_URL
read -p "Enter the CLUSTER_URL (e.g., cluster.example.com): " CLUSTER_URL
if [ -z "${CLUSTER_URL}" ]; then
  echo "Error: CLUSTER_URL is required."
  exit 1
fi

# Replace {CLUSTER_URL}} in values.yaml with the provided value
sed -i "s/{CLUSTER_URL}}/ ${CLUSTER_URL}/g" ai-gateways/kong/values.yaml

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

# Deploy Kong using Official Helm chart with our custom values
echo "Deploying Kong Gateway (Official Chart)..."
helm upgrade --install "${RELEASE_NAME}" kong/kong \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values.yaml \
  --wait --timeout 5m

# Update SCC policy for Kong service account
echo "Updating SCC policy for Kong service account..."
oc adm policy add-scc-to-user anyuid -z kong -n "${NAMESPACE}"
oc adm policy add-scc-to-user nonroot-v2 -z kong -n "${NAMESPACE}"

# Create routes
echo "Creating routes..."
# Route for Kong Manager
oc create route edge kong-manager --service=kong-kong-manager -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
# Route for Kong Admin
oc create route edge kong-admin --service=kong-kong-admin -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo "##############################################################"
echo "Kong Gateway deployed successfully!"
echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "Chart: kong/kong (Official)"
echo "##############################################################"

echo "To access Kong Manager:"
echo "  http://\$(oc get route -n ${NAMESPACE} kong-manager -o jsonpath='{.spec.host}')"
echo ""
echo "To access Kong Admin API:"
echo "  http://\$(oc get route -n ${NAMESPACE} kong-admin -o jsonpath='{.spec.host}')"
echo ""
echo "To verify deployment:"
echo "  ./ai-gateways/kong/test-connectivity.sh"
