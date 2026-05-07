#!/usr/bin/env bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRAFANA_NAMESPACE="grafana"
GRAFANA_RELEASE="grafana"

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

echo -e "${BLUE}=== Monitoring Cleanup Helper ===${NC}"
echo "This script will remove Grafana and associated resources."

echo " "
echo "**********************"
echo "**********************"

# Check if Grafana namespace exists
if ! $KUBECTL_CMD get project "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${YELLOW}Grafana namespace '$GRAFANA_NAMESPACE' does not exist. Nothing to clean up.${NC}"
  exit 0
fi

echo " "
read -r -p "Delete Grafana project and all resources? [y/N]: " CONFIRM_DELETE
if ! [[ "$CONFIRM_DELETE" =~ ^([yY]|[yY][eE][sS])$ ]]; then
  echo -e "${YELLOW}Cleanup cancelled.${NC}"
  exit 0
fi

echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deleting Grafana Helm release ===${NC}"
echo "**********************"

if helm status "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${BLUE}Uninstalling Helm release '$GRAFANA_RELEASE'...${NC}"
  helm uninstall "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" || true
  echo -e "${GREEN}Helm release uninstalled.${NC}"
else
  echo -e "${YELLOW}Helm release '$GRAFANA_RELEASE' not found.${NC}"
fi

echo " "
echo -e "${BLUE}=== Deleting Grafana project ===${NC}"
$KUBECTL_CMD delete project "$GRAFANA_NAMESPACE" || true
echo -e "${GREEN}Project deletion initiated.${NC}"

echo " "
echo "**********************"
echo -e "${BLUE}=== Waiting for resources to be deleted (up to 2 minutes) ===${NC}"
echo "**********************"

wait_for_deletion() {
  local max_attempts=60
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    if ! $KUBECTL_CMD get project "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
      echo -e "${GREEN}✓ Project '$GRAFANA_NAMESPACE' deleted successfully!${NC}"
      return 0
    fi
    
    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 2))
    echo -e "${YELLOW}[$attempt/$max_attempts] Waiting for project deletion... | $remaining_time${NC}"
    
    sleep 2
    ((attempt++))
  done
  
  echo -e "${YELLOW}Deletion timeout reached. Project may still exist.${NC}"
  return 1
}

wait_for_deletion

echo " "
echo "**********************"
echo -e "${BLUE}=== Cleanup Summary ===${NC}"
echo "**********************"

if $KUBECTL_CMD get project "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
  echo -e "Grafana status: ${YELLOW}Project still exists${NC}"
  echo -e "To force deletion, run: ${BLUE}$KUBECTL_CMD delete project $GRAFANA_NAMESPACE --force${NC}"
else
  echo -e "Grafana status: ${GREEN}Successfully removed${NC}"
fi

echo " "
echo "**********************"
echo -e "${GREEN}=== Cleanup finished ===${NC}"
echo "**********************"
