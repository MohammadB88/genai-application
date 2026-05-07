#!/usr/bin/env bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="$SCRIPT_DIR/../models"
NAMESPACE="llms"

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

echo -e "${BLUE}=== Welcome to Model Deployment Helper ===${NC}"
echo "This script will deploy any model from the models directory using kustomize."

echo " "
echo "**********************"
echo "**********************"

# Get model path from argument or prompt
if [[ $# -gt 0 ]]; then
  MODEL_PATH="$1"
else
  echo -e "${BLUE}=== Available Models ===${NC}"
  # Find all directories with kustomization.yaml
  echo "Scanning for models with kustomization.yaml..."
  readarray -t MODELS < <(find "$MODELS_DIR" -name "kustomization.yaml" -type f -exec dirname {} \; | sed "s|$MODELS_DIR/||" | sort)
  
  if [[ ${#MODELS[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No models with kustomization.yaml found in $MODELS_DIR${NC}"
    exit 1
  fi
  
  for i in "${!MODELS[@]}"; do
    echo "  $((i+1)). ${MODELS[$i]}"
  done
  
  echo " "
  read -r -p "Select model by number: " MODEL_CHOICE
  
  if ! [[ "$MODEL_CHOICE" =~ ^[0-9]+$ ]] || [[ $MODEL_CHOICE -lt 1 ]] || [[ $MODEL_CHOICE -gt ${#MODELS[@]} ]]; then
    echo -e "${RED}Error: Invalid selection.${NC}"
    exit 1
  fi
  
  MODEL_PATH="${MODELS[$((MODEL_CHOICE-1))]}"
fi

MODEL_DIR="$MODELS_DIR/$MODEL_PATH"

if [[ ! -d "$MODEL_DIR" ]]; then
  echo -e "${RED}Error: Model directory not found: $MODEL_DIR${NC}"
  exit 1
fi

if [[ ! -f "$MODEL_DIR/kustomization.yaml" ]]; then
  echo -e "${RED}Error: kustomization.yaml not found in $MODEL_DIR${NC}"
  exit 1
fi

echo -e "${GREEN}Selected model: $MODEL_PATH${NC}"
echo "Model directory: $MODEL_DIR"

# Ensure namespace exists
echo -e "${BLUE}=== Creating namespace '${NAMESPACE}' if needed ===${NC}"
$KUBECTL_CMD create namespace "$NAMESPACE" --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
echo -e "${GREEN}Namespace ready.${NC}"

echo " "
echo "**********************"
read -r -p "Enter STORAGE_CLASS_NAME (leave blank for default cluster storage): " STORAGE_CLASS_NAME
if [[ -n "${STORAGE_CLASS_NAME:-}" ]]; then
  echo -e "${BLUE}=== Substituting STORAGE_CLASS_NAME into PVC manifests ===${NC}"
  if ! command -v envsubst >/dev/null 2>&1; then
    echo -e "${RED}Error: envsubst is required to replace STORAGE_CLASS_NAME.${NC}"
    exit 1
  fi
  
  # Find all pvc.yaml files in the model directory and substitute
  while IFS= read -r pvc_file; do
    if [[ -f "$pvc_file" ]]; then
      export STORAGE_CLASS_NAME
      envsubst < "$pvc_file" > "$pvc_file.tmp"
      mv "$pvc_file.tmp" "$pvc_file"
      echo -e "${GREEN}Updated: $(basename $(dirname "$pvc_file"))/pvc.yaml${NC}"
    fi
  done < <(find "$MODEL_DIR" -name "pvc.yaml" -type f)
else
  echo -e "${YELLOW}Using default storage class.${NC}"
fi

echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deploying Model with Kustomize ===${NC}"
echo "Model: ${GREEN}${MODEL_PATH}${NC}"
echo "**********************"
echo "**********************"

$KUBECTL_CMD apply -k "$MODEL_DIR" -n "$NAMESPACE"

echo "**********************"
echo -e "${BLUE}=== Waiting for Deployments to be ready (up to 5 minutes) ===${NC}"
echo "**********************"

wait_for_deployments_ready() {
  local max_attempts=150
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    # Get all deployments in the namespace
    local deployments=$($KUBECTL_CMD get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$deployments" ]]; then
      echo -e "${YELLOW}[$attempt/$max_attempts] Waiting for deployments to appear...${NC}"
      sleep 2
      ((attempt++))
      continue
    fi
    
    # Check if all deployments are ready
    local all_ready=true
    for deployment in $deployments; do
      local ready_replicas=$($KUBECTL_CMD get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      local desired_replicas=$($KUBECTL_CMD get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
      
      if [[ "$ready_replicas" != "$desired_replicas" ]] || [[ "$ready_replicas" == "0" ]]; then
        all_ready=false
        break
      fi
    done
    
    if [[ "$all_ready" == true ]]; then
      echo -e "${GREEN}✓ All deployments are READY!${NC}"
      for deployment in $deployments; do
        local ready_replicas=$($KUBECTL_CMD get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
        local desired_replicas=$($KUBECTL_CMD get deployment "$deployment" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')
        echo -e "${GREEN}  - $deployment: $ready_replicas/$desired_replicas replicas${NC}"
      done
      return 0
    fi
    
    # Still waiting - show status
    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 2))
    echo -e "${YELLOW}[$attempt/$max_attempts] Checking deployments... | $remaining_time${NC}"
    
    sleep 2
    ((attempt++))
  done
  
  # Timeout reached
  echo -e "${RED}✗ Deployments did not reach ready state within 5 minutes${NC}"
  echo -e "${YELLOW}Current status:${NC}"
  $KUBECTL_CMD get deployments -n "$NAMESPACE" || true
  echo -e "${YELLOW}Pod status:${NC}"
  $KUBECTL_CMD get pods -n "$NAMESPACE" || true
  return 1
}

wait_for_deployments_ready

echo "**********************"
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo "**********************"
echo -e "Namespace: ${BLUE}${NAMESPACE}${NC}"
echo -e "Model: ${BLUE}${MODEL_PATH}${NC}"
echo -e "Model Directory: ${BLUE}${MODEL_DIR}${NC}"

echo " "
echo -e "${BLUE}=== Resources ===${NC}"
$KUBECTL_CMD get all -n "$NAMESPACE" || true

if [[ "$KUBECTL_CMD" == "oc" ]]; then
  echo " "
  echo -e "${BLUE}=== Routes ===${NC}"
  $KUBECTL_CMD get route -n "$NAMESPACE" || true
fi

echo "**********************"
echo -e "${GREEN}=== Deployment finished ===${NC}"
echo "**********************"
