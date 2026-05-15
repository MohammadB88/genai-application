#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
RELEASE_NAME="${2:-kong}"

echo "##############################################################"
echo "Cleaning up Kong AI Gateway from namespace: ${NAMESPACE}"
echo "Release name: ${RELEASE_NAME}"
echo "##############################################################"

# Uninstall Helm release
echo "Uninstalling Helm release ${RELEASE_NAME}..."
if helm list -n "${NAMESPACE}" | grep -q "${RELEASE_NAME}"; then
  helm uninstall "${RELEASE_NAME}" --namespace "${NAMESPACE}"
  echo "Helm release ${RELEASE_NAME} uninstalled."
else
  echo "Helm release ${RELEASE_NAME} not found in namespace ${NAMESPACE}."
fi

# Clean up manually created routes
echo "Cleaning up routes..."
oc delete route kong-manager -n "${NAMESPACE}" --ignore-not-found
oc delete route kong-admin -n "${NAMESPACE}" --ignore-not-found
echo "Routes cleaned up."

# Optionally delete the namespace (uncomment if you want to delete the entire namespace)
# echo "Deleting namespace ${NAMESPACE}..."
# kubectl delete namespace "${NAMESPACE}"

echo "##############################################################"
echo "Kong AI Gateway cleanup completed!"
echo "Namespace: ${NAMESPACE}"
echo "Release: ${RELEASE_NAME}"
echo "Note: Namespace ${NAMESPACE} was NOT deleted to preserve other resources."
echo "To delete namespace, run: kubectl delete namespace ${NAMESPACE}"
echo "##############################################################"
