#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG (edit if needed)
# =========================
NAMESPACE="${NAMESPACE:-postgres}"
APP_NAME="postgres"

SECRET_FILE="../databases/postgres/secret.yaml"
PVC_FILE="../databases/postgres/pvc.yaml"
DEPLOYMENT_FILE="../databases/postgres/deployment.yaml"
SERVICE_FILE="../databases/postgres/service.yaml"

# =========================
# HELPERS
# =========================
info() { echo -e "[INFO] $*"; }
ok()   { echo -e "[OK]   $*"; }
err()  { echo -e "[ERROR] $*" >&2; exit 1; }

# =========================
# CHECK PREREQS
# =========================
command -v oc >/dev/null 2>&1 || err "oc CLI not installed"

oc whoami >/dev/null 2>&1 || err "Not logged into OpenShift (run: oc login)"

# =========================
# CREATE NAMESPACE
# =========================
info "Creating / selecting namespace: $NAMESPACE"

if oc get ns "$NAMESPACE" >/dev/null 2>&1; then
  ok "Namespace exists"
else
  oc new-project "$NAMESPACE"
  ok "Namespace created"
fi

oc project "$NAMESPACE" >/dev/null

# =========================
# APPLY RESOURCES
# =========================
apply_file () {
  local file="$1"
  [[ -f "$file" ]] || err "Missing file: $file"

  info "Applying $file"
  oc apply -f "$file"
  ok "$file applied"
}

apply_file "$SECRET_FILE"
apply_file "$PVC_FILE"

# Wait for PVC
info "Waiting for PVC to bind..."
oc wait --for=condition=Bound pvc --all --timeout=120s || true

apply_file "$DEPLOYMENT_FILE"

info "Waiting for PostgreSQL rollout..."
oc rollout status deployment/"$APP_NAME" --timeout=300s

apply_file "$SERVICE_FILE"

# =========================
# VERIFY
# =========================
info "Checking pods..."
oc get pods -o wide

info "Checking service..."
oc get svc

ok "PostgreSQL installation complete"

echo ""
echo "Connect inside cluster using:"
echo "  psql -h postgres -U <user> -d <db>"
echo ""