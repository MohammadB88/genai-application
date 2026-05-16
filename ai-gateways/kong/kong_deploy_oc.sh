#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kong"
RELEASE="kong"
VALUES_FILE="values.yaml"

echo "==> Create namespace"
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"

echo "==> Grant SCC (required for some Kong init operations)"
oc adm policy add-scc-to-user anyuid -z default -n "$NAMESPACE"

echo "==> Ensure OpenShift can assign random UID (IMPORTANT FIX)"
oc adm policy add-scc-to-user restricted -z default -n "$NAMESPACE" || true

echo "==> Install Helm repo"
helm repo add kong https://charts.konghq.com
helm repo update

echo "==> Install/Upgrade Kong"
helm upgrade --install "$RELEASE" kong/kong \
  -n "$NAMESPACE" \
  -f "$VALUES_FILE" \
  --set ingressController.installCRDs=false

echo "==> Wait for rollout"
oc rollout status deployment/"$RELEASE-kong" -n "$NAMESPACE" --timeout=300s

echo "==> Create routes"

oc create route edge kong-proxy \
  --service="$RELEASE-kong-proxy" \
  --port=kong-proxy \
  -n "$NAMESPACE" 2>/dev/null || true

oc create route edge kong-admin \
  --service="$RELEASE-kong-admin" \
  --port=kong-admin \
  -n "$NAMESPACE" 2>/dev/null || true

oc create route edge kong-manager \
  --service="$RELEASE-kong-manager" \
  --port=kong-manager \
  -n "$NAMESPACE" 2>/dev/null || true

echo "==> Done"
oc get routes -n "$NAMESPACE"