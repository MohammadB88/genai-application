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

echo -e "${BLUE}=== Web Interfaces Cleanup Helper ===${NC}"
echo "This script will remove deployed web interfaces and their resources."

echo " "
echo "**********************"
echo "**********************"

# Get deployed web interfaces based on kustomization.yaml paths
echo -e "${BLUE}=== Discovering deployed web interfaces ===${NC}"
readarray -t DEPLOYED_WEB_INTERFACES < <(find "$WEB_INTERFACES_DIR" -name "kustomization.yaml" -type f -exec dirname {} \; | sed "s|$WEB_INTERFACES_DIR/||" | sort)

if [[ ${#DEPLOYED_WEB_INTERFACES[@]} -eq 0 ]]; then
  echo -e "${YELLOW}No web interfaces found with kustomization.yaml.${NC}"
  exit 0
fi

echo " "
read -r -p "Delete all web interfaces? [y/N]: " DELETE_ALL
if [[ "$DELETE_ALL" =~ ^([yY]|[yY][eE][sS])$ ]]; then
  WEB_INTERFACES_TO_DELETE=("${DEPLOYED_WEB_INTERFACES[@]}")
else
  echo " "
  echo -e "${BLUE}=== Select Web Interfaces to Delete ===${NC}"
  for i in "${!DEPLOYED_WEB_INTERFACES[@]}"; do
    echo "  $((i+1)). ${DEPLOYED_WEB_INTERFACES[$i]}"
  done
  echo "  0. Cancel cleanup"
  
  echo " "
  read -r -p "Select web interface(s) by number (comma-separated for multiple, e.g., '1,3'): " WEB_INTERFACE_CHOICE
  
  if [[ "$WEB_INTERFACE_CHOICE" == "0" ]]; then
    echo -e "${YELLOW}Cleanup cancelled.${NC}"
    exit 0
  fi
  
  WEB_INTERFACES_TO_DELETE=()
  IFS=',' read -ra CHOICES <<< "$WEB_INTERFACE_CHOICE"
  for choice in "${CHOICES[@]}"; do
    choice=$(echo "$choice" | xargs) # trim whitespace
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 ]] || [[ $choice -gt ${#DEPLOYED_WEB_INTERFACES[@]} ]]; then
      echo -e "${RED}Error: Invalid selection '$choice'.${NC}"
      exit 1
    fi
    WEB_INTERFACES_TO_DELETE+=("${DEPLOYED_WEB_INTERFACES[$((choice-1))]}")
  done
fi

echo " "
echo "**********************"
echo -e "${BLUE}=== Web Interfaces to delete ===${NC}"
for i in "${!WEB_INTERFACES_TO_DELETE[@]}"; do
  echo "  $((i+1)). ${WEB_INTERFACES_TO_DELETE[$i]}"
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
echo -e "${BLUE}=== Deleting web interfaces ===${NC}"
echo "**********************"

for web_interface in "${WEB_INTERFACES_TO_DELETE[@]}"; do
  WEB_INTERFACE_DIR="$WEB_INTERFACES_DIR/$web_interface"
  
  if [[ ! -d "$WEB_INTERFACE_DIR" ]]; then
    echo -e "${YELLOW}Web interface directory not found: $WEB_INTERFACE_DIR (skipping)${NC}"
    continue
  fi
  
  if [[ ! -f "$WEB_INTERFACE_DIR/kustomization.yaml" ]]; then
    echo -e "${YELLOW}No kustomization.yaml found in $WEB_INTERFACE_DIR (skipping)${NC}"
    continue
  fi
  
  echo " "
  echo -e "${BLUE}Deleting web interface: ${web_interface}${NC}"
  $KUBECTL_CMD delete -k "$WEB_INTERFACE_DIR" || true
  echo -e "${GREEN}Web interface delete command issued.${NC}"
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
echo -e "Web Interfaces deleted: ${BLUE}${#WEB_INTERFACES_TO_DELETE[@]}${NC}"

echo " "
echo -e "${BLUE}=== Remaining resources ===${NC}"
$KUBECTL_CMD get all 2>/dev/null || echo -e "${GREEN}No resources found.${NC}"

echo " "
echo "**********************"
echo -e "${GREEN}=== Cleanup finished ===${NC}"
echo "**********************"
