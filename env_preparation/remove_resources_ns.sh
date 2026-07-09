#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

DEFAULT_PREFIX="ic-"

usage() {
  cat <<EOF
Usage: $(basename "$0") [PREFIX] [options]

Environment cleanup: deletes all namespaces whose name starts with PREFIX
(default: '$DEFAULT_PREFIX').

Arguments:
  PREFIX                   Namespace name prefix (default: '$DEFAULT_PREFIX').

Options:
  -y, --non-interactive    Skip the confirmation prompt.
  -h, --help               Show this help.

Namespace deletion cascades to all resources inside. If a namespace gets stuck
in Terminating, the script reports what is still blocking it.
EOF
}

PREFIX=""
NON_INTERACTIVE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--non-interactive) NON_INTERACTIVE=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log_err "Error: unknown option '$1'."
      usage; exit 1 ;;
    *)
      if [[ -n "$PREFIX" ]]; then
        log_err "Error: multiple prefixes given ('$PREFIX' and '$1')."
        exit 1
      fi
      PREFIX="$1"; shift ;;
  esac
done

if [[ -z "$PREFIX" ]]; then
  PREFIX="$DEFAULT_PREFIX"
  log_info "No prefix given; using default '$PREFIX'."
fi

readarray -t NAMESPACES < <($KUBECTL_CMD get ns --no-headers -o custom-columns=":metadata.name" | grep "^${PREFIX}" || true)

if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
  log_ok "No namespaces found starting with '$PREFIX'. Nothing to do."
  exit 0
fi

log_info "=== Namespaces to delete ==="
for ns in "${NAMESPACES[@]}"; do
  echo "  $ns"
done
log_warn "Deleting a namespace removes ALL resources inside it."

if [[ "$NON_INTERACTIVE" != true ]]; then
  echo " "
  read -r -p "Type 'yes' to proceed: " CONFIRM
  if [[ "$CONFIRM" != "yes" ]]; then
    log_warn "Cancelled."
    exit 0
  fi
fi

FAILED=false
for ns in "${NAMESPACES[@]}"; do
  echo " "
  log_info "Deleting namespace: $ns"
  if $KUBECTL_CMD delete namespace "$ns" --ignore-not-found --timeout=30s; then
    log_ok "Namespace '$ns' deleted."
  else
    FAILED=true
    log_err "Namespace '$ns' did not finish deleting within 30s (likely stuck in Terminating)."
    log_warn "Resources still blocking deletion:"
    $KUBECTL_CMD api-resources --verbs=list --namespaced -o name 2>/dev/null \
      | xargs -r -n1 $KUBECTL_CMD get -n "$ns" --no-headers --ignore-not-found -o name 2>/dev/null \
      | sed 's/^/  /' || true
    log_warn "These usually hold finalizers. Inspect them with:"
    log_warn "  $KUBECTL_CMD get <resource> -n $ns -o yaml   # then clear .metadata.finalizers if safe"
  fi
done

echo " "
if [[ "$FAILED" == true ]]; then
  log_err "=== Finished with errors: some namespaces are still terminating ==="
  exit 1
fi
log_ok "=== All done. ==="
