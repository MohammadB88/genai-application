#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
CP_RELEASE="${2:-kong-cp}"
DP_RELEASE="${3:-kong-dp}"

echo "##############################################################"
echo "Cleaning up Kong Hybrid Mode from namespace: ${NAMESPACE}"
echo "Control Plane release: ${CP_RELEASE}"
echo "Data Plane release: ${DP_RELEASE}"
echo "##############################################################"

# Uninstall Data Plane Helm release
echo "Uninstalling Data Plane ${DP_RELEASE}..."
if helm list -n "${NAMESPACE}" | grep -q "${DP_RELEASE}"; then
  helm uninstall "${DP_RELEASE}" --namespace "${NAMESPACE}"
  echo "Data Plane uninstalled."
else
  echo "Data Plane release ${DP_RELEASE} not found."
fi

# Uninstall Control Plane Helm release
echo "Uninstalling Control Plane ${CP_RELEASE}..."
if helm list -n "${NAMESPACE}" | grep -q "${CP_RELEASE}"; then
  helm uninstall "${CP_RELEASE}" --namespace "${NAMESPACE}"
  echo "Control Plane uninstalled."
else
  echo "Control Plane release ${CP_RELEASE} not found."
fi

# Delete cluster certificate secret
echo "Deleting cluster certificate secret..."
kubectl delete secret kong-cluster-cert -n "${NAMESPACE}" --ignore-not-found

# Delete Postgres PVC (created by Postgres sub-chart)
echo "Deleting Postgres PVC..."
kubectl delete pvc "data-${CP_RELEASE}-postgresql-0" -n "${NAMESPACE}" --ignore-not-found

# Clean up routes
echo "Cleaning up routes..."
oc delete route kong-cp-admin -n "${NAMESPACE}" --ignore-not-found
oc delete route kong-dp-proxy -n "${NAMESPACE}" --ignore-not-found
echo "Routes cleaned up."

echo "##############################################################"
echo "Kong Hybrid Mode cleanup completed!"
echo "Namespace: ${NAMESPACE}"
echo "Note: Namespace ${NAMESPACE} was NOT deleted to preserve other resources."
echo "To delete namespace, run: kubectl delete namespace ${NAMESPACE}"
echo "##############################################################"
