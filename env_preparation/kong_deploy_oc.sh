#!/usr/bin/env bash
# =============================================================================
# deploy-kong-openshift.sh
# Deploy Kong Gateway OSS on OpenShift
#
#   Modes:
#     dbless    — DB-less declarative config via ConfigMap (no GUI)
#     postgres  — Standalone RHEL PostgreSQL (oc manifests) + Kong Manager OSS
#
# PostgreSQL is deployed using the official Red Hat image:
#   registry.redhat.io/rhel9/postgresql-16
# It runs unprivileged and is OpenShift SCC-compatible with NO extra tuning.
# Resources are created with plain `oc apply` — no Helm, no Bitnami.
#
# Usage:
#   ./deploy-kong-openshift.sh --mode dbless    [options]
#   ./deploy-kong-openshift.sh --mode postgres  [options]
#
# Options:
#   --mode          dbless | postgres              (required)
#   --namespace     OpenShift project/namespace    (default: kong)
#   --pg-namespace  Separate namespace for PG      (default: same as --namespace)
#   --release       Helm release name for Kong     (default: kong)
#   --domain        OpenShift apps domain          (e.g. apps.cluster.example.com)
#   --pg-password   PostgreSQL password            (default: changeme)
#   --pg-version    PostgreSQL image version tag   (default: 16)
#   --kong-image    Kong image tag                 (default: 3.7)
#   --storage-class StorageClass for PG PVC        (default: cluster default)
#   --pg-size       PVC size for PostgreSQL         (default: 5Gi)
#   --dry-run       Print manifests/values only, do not apply
#   --uninstall     Remove Kong + PostgreSQL and clean up namespaces
#   -h | --help     Show this help
# =============================================================================

set -euo pipefail

# ── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}─── $* ───${RESET}"; }

# ── Defaults ─────────────────────────────────────────────────────────────────
MODE=""
NAMESPACE="kong"
PG_NAMESPACE=""
RELEASE="kong"
DOMAIN=""
PG_PASSWORD="changeme"
PG_VERSION="16"
KONG_IMAGE_TAG="3.7"
STORAGE_CLASS=""
PG_SIZE="5Gi"
DRY_RUN=false
UNINSTALL=false

# Names used in all PG manifests — kept consistent throughout
PG_NAME="kong-postgres"
PG_SECRET_NAME="kong-postgres-secret"
PG_PVC_NAME="kong-postgres-pvc"
PG_SVC_NAME="kong-postgres"

# Temp dir (cleaned up on exit)
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

KONG_VALUES="$WORK_DIR/kong-values.yaml"
PG_MANIFEST="$WORK_DIR/postgres.yaml"

# ── Argument parsing ─────────────────────────────────────────────────────────
usage() {
  grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)           MODE="$2";           shift 2 ;;
    --namespace)      NAMESPACE="$2";      shift 2 ;;
    --pg-namespace)   PG_NAMESPACE="$2";   shift 2 ;;
    --release)        RELEASE="$2";        shift 2 ;;
    --domain)         DOMAIN="$2";         shift 2 ;;
    --pg-password)    PG_PASSWORD="$2";    shift 2 ;;
    --pg-version)     PG_VERSION="$2";     shift 2 ;;
    --kong-image)     KONG_IMAGE_TAG="$2"; shift 2 ;;
    --storage-class)  STORAGE_CLASS="$2";  shift 2 ;;
    --pg-size)        PG_SIZE="$2";        shift 2 ;;
    --dry-run)        DRY_RUN=true;        shift ;;
    --uninstall)      UNINSTALL=true;      shift ;;
    -h|--help)        usage ;;
    *) error "Unknown argument: $1  — run with --help for usage" ;;
  esac
done

# Resolve PG namespace default
[[ -z "$PG_NAMESPACE" ]] && PG_NAMESPACE="$NAMESPACE"

# Kong connects to PG via short name (same ns) or FQDN (cross-ns)
if [[ "$PG_NAMESPACE" == "$NAMESPACE" ]]; then
  PG_HOST="${PG_SVC_NAME}"
else
  PG_HOST="${PG_SVC_NAME}.${PG_NAMESPACE}.svc.cluster.local"
fi

# ── Validation ────────────────────────────────────────────────────────────────
if [[ "$UNINSTALL" == "false" ]]; then
  [[ -z "$MODE" ]] && error "--mode is required (dbless | postgres)"
  [[ "$MODE" != "dbless" && "$MODE" != "postgres" ]] && \
    error "--mode must be 'dbless' or 'postgres'"
fi

# ── Prerequisites ─────────────────────────────────────────────────────────────
check_prereqs() {
  step "Checking prerequisites"
  for cmd in oc helm; do
    command -v "$cmd" &>/dev/null || error "'$cmd' not found in PATH"
  done
  oc whoami &>/dev/null || error "Not logged in to OpenShift — run: oc login ..."
  helm version --short &>/dev/null || error "Helm is not working correctly"
  success "oc and helm are present and authenticated"
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
do_uninstall() {
  step "Removing Kong release '${RELEASE}' from '${NAMESPACE}'"
  helm uninstall "${RELEASE}" -n "${NAMESPACE}" 2>/dev/null \
    && success "Kong Helm release removed" \
    || warn "Kong release not found, skipping"

  step "Removing PostgreSQL resources from '${PG_NAMESPACE}'"
  for res in \
    "deployment/${PG_NAME}" \
    "service/${PG_SVC_NAME}" \
    "pvc/${PG_PVC_NAME}" \
    "secret/${PG_SECRET_NAME}"; do
    oc delete "$res" -n "${PG_NAMESPACE}" --ignore-not-found=true \
      && success "Deleted ${res}" || true
  done

  info "Cleaning up remaining resources in '${NAMESPACE}'..."
  oc delete all,secret,cm,route,pvc --all -n "${NAMESPACE}" --ignore-not-found=true

  if [[ "$PG_NAMESPACE" != "$NAMESPACE" ]]; then
    info "Cleaning up remaining resources in '${PG_NAMESPACE}'..."
    oc delete all,secret,pvc --all -n "${PG_NAMESPACE}" --ignore-not-found=true
    oc delete namespace "${PG_NAMESPACE}" --ignore-not-found=true
  fi

  oc delete namespace "${NAMESPACE}" --ignore-not-found=true
  success "Cleanup complete"
  exit 0
}

# ── Helm repo ─────────────────────────────────────────────────────────────────
setup_helm_repo() {
  step "Setting up Kong Helm repository"
  helm repo add kong https://charts.konghq.com 2>/dev/null || true
  helm repo update kong
  success "Kong Helm repo ready"
}

# ── Namespace & SCC ──────────────────────────────────────────────────────────
setup_namespace() {
  local ns="$1"
  step "Setting up namespace '${ns}'"

  if oc get namespace "${ns}" &>/dev/null; then
    warn "Namespace '${ns}' already exists, skipping creation"
  else
    oc new-project "${ns}"
    success "Namespace '${ns}' created"
  fi

  # Kong (Bitnami-based image) needs anyuid to run as UID 1001.
  # The RHEL PostgreSQL image runs fully unprivileged — no SCC grant needed.
  if [[ "$ns" == "$NAMESPACE" ]]; then
    info "Granting 'anyuid' SCC to Kong service accounts..."
    oc adm policy add-scc-to-user anyuid -z default           -n "${ns}" 2>/dev/null || true
    oc adm policy add-scc-to-user anyuid -z "${RELEASE}-kong" -n "${ns}" 2>/dev/null || true
    success "anyuid SCC granted for Kong"
  fi
}

# ── Auto-detect apps domain ───────────────────────────────────────────────────
resolve_domain() {
  if [[ -z "$DOMAIN" ]]; then
    step "Auto-detecting OpenShift apps domain"
    DOMAIN=$(oc get ingresses.config.openshift.io cluster \
               -o jsonpath='{.spec.domain}' 2>/dev/null || true)
    [[ -z "$DOMAIN" ]] && \
      error "Could not detect apps domain — pass --domain apps.cluster.example.com"
    success "Domain: ${DOMAIN}"
  fi
}

# ── DB-less ConfigMap ─────────────────────────────────────────────────────────
create_dbless_configmap() {
  step "Creating DB-less declarative config ConfigMap"
  if oc get cm kong-dbless-config -n "${NAMESPACE}" &>/dev/null; then
    warn "ConfigMap 'kong-dbless-config' already exists, skipping"
    return
  fi
  oc create configmap kong-dbless-config -n "${NAMESPACE}" \
    --from-literal=kong.yml='_format_version: "3.0"
_transform: true

# Add your services, routes, and plugins here.
# Example:
# services:
#   - name: httpbin
#     url: https://httpbin.org
#     routes:
#       - name: httpbin-route
#         paths:
#           - /httpbin
'
  success "ConfigMap created — edit: oc edit cm kong-dbless-config -n ${NAMESPACE}"
}

# ── Generate PostgreSQL manifest ──────────────────────────────────────────────
# Uses registry.redhat.io/rhel9/postgresql-<version>
# This image is:
#   - Built on RHEL 9, fully supported by Red Hat
#   - Runs as a non-root, unprivileged user (UID 26 / postgres)
#   - Natively compatible with OpenShift's restricted SCC — no SCC grants needed
#   - Configured entirely via environment variables
#   - Data stored at /var/lib/pgsql/data (mounted from the PVC)
write_postgres_manifest() {
  step "Writing PostgreSQL manifest (registry.redhat.io/rhel9/postgresql-${PG_VERSION})"

  # Optional storageClassName line
  local sc_line=""
  [[ -n "$STORAGE_CLASS" ]] && sc_line="      storageClassName: \"${STORAGE_CLASS}\""

  cat > "$PG_MANIFEST" <<EOF
# =============================================================================
# PostgreSQL deployment for Kong — using the official RHEL image
#
# Image:   registry.redhat.io/rhel9/postgresql-${PG_VERSION}
# NOTE:    Pull access to registry.redhat.io requires a Red Hat pull secret.
#          On OCP this is usually pre-configured in the global pull secret.
#          If not, create it with:
#            oc create secret docker-registry rh-registry-secret \\
#              --docker-server=registry.redhat.io \\
#              --docker-username=<rh-login> \\
#              --docker-password=<rh-password-or-token> \\
#              -n ${PG_NAMESPACE}
#          Then link it:
#            oc secrets link default rh-registry-secret --for=pull -n ${PG_NAMESPACE}
# =============================================================================

---
# Secret — PostgreSQL credentials
# Environment variable names match what the RHEL image expects exactly.
apiVersion: v1
kind: Secret
metadata:
  name: ${PG_SECRET_NAME}
  namespace: ${PG_NAMESPACE}
  labels:
    app: kong-postgres
type: Opaque
stringData:
  POSTGRESQL_USER:     "kong"
  POSTGRESQL_PASSWORD: "${PG_PASSWORD}"
  POSTGRESQL_DATABASE: "kong"

---
# PersistentVolumeClaim — data directory for PostgreSQL
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PG_PVC_NAME}
  namespace: ${PG_NAMESPACE}
  labels:
    app: kong-postgres
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${PG_SIZE}
${sc_line}

---
# Deployment — single-replica PostgreSQL instance
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${PG_NAME}
  namespace: ${PG_NAMESPACE}
  labels:
    app: kong-postgres
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kong-postgres
  strategy:
    type: Recreate       # Recreate avoids two pods competing for the same PVC
  template:
    metadata:
      labels:
        app: kong-postgres
    spec:
      containers:
        - name: postgresql
          image: registry.redhat.io/rhel9/postgresql-${PG_VERSION}:latest
          imagePullPolicy: IfNotPresent

          # The RHEL image reads credentials from these exact env var names.
          # They are sourced from the Secret above to keep credentials out of
          # the Deployment spec.
          envFrom:
            - secretRef:
                name: ${PG_SECRET_NAME}

          ports:
            - name: postgresql
              containerPort: 5432
              protocol: TCP

          # The RHEL PostgreSQL image stores data at /var/lib/pgsql/data.
          # This path is owned by the 'postgres' user (UID 26) inside the image.
          volumeMounts:
            - name: pgdata
              mountPath: /var/lib/pgsql/data

          # Readiness: wait until PostgreSQL is actually accepting connections
          readinessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - psql -U \$POSTGRESQL_USER -d \$POSTGRESQL_DATABASE -c "SELECT 1"
            initialDelaySeconds: 15
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6

          # Liveness: restart the pod if the process hangs
          livenessProbe:
            exec:
              command:
                - /bin/sh
                - -c
                - psql -U \$POSTGRESQL_USER -d \$POSTGRESQL_DATABASE -c "SELECT 1"
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 3

          resources:
            requests:
              cpu: 250m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 512Mi

      volumes:
        - name: pgdata
          persistentVolumeClaim:
            claimName: ${PG_PVC_NAME}

---
# Service — ClusterIP, reachable inside the cluster as:
#   ${PG_HOST}:5432
apiVersion: v1
kind: Service
metadata:
  name: ${PG_SVC_NAME}
  namespace: ${PG_NAMESPACE}
  labels:
    app: kong-postgres
spec:
  type: ClusterIP
  selector:
    app: kong-postgres
  ports:
    - name: postgresql
      port: 5432
      targetPort: postgresql
      protocol: TCP
EOF

  success "PostgreSQL manifest written"
  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    echo -e "${BOLD}─── postgres.yaml ───${RESET}"
    cat "$PG_MANIFEST"
    echo ""
  fi
}

# ── Apply PostgreSQL manifest ─────────────────────────────────────────────────
deploy_postgres() {
  step "Deploying PostgreSQL to namespace '${PG_NAMESPACE}'"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN — skipping oc apply"
    return
  fi

  oc apply -f "$PG_MANIFEST"
  success "PostgreSQL resources applied"

  info "Waiting for PostgreSQL Deployment rollout..."
  oc rollout status deployment/"${PG_NAME}" \
    -n "${PG_NAMESPACE}" --timeout=5m \
    || warn "Rollout timed out — check: oc get pods -n ${PG_NAMESPACE}"
  success "PostgreSQL is ready"
}

# ── Write Kong values.yaml (DB-less) ─────────────────────────────────────────
write_kong_values_dbless() {
  step "Writing Kong DB-less values.yaml"
  cat > "$KONG_VALUES" <<EOF
# =============================================================================
# kong-values.yaml — Kong Gateway OSS, DB-less mode
# =============================================================================

image:
  repository: kong
  tag: "${KONG_IMAGE_TAG}"

# OpenShift SCC: null out hardcoded UIDs so anyuid SCC assigns its own
containerSecurityContext:
  runAsUser: null
  runAsGroup: null
  runAsNonRoot: false
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]

podSecurityContext:
  runAsUser: null
  runAsGroup: null
  fsGroup: null

env:
  database: "off"
  declarative_config: /kong_dbless/kong.yml
  admin_listen:      "0.0.0.0:8001"
  proxy_access_log:  /dev/stdout
  proxy_error_log:   /dev/stderr
  admin_access_log:  /dev/stdout
  admin_error_log:   /dev/stderr

volumes:
  - name: kong-dbless-config
    configMap:
      name: kong-dbless-config

volumeMounts:
  - name: kong-dbless-config
    mountPath: /kong_dbless

admin:
  enabled: true
  http:
    enabled: true
  type: ClusterIP

proxy:
  enabled: true
  http:
    enabled: true
  type: ClusterIP

manager:
  enabled: false     # Kong Manager requires a database

ingressController:
  enabled: true
  installCRDs: false

postgresql:
  enabled: false

enterprise:
  enabled: false

replicaCount: 1

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi
EOF

  success "Kong DB-less values written"
  [[ "$DRY_RUN" == "true" ]] && { echo ""; echo -e "${BOLD}─── kong-values.yaml ───${RESET}"; cat "$KONG_VALUES"; echo ""; }
}

# ── Write Kong values.yaml (PostgreSQL + Manager OSS) ────────────────────────
write_kong_values_postgres() {
  local admin_host="${RELEASE}-admin.${DOMAIN}"
  local manager_host="${RELEASE}-manager.${DOMAIN}"

  step "Writing Kong PostgreSQL + Manager values.yaml"
  cat > "$KONG_VALUES" <<EOF
# =============================================================================
# kong-values.yaml — Kong Gateway OSS, PostgreSQL + Kong Manager GUI
# Kong Manager OSS requires Kong Gateway >= 3.4
#
# PostgreSQL is the standalone RHEL deployment applied separately.
# The built-in postgresql sub-chart is disabled.
# =============================================================================

image:
  repository: kong
  tag: "${KONG_IMAGE_TAG}"

# OpenShift SCC: null out hardcoded UIDs so anyuid SCC assigns its own
containerSecurityContext:
  runAsUser: null
  runAsGroup: null
  runAsNonRoot: false
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]

podSecurityContext:
  runAsUser: null
  runAsGroup: null
  fsGroup: null

env:
  database:    postgres

  # Points to the standalone RHEL PostgreSQL Service:
  #   same namespace     → ${PG_HOST}
  #   cross-namespace    → ${PG_HOST}
  pg_host:     "${PG_HOST}"
  pg_port:     "5432"
  pg_database: kong
  pg_user:     kong
  pg_password: "${PG_PASSWORD}"

  # Kong Manager OSS — must match the OpenShift Routes created below
  admin_gui_url:    "https://${manager_host}"
  admin_api_uri:    "https://${admin_host}"
  admin_listen:     "0.0.0.0:8001"

  proxy_access_log: /dev/stdout
  proxy_error_log:  /dev/stderr
  admin_access_log: /dev/stdout
  admin_error_log:  /dev/stderr

manager:
  enabled: true
  http:
    enabled: true
  type: ClusterIP

admin:
  enabled: true
  http:
    enabled: true
  type: ClusterIP

proxy:
  enabled: true
  http:
    enabled: true
  type: ClusterIP

ingressController:
  enabled: true
  installCRDs: false

# Disable the built-in Bitnami PostgreSQL sub-chart entirely
postgresql:
  enabled: false

migrations:
  preUpgrade:  true
  postUpgrade: true

enterprise:
  enabled: false

replicaCount: 1

resources:
  requests:
    cpu: 250m
    memory: 256Mi
  limits:
    cpu: 1000m
    memory: 512Mi
EOF

  success "Kong PostgreSQL+Manager values written"
  [[ "$DRY_RUN" == "true" ]] && { echo ""; echo -e "${BOLD}─── kong-values.yaml ───${RESET}"; cat "$KONG_VALUES"; echo ""; }
}

# ── Deploy Kong via Helm ──────────────────────────────────────────────────────
deploy_kong() {
  step "Deploying Kong Gateway (release: ${RELEASE}, ns: ${NAMESPACE})"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "DRY RUN — helm template output:"
    helm template "${RELEASE}" kong/kong \
      -n "${NAMESPACE}" \
      -f "$KONG_VALUES" \
      --set ingressController.installCRDs=false
    return
  fi

  if helm status "${RELEASE}" -n "${NAMESPACE}" &>/dev/null; then
    warn "Kong release already exists — upgrading..."
    helm upgrade "${RELEASE}" kong/kong \
      -n "${NAMESPACE}" \
      -f "$KONG_VALUES" \
      --set ingressController.installCRDs=false \
      --wait --timeout 10m
  else
    helm install "${RELEASE}" kong/kong \
      -n "${NAMESPACE}" \
      -f "$KONG_VALUES" \
      --set ingressController.installCRDs=false \
      --wait --timeout 10m
  fi

  success "Kong deployed"
}

# ── Wait for Kong rollout ─────────────────────────────────────────────────────
wait_for_kong() {
  step "Waiting for Kong pods"
  oc rollout status deployment/"${RELEASE}-kong" \
    -n "${NAMESPACE}" --timeout=5m \
    || warn "Rollout timed out — check: oc get pods -n ${NAMESPACE}"
  success "Kong pods are running"
}

# ── OpenShift Routes (TLS edge) ───────────────────────────────────────────────
create_routes() {
  step "Creating OpenShift Routes (TLS edge termination)"

  local proxy_host="${RELEASE}-proxy.${DOMAIN}"
  local admin_host="${RELEASE}-admin.${DOMAIN}"

  _create_route() {
    local name="$1" svc="$2" port="$3" host="$4" insecure="$5"
    if oc get route "${name}" -n "${NAMESPACE}" &>/dev/null; then
      warn "Route '${name}' already exists, skipping"
      return
    fi
    oc create route edge "${name}" \
      --service="${svc}" --port="${port}" \
      --hostname="${host}" --insecure-policy="${insecure}" \
      -n "${NAMESPACE}"
    success "Route → https://${host}"
  }

  _create_route \
    "${RELEASE}-proxy"   "${RELEASE}-kong-proxy"   kong-proxy   "${proxy_host}" Redirect
  _create_route \
    "${RELEASE}-admin"   "${RELEASE}-kong-admin"   kong-admin   "${admin_host}" None

  if [[ "$MODE" == "postgres" ]]; then
    local manager_host="${RELEASE}-manager.${DOMAIN}"
    _create_route \
      "${RELEASE}-manager" "${RELEASE}-kong-manager" kong-manager "${manager_host}" Redirect
  fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
  local proxy_host="${RELEASE}-proxy.${DOMAIN}"
  local admin_host="${RELEASE}-admin.${DOMAIN}"

  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
  echo -e "${GREEN}  Kong Gateway OSS deployed successfully on OpenShift!${RESET}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════${RESET}"
  echo ""
  echo -e "  ${BOLD}Mode:${RESET}          ${MODE}"
  echo -e "  ${BOLD}Kong namespace:${RESET} ${NAMESPACE}"
  echo -e "  ${BOLD}Kong image:${RESET}    kong:${KONG_IMAGE_TAG}"
  echo ""
  echo -e "  ${BOLD}Proxy URL:${RESET}     https://${proxy_host}"
  echo -e "  ${BOLD}Admin API:${RESET}     https://${admin_host}"

  if [[ "$MODE" == "postgres" ]]; then
    local manager_host="${RELEASE}-manager.${DOMAIN}"
    echo ""
    echo -e "  ${BOLD}PostgreSQL image:${RESET}  registry.redhat.io/rhel9/postgresql-${PG_VERSION}"
    echo -e "  ${BOLD}PostgreSQL ns:${RESET}     ${PG_NAMESPACE}"
    echo -e "  ${BOLD}PostgreSQL host:${RESET}   ${PG_HOST}:5432"
    echo -e "  ${BOLD}PostgreSQL db:${RESET}     kong  (user: kong)"
    echo ""
    echo -e "  ${BOLD}Kong Manager GUI:${RESET}  https://${manager_host}"
    echo ""
    echo -e "  ${YELLOW}Security note:${RESET} Kong Manager OSS has no login by default."
    echo -e "  Restrict the admin and manager routes with a NetworkPolicy"
    echo -e "  or an OpenShift OAuth proxy before exposing externally."
  else
    echo ""
    echo -e "  ${YELLOW}DB-less note:${RESET} Edit your declarative config:"
    echo -e "  ${CYAN}oc edit cm kong-dbless-config -n ${NAMESPACE}${RESET}"
    echo -e "  Then reload Kong:"
    echo -e "  ${CYAN}oc exec -n ${NAMESPACE} deploy/${RELEASE}-kong -- kong reload${RESET}"
  fi

  echo ""
  echo -e "  ${BOLD}Useful commands:${RESET}"
  echo -e "    oc get pods   -n ${NAMESPACE}"
  echo -e "    oc get routes -n ${NAMESPACE}"
  [[ "$MODE" == "postgres" ]] && \
  echo -e "    oc get pods   -n ${PG_NAMESPACE}    # PostgreSQL pod"
  echo -e "    oc logs -f deploy/${RELEASE}-kong -n ${NAMESPACE}"
  echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
  echo ""
  echo -e "${BOLD}  Kong Gateway OSS — OpenShift Deployment Script${RESET}"
  echo -e "  Mode: ${CYAN}${MODE:-uninstall}${RESET}  |  Namespace: ${CYAN}${NAMESPACE}${RESET}"
  echo ""

  check_prereqs
  [[ "$UNINSTALL" == "true" ]] && do_uninstall

  setup_helm_repo
  setup_namespace "$NAMESPACE"
  [[ "$MODE" == "postgres" && "$PG_NAMESPACE" != "$NAMESPACE" ]] && \
    setup_namespace "$PG_NAMESPACE"

  resolve_domain

  case "$MODE" in
    dbless)
      create_dbless_configmap
      write_kong_values_dbless
      deploy_kong
      ;;
    postgres)
      write_postgres_manifest
      deploy_postgres
      write_kong_values_postgres
      deploy_kong
      ;;
  esac

  if [[ "$DRY_RUN" == "false" ]]; then
    wait_for_kong
    create_routes
    print_summary
  fi
}

main "$@"