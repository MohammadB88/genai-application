#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="${1:-kong}"
RELEASE="${2:-kong}"

echo "##############################################################"
echo "Cleaning up Kong AI Gateway from namespace: ${NAMESPACE}"
echo "Helm release: ${RELEASE}"
echo "##############################################################"

# Uninstall Helm release
echo "Uninstalling ${RELEASE}..."
if helm list -n "${NAMESPACE}" | grep -q "${RELEASE}"; then
  helm uninstall "${RELEASE}" --namespace "${NAMESPACE}"
  echo "Release uninstalled."
else
  echo "Release ${RELEASE} not found."
fi

# Clean up Routes
echo "Cleaning up routes..."
oc delete route "${RELEASE}-proxy" -n "${NAMESPACE}" --ignore-not-found
oc delete route "${RELEASE}-admin" -n "${NAMESPACE}" --ignore-not-found
echo "Routes cleaned up."

echo ""
echo "##############################################################"
echo "Kong AI Gateway cleanup completed!"
echo "Namespace: ${NAMESPACE}"
echo "Note: Namespace ${NAMESPACE} was NOT deleted to preserve other resources."
echo "To delete namespace, run: kubectl delete namespace ${NAMESPACE}"
echo "##############################################################"
