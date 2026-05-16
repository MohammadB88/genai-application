#!/usr/bin/env bash
# install-kong-openshift.sh
# Installs Kong Gateway OSS on OpenShift via Helm and creates Routes for
# the Proxy, Admin API, and Manager UI.
#
# Prerequisites:
#   - oc / kubectl logged in with cluster-admin or sufficient RBAC
#   - helm 3 installed
#   - values.yaml in the same directory as this script
#
# Usage:
#   ADMIN_HOST=kong-admin.apps.mycluster.example.com \
#   MANAGER_HOST=kong-manager.apps.mycluster.example.com \
#   PROXY_HOST=kong-proxy.apps.mycluster.example.com \
#   PG_PASSWORD=your-real-password \
#   ./install-kong-openshift.sh

set -euo pipefail

# ── Input prompts (override via environment) ─────────────────────────────────
read -p "Enter Cluster Hostname (e.g., app.example.com): " CLUSTER_HOST
read -p "Enter PostgreSQL password: " PG_PASSWORD

# Construct default hostnames based on cluster hostname
export ADMIN_HOST="kong-admin.apps.${CLUSTER_HOST}"
export MANAGER_HOST="kong-manager.apps.${CLUSTER_HOST}"
export PROXY_HOST="kong-proxy.apps.${CLUSTER_HOST}"

# ── Config (override via environment) ─────────────────────────────────────────
NAMESPACE="${NAMESPACE:-kong}"
RELEASE="${RELEASE:-kong}"
CHART_VERSION="${CHART_VERSION:-2.38.0}"   # https://github.com/Kong/charts/releases
PG_PASSWORD="${PG_PASSWORD:-changeme}"     # pass a real secret in CI/CD

# Public hostnames for OpenShift Routes – MUST be set before running
ADMIN_HOST="${ADMIN_HOST:-kong-admin.apps.CHANGEME}"
MANAGER_HOST="${MANAGER_HOST:-kong-manager.apps.CHANGEME}"
PROXY_HOST="${PROXY_HOST:-kong-proxy.apps.CHANGEME}"

VALUES_FILE="$(dirname "$0")/values.yaml"

# ── 1. Namespace ───────────────────────────────────────────────────────────────
echo "==> Creating namespace: $NAMESPACE"
oc new-project "$NAMESPACE" 2>/dev/null || oc project "$NAMESPACE"

# ── 2. OpenShift SCC – let Kong pods run with the anyuid SCC ──────────────────
# Required because the Kong image may expect specific UIDs.
echo "==> Granting anyuid SCC to default service account"
oc adm policy add-scc-to-user anyuid \
  -z default \
  -n "$NAMESPACE"

# ── 3. Postgres credentials secret ────────────────────────────────────────────
echo "==> Creating Postgres secret"
oc create secret generic kong-postgres-secret \
  --from-literal=password="$PG_PASSWORD" \
  --namespace "$NAMESPACE" \
  --dry-run=client -o yaml | oc apply -f -

# ── 4. Helm repo ───────────────────────────────────────────────────────────────
echo "==> Adding Kong Helm repo"
helm repo add kong https://charts.konghq.com
helm repo update

# ── 5. Install / upgrade ───────────────────────────────────────────────────────
# Inject the public Admin API URL so Kong Manager can reach it from the browser.
echo "==> Installing Kong (release: $RELEASE, chart: $CHART_VERSION)"
helm upgrade --install "$RELEASE" kong/kong \
  --namespace "$NAMESPACE" \
  --version "$CHART_VERSION" \
  --values "$VALUES_FILE" \
  --set "env.admin_gui_api_url=http://${ADMIN_HOST}" \
  --set "env.admin_api_uri=http://${ADMIN_HOST}" \
  --timeout 10m \
  --wait

# ── 6. OpenShift Routes ────────────────────────────────────────────────────────
echo "==> Creating OpenShift Routes"

# 6a. Proxy (data-plane traffic)
oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kong-proxy
  namespace: ${NAMESPACE}
spec:
  host: ${PROXY_HOST}
  port:
    targetPort: 8000
  to:
    kind: Service
    name: ${RELEASE}-kong-proxy
  wildcardPolicy: None
EOF

# 6b. Admin API (HTTP – restrict to internal networks in production)
oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kong-admin
  namespace: ${NAMESPACE}
spec:
  host: ${ADMIN_HOST}
  port:
    targetPort: 8001
  to:
    kind: Service
    name: ${RELEASE}-kong-admin
  wildcardPolicy: None
EOF

# 6c. Kong Manager UI
oc apply -n "$NAMESPACE" -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: kong-manager
  namespace: ${NAMESPACE}
spec:
  host: ${MANAGER_HOST}
  port:
    targetPort: 8002
  to:
    kind: Service
    name: ${RELEASE}-kong-admin-gui
  wildcardPolicy: None
EOF

# ── 7. Smoke test ──────────────────────────────────────────────────────────────
echo "==> Waiting for pods to be ready"
oc rollout status deployment/"${RELEASE}-kong" -n "$NAMESPACE" --timeout=5m

echo ""
echo "✅  Kong Gateway OSS installed successfully."
echo ""
echo "   Proxy    : http://${PROXY_HOST}"
echo "   Admin API: http://${ADMIN_HOST}"
echo "   Manager  : http://${MANAGER_HOST}"
echo ""
echo "Quick health check:"
echo "   curl -s http://${ADMIN_HOST}/status | jq .server"