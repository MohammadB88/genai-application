#!/usr/bin/env bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_APP_FILE="$SCRIPT_DIR/../gitops/root-application.yaml"
APP_NAME="genai-root"
APP_NAMESPACE="openshift-gitops"

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

echo -e "${BLUE}=== Welcome to the GenAI Application Deployment Helper ===${NC}"
echo "This script will help you deploy the root Argo CD application for the GenAI demo environment. It will also prompt you to set up necessary secrets for model deployments."

echo " "
echo "**********************"
echo -e "${BLUE}=== Secret setup option ===${NC}"
read -r -p "Create secrets in namespace 'llms'? [y/N]: " CREATE_SECRET_ANSWER
if [[ "$CREATE_SECRET_ANSWER" =~ ^([yY]|[yY][eE][sS])$ ]]; then
  echo "**********************"
  echo -e "${BLUE}=== NGC API key required ===${NC}"
  echo -n "Enter ngc_api_key: "
  read -r -s NGC_API_KEY
  echo
  if [[ -z "${NGC_API_KEY:-}" ]]; then
    echo -e "${RED}Error: ngc_api_key is required.${NC}"
    exit 1
  fi

  echo -e "${GREEN}NGC API key received.${NC}"
  echo "**********************"


  echo "**********************"
  echo -e "${BLUE}=== Creating secrets in namespace 'llms' ===${NC}"
  echo "**********************"
  $KUBECTL_CMD create namespace llms --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
  
  $KUBECTL_CMD create secret generic ngc-api-key \
    --from-literal=NGC_API_KEY="$NGC_API_KEY" \
    -n llms --dry-run=client -o yaml | $KUBECTL_CMD apply -f -

  $KUBECTL_CMD create secret docker-registry nim-pull-secret \
    --docker-server='nvcr.io' \
    --docker-username='\$oauthtoken' \
    --docker-password="$NGC_API_KEY" \
    -n llms --dry-run=client -o yaml | $KUBECTL_CMD apply -f -

  echo -e "${GREEN}Secrets created in namespace 'llms'.${NC}"
  echo "**********************"
else
  echo -e "${YELLOW}Skipping secret creation for namespace 'llms'.${NC}"
  echo "**********************"
fi

echo " "
echo "**********************"
echo -e "${BLUE}=== Deploying root Argo CD application ===${NC}"
echo "**********************"

$KUBECTL_CMD apply -f "$ROOT_APP_FILE"

echo "**********************"
echo -e "${BLUE}=== Waiting for Application '$APP_NAME' to be ready (up to 2 minutes) ===${NC}"
echo "**********************"

wait_for_app_ready() {
  local max_attempts=60
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    # Check if application exists
    if ! $KUBECTL_CMD get applications.argoproj.io "$APP_NAME" -n "$APP_NAMESPACE" >/dev/null 2>&1; then
      echo -e "${YELLOW}[$attempt/$max_attempts] Waiting for Application '$APP_NAME' resource to appear...${NC}"
      sleep 2
      ((attempt++))
      continue
    fi
    
    # Check if application is synced and healthy
    local sync_status=$($KUBECTL_CMD get applications.argoproj.io "$APP_NAME" -n "$APP_NAMESPACE" -o jsonpath='{.status.operationState.phase}' 2>/dev/null || echo "Unknown")
    local health_status=$($KUBECTL_CMD get applications.argoproj.io "$APP_NAME" -n "$APP_NAMESPACE" -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
    
    if [[ "$sync_status" == "Succeeded" ]] && [[ "$health_status" == "Healthy" ]]; then
      echo -e "${GREEN}✓ Application '$APP_NAME' is READY!${NC}"
      echo -e "${GREEN}  Sync Status: $sync_status${NC}"
      echo -e "${GREEN}  Health Status: $health_status${NC}"
      return 0
    fi
    
    # Still waiting
    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 2))
    echo -e "${YELLOW}[$attempt/$max_attempts] Sync: $sync_status | Health: $health_status | $remaining_time${NC}"
    
    sleep 2
    ((attempt++))
  done
  
  # Timeout reached
  echo -e "${RED}✗ Application did not reach ready state within 2 minutes${NC}"
  echo -e "${YELLOW}Current status:${NC}"
  $KUBECTL_CMD describe applications.argoproj.io "$APP_NAME" -n "$APP_NAMESPACE" || true
  return 1
}

wait_for_app_ready

echo "**********************"
if [[ "$KUBECTL_CMD" == "oc" ]]; then
  echo -e "${BLUE}=== Listing available OpenShift routes ===${NC}"
  echo "**********************"
  oc get route --all-namespaces -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,HOST:.spec.host,TLS:.spec.tls.termination --no-headers | awk '{scheme = ($4 == "" ? "http://" : "https://"); print $1 " " $2 " " scheme $3}'
else
  echo -e "${YELLOW}Note: route listing is only supported with 'oc' in OpenShift environments.${NC}"
fi

echo "**********************"
echo -e "${GREEN}=== Deployment helper finished ===${NC}"
echo "**********************"



# Since I am deploying it with argocd-applications, I should find a way for it so that ArgoCD replaces the variables in pvc.yaml with the user input. 
# echo " "
# read -r -p "Enter STORAGE_CLASS_NAME (leave blank for default cluster storage): " STORAGE_CLASS_NAME
# if [[ -n "${STORAGE_CLASS_NAME:-}" ]]; then
#   echo -e "${BLUE}=== Substituting STORAGE_CLASS_NAME into PVC manifest ===${NC}"
#   if ! command -v envsubst >/dev/null 2>&1; then
#     echo -e "${RED}Error: envsubst is required to replace STORAGE_CLASS_NAME.${NC}"
#     exit 1
#   fi
#   export STORAGE_CLASS_NAME
#   envsubst < "$SCRIPT_DIR/../models/vllm/cpu/granite-318b/pvc.yaml" | oc apply -f -
#   mv "$SCRIPT_DIR/../models/vllm/cpu/granite-318b/pvc.yaml.tmp" "$SCRIPT_DIR/../models/vllm/cpu/granite-318b/pvc.yaml"
#   echo -e "${GREEN}Updated PVC manifest with storage class: ${STORAGE_CLASS_NAME}${NC}"
# fi