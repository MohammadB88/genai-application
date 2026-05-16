#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
CP_RELEASE="${2:-kong-cp}"
DP_RELEASE="${3:-kong-dp}"

echo "##############################################################"
echo "Deploying Kong Hybrid Mode to namespace: ${NAMESPACE}"
echo "Control Plane release: ${CP_RELEASE}"
echo "Data Plane release: ${DP_RELEASE}"
echo "##############################################################"

# Create namespace if it doesn't exist
echo "Checking if namespace ${NAMESPACE} exists..."
if ! kubectl get namespace "${NAMESPACE}" >/dev/null 2>&1; then
  echo "Creating namespace ${NAMESPACE}..."
  kubectl create namespace "${NAMESPACE}"
else
  echo "Namespace ${NAMESPACE} already exists."
fi

# Generate cluster certificate for CP/DP communication
echo "Generating cluster certificate..."
openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
  -keyout /tmp/kong-cluster.key -out /tmp/kong-cluster.crt \
  -days 1095 -subj "/CN=kong_clustering"

# Create or update the TLS secret
echo "Creating cluster certificate secret..."
kubectl create secret tls kong-cluster-cert \
  --cert=/tmp/kong-cluster.crt --key=/tmp/kong-cluster.key \
  -n "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Clean up temp cert files
rm -f /tmp/kong-cluster.key /tmp/kong-cluster.crt

# Add Kong Helm repository
echo "Adding Kong Helm repository..."
helm repo add kong https://charts.konghq.com
helm repo update

# Deploy Control Plane
echo "=============================================="
echo "Deploying Kong Control Plane..."
echo "=============================================="
helm upgrade --install "${CP_RELEASE}" kong/kong \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values_cp.yaml \
  --wait --timeout 5m

# Update SCC policy for CP service account
echo "Updating SCC policy for CP service account..."
oc adm policy add-scc-to-user anyuid -z "${CP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true
oc adm policy add-scc-to-user nonroot-v2 -z "${CP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true

# Build DP cluster_control_plane value
CP_CLUSTER_SVC="${CP_RELEASE}-cluster.${NAMESPACE}.svc.cluster.local:8005"

# Deploy Data Plane
echo "=============================================="
echo "Deploying Kong Data Plane..."
echo "=============================================="
helm upgrade --install "${DP_RELEASE}" kong/kong \
  --namespace "${NAMESPACE}" \
  -f ai-gateways/kong/values_dp.yaml \
  --set env.cluster_control_plane="${CP_CLUSTER_SVC}" \
  --wait --timeout 5m

# Update SCC policy for DP service account
echo "Updating SCC policy for DP service account..."
oc adm policy add-scc-to-user anyuid -z "${DP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true
oc adm policy add-scc-to-user nonroot-v2 -z "${DP_RELEASE}-kong" -n "${NAMESPACE}" 2>/dev/null || true

# Create OpenShift routes
echo "Creating OpenShift routes..."
# Route for CP Admin API
oc create route edge kong-cp-admin --service="${CP_RELEASE}-admin" -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -
# Route for DP Proxy
oc create route edge kong-dp-proxy --service="${DP_RELEASE}-proxy" -n "${NAMESPACE}" --dry-run=client -o yaml | oc apply -f -

echo ""
echo "##############################################################"
echo "Kong Hybrid Mode deployed successfully!"
echo "Namespace: ${NAMESPACE}"
echo "Control Plane: ${CP_RELEASE}"
echo "Data Plane: ${DP_RELEASE}"
echo "##############################################################"
echo ""
echo "Control Plane Admin API:"
echo "  https://$(oc get route -n "${NAMESPACE}" kong-cp-admin -o jsonpath='{.spec.host}' 2>/dev/null)"
echo ""
echo "Data Plane Proxy:"
echo "  https://$(oc get route -n "${NAMESPACE}" kong-dp-proxy -o jsonpath='{.spec.host}' 2>/dev/null)"
echo ""
echo "To verify CP nodes:"
echo "  curl -s https://$(oc get route -n "${NAMESPACE}" kong-cp-admin -o jsonpath='{.spec.host}' 2>/dev/null)/clustering/data-planes"
echo ""
echo "To verify DP proxy:"
echo "  curl -s https://$(oc get route -n "${NAMESPACE}" kong-dp-proxy -o jsonpath='{.spec.host}' 2>/dev/null)"
