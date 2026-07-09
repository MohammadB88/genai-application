#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/../models"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [MODEL_PATH] [options]

Deploy a model from the models/ directory using kustomize.

Arguments:
  MODEL_PATH               Model to deploy, relative to models/ (e.g. nvidia_nim/llama321b).
                           Omit to pick interactively from the discovered models.

Options:
  -y, --non-interactive    Never prompt; fail if required input is missing.
  --timeout <seconds>      Readiness wait per deployment (default: 1800).
  -h, --help               Show this help.

Environment variables:
  NGC_API_KEY              NVIDIA NGC key (required for nvidia_nim/* models unless the
                           'ngc-api-key' secret already exists in the target namespace).
  HUGGING_FACE_HUB_TOKEN   HF token (required for vllm/gpu/* models unless the
                           'huggingface-secret' secret already exists).
  STORAGE_CLASS            Storage class for model PVCs. Use "default" for the cluster
                           default storage class.

Non-interactive example (CI):
  NGC_API_KEY=nvapi-... STORAGE_CLASS=ocs-external-storagecluster-ceph-rbd \\
    $(basename "$0") nvidia_nim/llama321b -y
EOF
}

# --- Argument parsing --------------------------------------------------------
MODEL_PATH=""
NON_INTERACTIVE=false
TIMEOUT=1800

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--non-interactive) NON_INTERACTIVE=true; shift ;;
    --timeout)
      if [[ $# -lt 2 || ! "$2" =~ ^[0-9]+$ ]]; then
        log_err "Error: --timeout requires a number of seconds."
        exit 1
      fi
      TIMEOUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*)
      log_err "Error: unknown option '$1'."
      usage; exit 1 ;;
    *)
      if [[ -n "$MODEL_PATH" ]]; then
        log_err "Error: multiple model paths given ('$MODEL_PATH' and '$1')."
        exit 1
      fi
      MODEL_PATH="$1"; shift ;;
  esac
done

log_info "=== Model Deployment Helper ==="
echo "Deploys a model from the models directory using kustomize."
echo " "

# --- Model selection ---------------------------------------------------------
if [[ -z "$MODEL_PATH" ]]; then
  if [[ "$NON_INTERACTIVE" == true ]]; then
    log_err "Error: MODEL_PATH argument is required in non-interactive mode."
    exit 1
  fi
  log_info "=== Available Models ==="
  readarray -t MODELS < <(find "$MODELS_DIR" -name "kustomization.yaml" -type f -exec dirname {} \; | sed "s|$MODELS_DIR/||" | sort)

  if [[ ${#MODELS[@]} -eq 0 ]]; then
    log_err "Error: No models with kustomization.yaml found in $MODELS_DIR"
    exit 1
  fi

  for i in "${!MODELS[@]}"; do
    echo "  $((i+1)). ${MODELS[$i]}"
  done

  echo " "
  read -r -p "Select model by number: " MODEL_CHOICE

  if ! [[ "$MODEL_CHOICE" =~ ^[0-9]+$ ]] || [[ $MODEL_CHOICE -lt 1 ]] || [[ $MODEL_CHOICE -gt ${#MODELS[@]} ]]; then
    log_err "Error: Invalid selection."
    exit 1
  fi

  MODEL_PATH="${MODELS[$((MODEL_CHOICE-1))]}"
fi

MODEL_DIR="$MODELS_DIR/$MODEL_PATH"

if [[ ! -d "$MODEL_DIR" ]]; then
  log_err "Error: Model directory not found: $MODEL_DIR"
  exit 1
fi

if [[ ! -f "$MODEL_DIR/kustomization.yaml" ]]; then
  log_err "Error: kustomization.yaml not found in $MODEL_DIR"
  exit 1
fi

NAMESPACE=$(kustomization_namespace "$MODEL_DIR/kustomization.yaml" "llms")

log_ok "Selected model: $MODEL_PATH"
echo "Model directory: $MODEL_DIR"
echo "Target namespace: $NAMESPACE"

ensure_namespace "$NAMESPACE"

# --- GPU preflight -----------------------------------------------------------
if grep -rq "nvidia.com/gpu" "$MODEL_DIR"/*.yaml; then
  echo " "
  log_info "=== GPU preflight check ==="
  GPU_COUNT=0
  while IFS= read -r n; do
    [[ "$n" =~ ^[0-9]+$ ]] && GPU_COUNT=$((GPU_COUNT + n))
  done < <($KUBECTL_CMD get nodes -o jsonpath='{range .items[*]}{.status.allocatable.nvidia\.com/gpu}{"\n"}{end}' 2>/dev/null || true)

  if [[ $GPU_COUNT -eq 0 ]]; then
    log_warn "This model requests nvidia.com/gpu, but no node reports allocatable GPUs."
    log_warn "Check that GPU nodes exist and the NVIDIA GPU operator / device plugin is installed."
    if [[ "$NON_INTERACTIVE" == true ]]; then
      log_err "Aborting (non-interactive mode)."
      exit 1
    fi
    read -r -p "Continue anyway? [y/N]: " GPU_CONTINUE
    if ! [[ "$GPU_CONTINUE" =~ ^([yY]|[yY][eE][sS])$ ]]; then
      log_warn "Deployment cancelled."
      exit 0
    fi
  else
    log_ok "Cluster reports $GPU_COUNT allocatable GPU(s)."
  fi
fi

# --- Model credentials -------------------------------------------------------
# Secrets are created directly in the cluster (never written into the git-tracked
# manifests). The secret.yaml files in the model directories are templates only.

# NVIDIA NIM models need the NGC API key and a docker-registry pull secret for nvcr.io.
if [[ "$MODEL_PATH" == nvidia_nim/* ]]; then
  echo " "
  log_info "=== NVIDIA NIM Model Configuration ==="
  if $KUBECTL_CMD get secret ngc-api-key -n "$NAMESPACE" >/dev/null 2>&1 \
     && $KUBECTL_CMD get secret nim-pull-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    log_ok "Secrets 'ngc-api-key' and 'nim-pull-secret' already exist in '$NAMESPACE'. Skipping."
  else
    if [[ -z "${NGC_API_KEY:-}" ]]; then
      if [[ "$NON_INTERACTIVE" == true ]]; then
        log_err "Error: NGC_API_KEY env var is required in non-interactive mode."
        exit 1
      fi
      read -r -s -p "Enter your NVIDIA API KEY (NGC): " NGC_API_KEY
      echo
    fi
    if [[ -z "${NGC_API_KEY:-}" ]]; then
      log_err "Error: NGC API key must not be empty."
      exit 1
    fi

    $KUBECTL_CMD create secret generic ngc-api-key \
      --from-literal=NGC_API_KEY="$NGC_API_KEY" \
      -n "$NAMESPACE" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
    log_ok "Secret 'ngc-api-key' created/updated."

    $KUBECTL_CMD create secret docker-registry nim-pull-secret \
      --docker-server=nvcr.io \
      --docker-username='$oauthtoken' \
      --docker-password="$NGC_API_KEY" \
      -n "$NAMESPACE" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
    log_ok "Docker-registry secret 'nim-pull-secret' created/updated."
  fi
fi

# vLLM GPU models download weights from Hugging Face and need a token.
if [[ "$MODEL_PATH" == vllm/gpu/* ]]; then
  echo " "
  log_info "=== vLLM GPU Model Configuration ==="
  if $KUBECTL_CMD get secret huggingface-secret -n "$NAMESPACE" >/dev/null 2>&1; then
    log_ok "Secret 'huggingface-secret' already exists in '$NAMESPACE'. Skipping."
  else
    if [[ -z "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
      if [[ "$NON_INTERACTIVE" == true ]]; then
        log_err "Error: HUGGING_FACE_HUB_TOKEN env var is required in non-interactive mode."
        exit 1
      fi
      read -r -s -p "Enter your Hugging Face token: " HUGGING_FACE_HUB_TOKEN
      echo
    fi
    if [[ -z "${HUGGING_FACE_HUB_TOKEN:-}" ]]; then
      log_err "Error: Hugging Face token must not be empty."
      exit 1
    fi

    $KUBECTL_CMD create secret generic huggingface-secret \
      --from-literal=HUGGING_FACE_HUB_TOKEN="$HUGGING_FACE_HUB_TOKEN" \
      -n "$NAMESPACE" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
    log_ok "Secret 'huggingface-secret' created/updated."
  fi
fi

# --- Storage class selection -------------------------------------------------
PVC_FILES=()
while IFS= read -r f; do
  PVC_FILES+=("$f")
done < <(find "$MODEL_DIR" -name "pvc.yaml" -type f)

STORAGE_CLASS_NAME="${STORAGE_CLASS:-}"

if [[ ${#PVC_FILES[@]} -gt 0 && -z "$STORAGE_CLASS_NAME" ]]; then
  if [[ "$NON_INTERACTIVE" == true ]]; then
    STORAGE_CLASS_NAME="default"
    log_warn "STORAGE_CLASS not set; using cluster default storage class."
  else
    echo " "
    log_info "=== Available Storage Classes ==="
    SC_NAMES=()
    while IFS= read -r line; do
      SC_NAMES+=("$line")
    done < <($KUBECTL_CMD get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

    if [[ ${#SC_NAMES[@]} -eq 0 ]]; then
      log_warn "No storage classes found. Using cluster default."
      STORAGE_CLASS_NAME="default"
    else
      for i in "${!SC_NAMES[@]}"; do
        echo "  $((i+1)). ${SC_NAMES[$i]}"
      done
      echo "  $((${#SC_NAMES[@]}+1)). Use cluster default (no storageClassName)"
      echo " "
      read -r -p "Select storage class by number: " SC_CHOICE
      if [[ "$SC_CHOICE" =~ ^[0-9]+$ ]] && [[ "$SC_CHOICE" -ge 1 ]] && [[ "$SC_CHOICE" -le ${#SC_NAMES[@]} ]]; then
        STORAGE_CLASS_NAME="${SC_NAMES[$((SC_CHOICE-1))]}"
        log_ok "Selected storage class: $STORAGE_CLASS_NAME"
      else
        STORAGE_CLASS_NAME="default"
        log_warn "Using cluster default storage class."
      fi
    fi
  fi
fi

# --- Render to a temp copy (never mutate the git-tracked manifests) ----------
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
cp -r "$MODEL_DIR/." "$TMP_DIR/"

if [[ ${#PVC_FILES[@]} -gt 0 ]]; then
  for pvc_file in "${PVC_FILES[@]}"; do
    tmp_pvc="$TMP_DIR/${pvc_file#"$MODEL_DIR"/}"
    if [[ "$STORAGE_CLASS_NAME" == "default" ]]; then
      # Drop the storageClassName line so the cluster default provisioner is used.
      sed -i '/^  storageClassName:/d' "$tmp_pvc"
      log_ok "PVC ${pvc_file#"$MODELS_DIR"/}: using cluster default storage class"
    elif grep -q '^  storageClassName:' "$tmp_pvc"; then
      sed -i "s|^  storageClassName:.*|  storageClassName: $STORAGE_CLASS_NAME|" "$tmp_pvc"
      log_ok "PVC ${pvc_file#"$MODELS_DIR"/}: storageClassName set to '$STORAGE_CLASS_NAME'"
    else
      printf '  storageClassName: %s\n' "$STORAGE_CLASS_NAME" >> "$tmp_pvc"
      log_ok "PVC ${pvc_file#"$MODELS_DIR"/}: storageClassName added as '$STORAGE_CLASS_NAME'"
    fi
  done
fi

# --- Deploy ------------------------------------------------------------------
echo " "
log_info "=== Deploying Model with Kustomize ==="
echo -e "Model: ${GREEN}${MODEL_PATH}${NC}"

APPLY_OUTPUT="$($KUBECTL_CMD apply -k "$TMP_DIR" -o name)"
echo "$APPLY_OUTPUT"

readarray -t DEPLOYMENTS < <(echo "$APPLY_OUTPUT" | sed -n 's|^deployment\.apps/||p')

# --- Wait for readiness ------------------------------------------------------
echo " "
log_info "=== Waiting for deployments to be ready (timeout: ${TIMEOUT}s each) ==="
log_info "Note: first-time GPU model deployments pull large images and download weights; this can take 20+ minutes."

WAIT_FAILED=false
for deployment in "${DEPLOYMENTS[@]}"; do
  echo " "
  log_info "Waiting for deployment/$deployment in namespace '$NAMESPACE'..."
  if $KUBECTL_CMD rollout status "deployment/$deployment" -n "$NAMESPACE" --timeout="${TIMEOUT}s"; then
    log_ok "deployment/$deployment is ready."
  else
    WAIT_FAILED=true
    log_err "deployment/$deployment did not become ready within ${TIMEOUT}s."
    log_warn "Deployment status:"
    $KUBECTL_CMD describe "deployment/$deployment" -n "$NAMESPACE" || true
    log_warn "Pod status:"
    $KUBECTL_CMD get pods -n "$NAMESPACE" -o wide || true
    log_warn "Recent events:"
    $KUBECTL_CMD get events -n "$NAMESPACE" --sort-by=.lastTimestamp | tail -n 20 || true
  fi
done

# --- Summary -----------------------------------------------------------------
echo " "
log_info "=== Deployment Summary ==="
echo -e "Model: ${BLUE}${MODEL_PATH}${NC}"
echo -e "Namespace: ${BLUE}${NAMESPACE}${NC}"

echo " "
log_info "=== Resources ==="
$KUBECTL_CMD get all -n "$NAMESPACE" || true

if [[ "$KUBECTL_CMD" == "oc" ]]; then
  echo " "
  log_info "=== Routes ==="
  $KUBECTL_CMD get route -n "$NAMESPACE" || true
fi

echo " "
if [[ "$WAIT_FAILED" == true ]]; then
  log_err "=== Deployment finished with errors: not all deployments became ready ==="
  exit 1
fi
log_ok "=== Deployment finished ==="
