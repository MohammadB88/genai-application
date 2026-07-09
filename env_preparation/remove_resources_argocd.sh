#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="$SCRIPT_DIR/../gitops"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [NAMESPACE] [options]

Environment cleanup: deletes ALL Argo CD Applications and AppProjects in the
namespace (default). Use --repo-only to remove only the ones defined in this
repository's gitops/ directory.

Arguments:
  NAMESPACE                Argo CD namespace (default: openshift-gitops).

Options:
  --repo-only              Delete only the Applications/AppProjects defined in
                           this repository's gitops/ manifests.
  -y, --non-interactive    Skip the confirmation prompt.
  -h, --help               Show this help.

The built-in 'default' AppProject is left alone (the GitOps operator recreates
it anyway). Deletion keeps Argo CD's resources-finalizer intact so the workloads
each Application deployed are cascade-deleted too. Finalizers are only removed
as a fallback when a deletion hangs.
EOF
}

NAMESPACE="openshift-gitops"
NAMESPACE_SET=false
DELETE_ALL=true
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-only) DELETE_ALL=false; shift ;;
    -y|--non-interactive) NON_INTERACTIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log_err "Error: unknown option '$1'."
      usage; exit 1 ;;
    *)
      if [[ "$NAMESPACE_SET" == true ]]; then
        log_err "Error: multiple namespaces given ('$NAMESPACE' and '$1')."
        exit 1
      fi
      NAMESPACE="$1"; NAMESPACE_SET=true; shift ;;
  esac
done

log_info "=== Argo CD Resource Removal ==="
echo "Namespace: $NAMESPACE"

if ! $KUBECTL_CMD get crd applications.argoproj.io >/dev/null 2>&1; then
  log_warn "Argo CD CRDs (applications.argoproj.io) not found on this cluster. Nothing to do."
  exit 0
fi

# Extract metadata.name of resources with the given kind from the gitops manifests.
gitops_names() {
  local kind="$1" f
  for f in "$GITOPS_DIR"/*.yaml; do
    [[ -f "$f" ]] || continue
    if grep -q "^kind:[[:space:]]*$kind[[:space:]]*$" "$f"; then
      sed -n '/^metadata:/,/^[^[:space:]]/{s/^  name:[[:space:]]*//p}' "$f" | head -n1
    fi
  done
}

# Keep only the names that actually exist in the cluster.
existing_only() {
  local type="$1" name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if $KUBECTL_CMD get "$type" "$name" -n "$NAMESPACE" >/dev/null 2>&1; then
      echo "$name"
    fi
  done
}

if [[ "$DELETE_ALL" == true ]]; then
  readarray -t APPS < <($KUBECTL_CMD get applications.argoproj.io -n "$NAMESPACE" -o name 2>/dev/null | sed 's|.*/||')
  readarray -t PROJECTS < <($KUBECTL_CMD get appprojects.argoproj.io -n "$NAMESPACE" -o name 2>/dev/null | sed 's|.*/||' | grep -v '^default$' || true)
else
  readarray -t APPS < <(gitops_names "Application" | existing_only "applications.argoproj.io")
  readarray -t PROJECTS < <(gitops_names "AppProject" | existing_only "appprojects.argoproj.io")
fi

if [[ ${#APPS[@]} -eq 0 && ${#PROJECTS[@]} -eq 0 ]]; then
  log_ok "No matching Applications or AppProjects found in '$NAMESPACE'. Nothing to do."
  exit 0
fi

echo " "
log_info "=== Resources to delete in namespace '$NAMESPACE' ==="
for app in "${APPS[@]:-}"; do
  [[ -n "$app" ]] && echo "  Application: $app"
done
for proj in "${PROJECTS[@]:-}"; do
  [[ -n "$proj" ]] && echo "  AppProject:  $proj"
done
log_warn "Deleting an Application also deletes the workloads it deployed (cascade)."
if [[ "$DELETE_ALL" == true ]]; then
  log_warn "Environment cleanup mode: this removes EVERY Application/AppProject in '$NAMESPACE'."
fi

if [[ "$NON_INTERACTIVE" != true ]]; then
  echo " "
  read -r -p "Confirm deletion? [y/N]: " CONFIRM
  if ! [[ "$CONFIRM" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    log_warn "Cancelled."
    exit 0
  fi
fi

# Delete with the finalizer intact so Argo CD cascades; strip finalizers only
# if the deletion hangs past the timeout.
delete_with_fallback() {
  local type="$1" name="$2"
  log_info "Deleting $type/$name ..."
  if $KUBECTL_CMD delete "$type" "$name" -n "$NAMESPACE" --ignore-not-found --timeout=30s; then
    log_ok "$type/$name deleted."
    return 0
  fi
  log_warn "$type/$name is stuck; removing finalizers as a fallback..."
  $KUBECTL_CMD patch "$type" "$name" -n "$NAMESPACE" --type=json \
    -p='[{"op": "remove", "path": "/metadata/finalizers"}]' 2>/dev/null || true
  if $KUBECTL_CMD delete "$type" "$name" -n "$NAMESPACE" --ignore-not-found --timeout=30s; then
    log_warn "$type/$name deleted after finalizer removal. Its deployed workloads may be orphaned - check their namespaces."
  else
    log_err "$type/$name could not be deleted."
    return 1
  fi
}

FAILED=false

# Applications first (they reference AppProjects), then AppProjects.
for app in "${APPS[@]:-}"; do
  [[ -n "$app" ]] || continue
  delete_with_fallback applications.argoproj.io "$app" || FAILED=true
done

for proj in "${PROJECTS[@]:-}"; do
  [[ -n "$proj" ]] || continue
  delete_with_fallback appprojects.argoproj.io "$proj" || FAILED=true
done

echo " "
if [[ "$FAILED" == true ]]; then
  log_err "=== Finished with errors: some resources could not be deleted ==="
  exit 1
fi
log_ok "=== Done. Argo CD resources deleted in namespace '$NAMESPACE'. ==="
