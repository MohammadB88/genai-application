#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kong"
RELEASE="kong"
VALUES_FILE="kong-values.yaml"

echo "🚀 Creating / selecting namespace..."
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"

echo "🔐 Granting OpenShift SCC permissions..."
oc adm policy add-scc-to-user anyuid -z default -n "$NAMESPACE"

echo "📦 Adding Kong Helm repo..."
helm repo add kong https://charts.konghq.com
helm repo update

echo "⬇️ Installing Kong..."
helm upgrade --install "$RELEASE" kong/kong \
  -n "$NAMESPACE" \
  -f "$VALUES_FILE"

echo "⏳ Waiting for Kong rollout..."
oc rollout status deployment/"$RELEASE-kong" -n "$NAMESPACE" --timeout=300s

echo "🌐 Creating OpenShift Routes..."

# Proxy route
oc create route edge kong-proxy \
  --service="$RELEASE-kong-proxy" \
  --port=kong-proxy \
  -n "$NAMESPACE" 2>/dev/null || true

# Admin API route
oc create route edge kong-admin \
  --service="$RELEASE-kong-admin" \
  --port=kong-admin \
  -n "$NAMESPACE" 2>/dev/null || true

# Manager UI route
oc create route edge kong-manager \
  --service="$RELEASE-kong-manager" \
  --port=kong-manager \
  -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "✅ Kong installation completed!"
echo ""
echo "📍 Routes:"
oc get routes -n "$NAMESPACE"