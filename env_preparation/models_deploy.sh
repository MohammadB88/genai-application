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

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

# Ensure llms namespace exists
if ! $KUBECTL_CMD get namespace llms >/dev/null 2>&1; then
  echo -e "${YELLOW}Namespace 'llms' not found. Creating it...${NC}"
  $KUBECTL_CMD create namespace llms
  echo -e "${GREEN}Namespace 'llms' created.${NC}"
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

# NVIDIA NIM models need NGC API key and docker-registry pull secret
if [[ "$MODEL_PATH" == nvidia_nim/* ]]; then
  echo " "
  echo "**********************"
  echo -e "${BLUE}=== NVIDIA NIM Model Configuration ===${NC}"
  read -r -s -p "Enter your NVIDIA API KEY (NGC): " NVIDIA_API_KEY
  echo

  # Update secret.yaml with the provided key
  SECRET_FILE="$MODEL_DIR/secret.yaml"
  if [[ -f "$SECRET_FILE" ]]; then
    sed -i "s/NGC_API_KEY:.*/NGC_API_KEY: $NVIDIA_API_KEY/" "$SECRET_FILE"
    echo -e "${GREEN}Updated: secret.yaml with NGC_API_KEY${NC}"
  fi

  # Apply secret.yaml directly so kustomization.yaml stays clean
  $KUBECTL_CMD apply -f "$SECRET_FILE"
  echo -e "${GREEN}Applied secret.yaml for ngc-api-key${NC}"

  # Create/apply docker-registry secret for nvcr.io
  echo -e "${BLUE}Creating docker-registry secret 'nim-pull-secret' for nvcr.io...${NC}"
  $KUBECTL_CMD create secret docker-registry nim-pull-secret \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password="$NVIDIA_API_KEY" \
    -n llms \
    --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
  echo -e "${GREEN}Docker-registry secret 'nim-pull-secret' created/updated.${NC}"
fi

echo " "
echo "**********************"
echo -e "${BLUE}=== Available Storage Classes ===${NC}"
SC_NAMES=()
while IFS= read -r line; do
  SC_NAMES+=("$line")
done < <($KUBECTL_CMD get storageclass -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

if [[ ${#SC_NAMES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No storage classes found. Using cluster default.${NC}"
  STORAGE_CLASS_NAME=""
else
  for i in "${!SC_NAMES[@]}"; do
    echo "  $((i+1)). ${SC_NAMES[$i]}"
  done
  echo "  $((${#SC_NAMES[@]}+1)). Use cluster default (no storageClassName)"
  echo " "
  read -r -p "Select storage class by number: " SC_CHOICE
  if [[ "$SC_CHOICE" =~ ^[0-9]+$ ]] && [[ "$SC_CHOICE" -ge 1 ]] && [[ "$SC_CHOICE" -le ${#SC_NAMES[@]} ]]; then
    STORAGE_CLASS_NAME="${SC_NAMES[$((SC_CHOICE-1))]}"
    echo -e "${GREEN}Selected storage class: $STORAGE_CLASS_NAME${NC}"
  else
    STORAGE_CLASS_NAME=""
    echo -e "${YELLOW}Using cluster default storage class.${NC}"
  fi
fi

# Apply storage class to PVC manifests
PVC_FILES=()
while IFS= read -r f; do
  PVC_FILES+=("$f")
done < <(find "$MODEL_DIR" -name "pvc.yaml" -type f)

if [[ -n "${STORAGE_CLASS_NAME:-}" ]]; then
  echo -e "${BLUE}=== Setting STORAGE_CLASS_NAME to '${STORAGE_CLASS_NAME}' in PVC manifests ===${NC}"
  for pvc_file in "${PVC_FILES[@]}"; do
    sed -i "s/^  storageClassName:.*/  storageClassName: $STORAGE_CLASS_NAME/" "$pvc_file"
    echo -e "${GREEN}Updated: ${pvc_file#$MODELS_DIR/}${NC}"
  done
else
  echo -e "${YELLOW}No storage class selected. Commenting out storageClassName to use cluster default.${NC}"
  for pvc_file in "${PVC_FILES[@]}"; do
    sed -i "s/^  storageClassName:.*/#  storageClassName: default/" "$pvc_file"
    echo -e "${GREEN}Cleared: ${pvc_file#$MODELS_DIR/}${NC}"
  done
fi

echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deploying Model with Kustomize ===${NC}"
echo "Model: ${GREEN}${MODEL_PATH}${NC}"
echo "**********************"
echo "**********************"

$KUBECTL_CMD apply -k "$MODEL_DIR"

echo "**********************"
echo -e "${BLUE}=== Waiting for Deployments to be ready (up to 5 minutes) ===${NC}"
echo "**********************"

wait_for_deployments_ready() {
  local max_attempts=30
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    # Get all deployments in the namespace
    local deployments=$($KUBECTL_CMD get deployments -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$deployments" ]]; then
      echo -e "${YELLOW}[$attempt/$max_attempts] Waiting for deployments to appear...${NC}"
      sleep 10
      ((attempt++))
      continue
    fi
    
    # Check if all deployments are ready
    local all_ready=true
    for deployment in $deployments; do
      local ready_replicas=$($KUBECTL_CMD get deployment "$deployment" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
      local desired_replicas=$($KUBECTL_CMD get deployment "$deployment" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
      
      if [[ "$ready_replicas" != "$desired_replicas" ]] || [[ "$ready_replicas" == "0" ]]; then
        all_ready=false
        break
      fi
    done
    
    if [[ "$all_ready" == true ]]; then
      echo -e "${GREEN}✓ All deployments are READY!${NC}"
      for deployment in $deployments; do
        local ready_replicas=$($KUBECTL_CMD get deployment "$deployment" -o jsonpath='{.status.readyReplicas}')
        local desired_replicas=$($KUBECTL_CMD get deployment "$deployment" -o jsonpath='{.spec.replicas}')
        echo -e "${GREEN}  - $deployment: $ready_replicas/$desired_replicas replicas${NC}"
      done
      return 0
    fi
    
    # Still waiting - show status
    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 10))
    echo -e "${YELLOW}[$attempt/$max_attempts] Checking deployments... | $remaining_time${NC}"
    
    sleep 10
    ((attempt++))
  done
  
  # Timeout reached
  echo -e "${RED}✗ Deployments did not reach ready state within 5 minutes${NC}"
  echo -e "${YELLOW}Current status:${NC}"
  $KUBECTL_CMD get deployments || true
  echo -e "${YELLOW}Pod status:${NC}"
  $KUBECTL_CMD get pods || true
  return 1
}

wait_for_deployments_ready

echo "**********************"
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo "**********************"
echo -e "Model: ${BLUE}${MODEL_PATH}${NC}"
echo -e "Model Directory: ${BLUE}${MODEL_DIR}${NC}"

echo " "
echo -e "${BLUE}=== Resources ===${NC}"
$KUBECTL_CMD get all || true

if [[ "$KUBECTL_CMD" == "oc" ]]; then
  echo " "
  echo -e "${BLUE}=== Routes ===${NC}"
  $KUBECTL_CMD get route || true
fi

echo "**********************"
echo -e "${GREEN}=== Deployment finished ===${NC}"
echo "**********************"
