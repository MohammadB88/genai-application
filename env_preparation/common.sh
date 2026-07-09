#!/usr/bin/env bash
# Shared helpers for env_preparation scripts. Source this file, do not execute it:
#   source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}$*${NC}"; }
log_ok()   { echo -e "${GREEN}$*${NC}"; }
log_warn() { echo -e "${YELLOW}$*${NC}"; }
log_err()  { echo -e "${RED}$*${NC}" >&2; }

# Prefer oc on OpenShift, fall back to kubectl.
if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  log_err "Error: neither oc nor kubectl is installed or available in PATH."
  exit 1
fi

ensure_namespace() {
  local ns="$1"
  if ! $KUBECTL_CMD get namespace "$ns" >/dev/null 2>&1; then
    log_warn "Namespace '$ns' not found. Creating it..."
    $KUBECTL_CMD create namespace "$ns"
    log_ok "Namespace '$ns' created."
  fi
}

# Read the target namespace from a kustomization.yaml; $2 is the fallback.
kustomization_namespace() {
  local kustomization_file="$1" fallback="${2:-llms}"
  local ns
  ns=$(sed -n 's/^namespace:[[:space:]]*//p' "$kustomization_file" | head -n1 | tr -d '"'"'" | tr -d '[:space:]')
  echo "${ns:-$fallback}"
}
