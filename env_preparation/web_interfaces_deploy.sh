#!/usr/bin/env bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEB_INTERFACES_DIR="$SCRIPT_DIR/../web_interfaces"

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

echo -e "${BLUE}=== Welcome to Web Interfaces Deployment Helper ===${NC}"
echo "This script will deploy any web interface from the web_interfaces directory using kustomize."

echo " "
echo "**********************"
echo "**********************"

# Get web interface path from argument or prompt
if [[ $# -gt 0 ]]; then
  WEB_INTERFACE_PATH="$1"
else
  echo -e "${BLUE}=== Available Web Interfaces ===${NC}"
  # Find all directories with kustomization.yaml
  echo "Scanning for web interfaces with kustomization.yaml..."
  readarray -t WEB_INTERFACES < <(find "$WEB_INTERFACES_DIR" -name "kustomization.yaml" -type f -exec dirname {} \; | sed "s|$WEB_INTERFACES_DIR/||" | sort)
  
  if [[ ${#WEB_INTERFACES[@]} -eq 0 ]]; then
    echo -e "${RED}Error: No web interfaces with kustomization.yaml found in $WEB_INTERFACES_DIR${NC}"
    exit 1
  fi
  
  for i in "${!WEB_INTERFACES[@]}"; do
    echo "  $((i+1)). ${WEB_INTERFACES[$i]}"
  done
  
  echo " "
  read -r -p "Select web interface by number: " WEB_INTERFACE_CHOICE
  
  if ! [[ "$WEB_INTERFACE_CHOICE" =~ ^[0-9]+$ ]] || [[ $WEB_INTERFACE_CHOICE -lt 1 ]] || [[ $WEB_INTERFACE_CHOICE -gt ${#WEB_INTERFACES[@]} ]]; then
    echo -e "${RED}Error: Invalid selection.${NC}"
    exit 1
  fi
  
  WEB_INTERFACE_PATH="${WEB_INTERFACES[$((WEB_INTERFACE_CHOICE-1))]}"
fi

WEB_INTERFACE_DIR="$WEB_INTERFACES_DIR/$WEB_INTERFACE_PATH"

if [[ ! -d "$WEB_INTERFACE_DIR" ]]; then
  echo -e "${RED}Error: Web interface directory not found: $WEB_INTERFACE_DIR${NC}"
  exit 1
fi

if [[ ! -f "$WEB_INTERFACE_DIR/kustomization.yaml" ]]; then
  echo -e "${RED}Error: kustomization.yaml not found in $WEB_INTERFACE_DIR${NC}"
  exit 1
fi

echo -e "${GREEN}Selected web interface: $WEB_INTERFACE_PATH${NC}"
echo "Web interface directory: $WEB_INTERFACE_DIR"

echo " "
echo "**********************"
read -r -p "Enter STORAGE_CLASS_NAME (leave blank for default cluster storage): " STORAGE_CLASS_NAME
if [[ -n "${STORAGE_CLASS_NAME:-}" ]]; then
  echo -e "${BLUE}=== Substituting STORAGE_CLASS_NAME into PVC manifests ===${NC}"
  if ! command -v envsubst >/dev/null 2>&1; then
    echo -e "${RED}Error: envsubst is required to replace STORAGE_CLASS_NAME.${NC}"
    exit 1
  fi
  
  # Find all pvc.yaml files in the web interface directory and substitute
  while IFS= read -r pvc_file; do
    if [[ -f "$pvc_file" ]]; then
      export STORAGE_CLASS_NAME
      envsubst < "$pvc_file" > "$pvc_file.tmp"
      mv "$pvc_file.tmp" "$pvc_file"
      echo -e "${GREEN}Updated: $(basename $(dirname "$pvc_file"))/pvc.yaml${NC}"
    fi
  done < <(find "$WEB_INTERFACE_DIR" -name "pvc.yaml" -type f)
else
  echo -e "${YELLOW}Using default storage class.${NC}"
fi

echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deploying Web Interface with Kustomize ===${NC}"
echo "Web Interface: ${GREEN}${WEB_INTERFACE_PATH}${NC}"
echo "**********************"
echo "**********************"

$KUBECTL_CMD apply -k "$WEB_INTERFACE_DIR"

echo "**********************"
echo -e "${BLUE}=== Waiting for Deployments to be ready (up to 6 minutes) ===${NC}"
echo "**********************"

wait_for_deployments_ready() {
  local max_attempts=18
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    # Get all deployments in the namespace
    local deployments=$($KUBECTL_CMD get deployments -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
    
    if [[ -z "$deployments" ]]; then
      echo -e "${YELLOW}[$attempt/$max_attempts] Waiting for deployments to appear...${NC}"
      sleep 30
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
  echo -e "${RED}✗ Deployments did not reach ready state within 6 minutes${NC}"
  echo -e "${YELLOW}Current status:${NC}"
  $KUBECTL_CMD get deployments || true
  echo -e "${YELLOW}Pod status:${NC}"
  $KUBECTL_CMD get pods || true
  return 1
}

wait_for_deployments_ready

echo " "
echo "**********************"
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo "**********************"
echo -e "Web Interface: ${BLUE}${WEB_INTERFACE_PATH}${NC}"
echo -e "Web Interface Directory: ${BLUE}${WEB_INTERFACE_DIR}${NC}"

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
