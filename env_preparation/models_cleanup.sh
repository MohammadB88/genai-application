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

echo -e "${BLUE}=== Model Cleanup Helper ===${NC}"
echo "This script will remove deployed models and their resources."

echo " "
echo "**********************"
echo "**********************"

# Get deployed models based on kustomization.yaml paths
echo -e "${BLUE}=== Discovering deployed models ===${NC}"
readarray -t DEPLOYED_MODELS < <(find "$MODELS_DIR" -name "kustomization.yaml" -type f -exec dirname {} \; | sed "s|$MODELS_DIR/||" | sort)

if [[ ${#DEPLOYED_MODELS[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No models found with kustomization.yaml.${NC}"
  exit 0
fi

echo " "
read -r -p "Delete all models? [y/N]: " DELETE_ALL
if [[ "$DELETE_ALL" =~ ^([yY]|[yY][eE][sS])$ ]]; then
  MODELS_TO_DELETE=("${DEPLOYED_MODELS[@]}")
else
  echo " "
  echo -e "${BLUE}=== Select Models to Delete ===${NC}"
  for i in "${!DEPLOYED_MODELS[@]}"; do
    echo "  $((i+1)). ${DEPLOYED_MODELS[$i]}"
  done
  echo "  0. Cancel cleanup"
  
  echo " "
  read -r -p "Select model(s) by number (comma-separated for multiple, e.g., '1,3'): " MODEL_CHOICE
  
  if [[ "$MODEL_CHOICE" == "0" ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
  fi
  
  MODELS_TO_DELETE=()
  IFS=',' read -ra CHOICES <<< "$MODEL_CHOICE"
  for choice in "${CHOICES[@]}"; do
    choice=$(echo "$choice" | xargs) # trim whitespace
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#DEPLOYED_MODELS[@]} ]]; then
      echo -e "${RED}Error: Invalid selection '$choice'.${NC}"
      exit 1
    fi
    MODELS_TO_DELETE+=("${DEPLOYED_MODELS[$((choice-1))]}")
  done
fi

echo " "
echo "**********************"
echo -e "${BLUE}=== Models to delete ===${NC}"
for i in "${!MODELS_TO_DELETE[@]}"; do
  echo "  $((i+1)). ${MODELS_TO_DELETE[$i]}"
done
echo "**********************"

read -r -p "Confirm deletion? [y/N]: " CONFIRM_DELETE
if ! [[ "$CONFIRM_DELETE" =~ ^([yY]|[yY][eE][sS])$ ]]; then
  echo -e "${YELLOW}Cleanup cancelled.${NC}"
  exit 0
fi

echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deleting models ===${NC}"
echo "**********************"

for model in "${MODELS_TO_DELETE[@]}"; do
  MODEL_DIR="$MODELS_DIR/$model"
  
  if [[ ! -d "$MODEL_DIR" ]]; then
    echo -e "${YELLOW}Model directory not found: $MODEL_DIR (skipping)${NC}"
    continue
  fi
  
  if [[ ! -f "$MODEL_DIR/kustomization.yaml" ]]; then
    echo -e "${YELLOW}No kustomization.yaml found in $MODEL_DIR (skipping)${NC}"
    continue
  fi
  
  echo " "
  echo -e "${BLUE}Deleting model: ${model}${NC}"
  $KUBECTL_CMD delete -k "$MODEL_DIR" || true
  echo -e "${GREEN}Model delete command issued.${NC}"
done

echo " "
echo "**********************"
echo -e "${BLUE}=== Waiting for resources to be deleted (up to 2 minutes) ===${NC}"
echo "**********************"

wait_for_deletion() {
  local max_attempts=60
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    local remaining_resources=$($KUBECTL_CMD get all --no-headers 2>/dev/null | wc -l)
    
    if [[ $remaining_resources -eq 0 ]]; then
      echo -e "${GREEN}✓ All resources deleted successfully!${NC}"
      return 0
    fi
    
    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 2))
    echo -e "${YELLOW}[$attempt/$max_attempts] Waiting for $remaining_resources resource(s) to be deleted... | $remaining_time${NC}"
    
    sleep 2
    ((attempt++))
  done
  
  echo -e "${YELLOW}Deletion timeout reached. Remaining resources:${NC}"
  $KUBECTL_CMD get all || true
  return 1
}

wait_for_deletion

echo " "
echo "**********************"
echo -e "${BLUE}=== Cleanup Summary ===${NC}"
echo "**********************"
echo -e "Models deleted: ${BLUE}${#MODELS_TO_DELETE[@]}${NC}"

echo " "
echo -e "${BLUE}=== Remaining resources ===${NC}"
$KUBECTL_CMD get all 2>/dev/null || echo -e "${GREEN}No resources found.${NC}"

echo " "
echo "**********************"
echo -e "${GREEN}=== Cleanup finished ===${NC}"
echo "**********************"
