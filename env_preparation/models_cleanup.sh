#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/../models"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [MODEL_PATH...] [options]

Remove deployed models and their resources.

Arguments:
  MODEL_PATH               Model(s) to delete, relative to models/ (e.g. nvidia_nim/llama321b).
                           Omit to pick interactively.

Options:
  --all                    Delete all models found under models/.
  -y, --non-interactive    Never prompt; requires MODEL_PATH or --all. Also removes the
                           model credential secrets (ngc-api-key, nim-pull-secret,
                           huggingface-secret) when used with --all.
  -h, --help               Show this help.
EOF
}

# --- Argument parsing --------------------------------------------------------
MODEL_ARGS=()
NON_INTERACTIVE=false
DELETE_ALL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--non-interactive) NON_INTERACTIVE=true; shift ;;
    --all) DELETE_ALL=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log_err "Error: unknown option '$1'."
      usage; exit 1 ;;
    *)
      MODEL_ARGS+=("$1"); shift ;;
  esac
done

log_info "=== Model Cleanup Helper ==="
echo "Removes deployed models and their resources."
echo " "

# --- Model discovery ---------------------------------------------------------
readarray -t AVAILABLE_MODELS < <(find "$MODELS_DIR" -name "kustomization.yaml" -type f -exec dirname {} \; | sed "s|$MODELS_DIR/||" | sort)

if [[ ${#AVAILABLE_MODELS[@]} -eq 0 ]]; then
  log_warn "No models found with kustomization.yaml."
  exit 0
fi

MODELS_TO_DELETE=()
if [[ "$DELETE_ALL" == true ]]; then
  MODELS_TO_DELETE=("${AVAILABLE_MODELS[@]}")
elif [[ ${#MODEL_ARGS[@]} -gt 0 ]]; then
  for model in "${MODEL_ARGS[@]}"; do
    if [[ ! -f "$MODELS_DIR/$model/kustomization.yaml" ]]; then
      log_err "Error: no kustomization.yaml found for model '$model'."
      exit 1
    fi
    MODELS_TO_DELETE+=("$model")
  done
elif [[ "$NON_INTERACTIVE" == true ]]; then
  log_err "Error: MODEL_PATH or --all is required in non-interactive mode."
  exit 1
else
  echo " "
  read -r -p "Delete all models? [y/N]: " DELETE_ALL_ANSWER
  if [[ "$DELETE_ALL_ANSWER" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    DELETE_ALL=true
    MODELS_TO_DELETE=("${AVAILABLE_MODELS[@]}")
  else
    echo " "
    log_info "=== Select Models to Delete ==="
    for i in "${!AVAILABLE_MODELS[@]}"; do
      echo "  $((i+1)). ${AVAILABLE_MODELS[$i]}"
    done
    echo "  0. Cancel cleanup"

    echo " "
    read -r -p "Select model(s) by number (comma-separated for multiple, e.g., '1,3'): " MODEL_CHOICE

    if [[ "$MODEL_CHOICE" == "0" ]]; then
      log_warn "Cleanup cancelled."
      exit 0
    fi

    IFS=',' read -ra CHOICES <<< "$MODEL_CHOICE"
    for choice in "${CHOICES[@]}"; do
      choice=$(echo "$choice" | xargs) # trim whitespace
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#AVAILABLE_MODELS[@]} ]]; then
        log_err "Error: Invalid selection '$choice'."
        exit 1
      fi
      MODELS_TO_DELETE+=("${AVAILABLE_MODELS[$((choice-1))]}")
    done
  fi
fi

echo " "
log_info "=== Models to delete ==="
for i in "${!MODELS_TO_DELETE[@]}"; do
  echo "  $((i+1)). ${MODELS_TO_DELETE[$i]}"
done

if [[ "$NON_INTERACTIVE" != true ]]; then
  read -r -p "Confirm deletion? [y/N]: " CONFIRM_DELETE
  if ! [[ "$CONFIRM_DELETE" =~ ^([yY]|[yY][eE][sS])$ ]]; then
    log_warn "Cleanup cancelled."
    exit 0
  fi
fi

# --- Delete ------------------------------------------------------------------
echo " "
log_info "=== Deleting models ==="

NAMESPACES=()
for model in "${MODELS_TO_DELETE[@]}"; do
  MODEL_DIR="$MODELS_DIR/$model"
  NAMESPACE=$(kustomization_namespace "$MODEL_DIR/kustomization.yaml" "llms")

  # Collect distinct namespaces for the summary / secret cleanup.
  found=false
  for ns in "${NAMESPACES[@]:-}"; do
    [[ "$ns" == "$NAMESPACE" ]] && found=true && break
  done
  [[ "$found" == false ]] && NAMESPACES+=("$NAMESPACE")

  echo " "
  log_info "Deleting model: $model (namespace: $NAMESPACE)"
  if $KUBECTL_CMD delete -k "$MODEL_DIR" --ignore-not-found --wait --timeout=120s; then
    log_ok "Model '$model' deleted."
  else
    log_warn "Deletion of '$model' did not complete cleanly (see output above)."
  fi
done

# --- Credential secret cleanup (only when removing everything) ---------------
if [[ "$DELETE_ALL" == true ]]; then
  DELETE_SECRETS=false
  if [[ "$NON_INTERACTIVE" == true ]]; then
    DELETE_SECRETS=true
  else
    echo " "
    read -r -p "Also delete model credential secrets (ngc-api-key, nim-pull-secret, huggingface-secret)? [y/N]: " SECRETS_ANSWER
    [[ "$SECRETS_ANSWER" =~ ^([yY]|[yY][eE][sS])$ ]] && DELETE_SECRETS=true
  fi

  if [[ "$DELETE_SECRETS" == true ]]; then
    for ns in "${NAMESPACES[@]}"; do
      $KUBECTL_CMD delete secret ngc-api-key nim-pull-secret huggingface-secret \
        -n "$ns" --ignore-not-found || true
    done
    log_ok "Credential secrets removed."
  fi
fi

# --- Summary -----------------------------------------------------------------
echo " "
log_info "=== Cleanup Summary ==="
echo -e "Models deleted: ${BLUE}${#MODELS_TO_DELETE[@]}${NC}"

for ns in "${NAMESPACES[@]}"; do
  echo " "
  log_info "=== Remaining resources in namespace '$ns' ==="
  $KUBECTL_CMD get all -n "$ns" 2>/dev/null || log_ok "No resources found."
done

echo " "
log_ok "=== Cleanup finished ==="
