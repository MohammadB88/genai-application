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

# echo " "
# echo "**********************"
# echo "**********************"
# echo -e "${BLUE}=== Preparing LiteMaaS installation ===${NC}"
# echo "**********************"
# echo "**********************"

# echo -e "${BLUE}=== Detecting cluster URL ===${NC}"
# # Detect cluster URL from kubeconfig
# detect_cluster_url() {
#   local api_server
#   api_server=$($KUBECTL_CMD cluster-info | grep 'Kubernetes master' | awk -F'[:/]' '{print $NF}')
  
#   if [[ -z "$api_server" ]]; then
#     # Fallback: extract from kubeconfig
#     api_server=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed 's|https://||' | sed 's|http://||' | cut -d':' -f1)
#   fi
  
#   echo "$api_server"
# }

# CLUSTER_URL="$(detect_cluster_url || echo "")"
# if [[ -z "$CLUSTER_URL" ]]; then
#   echo -e "${RED}Error: Could not detect cluster URL.${NC}"
#   exit 1
# fi

# echo -e "${GREEN}Detected cluster URL: $CLUSTER_URL${NC}"

# LITEMAAS_DIR="$SCRIPT_DIR/../ai-gateways/litemaas"
# OAUTHCLIENT_FILE="$LITEMAAS_DIR/oauthclient.yaml"
# USERS_SCRIPT="$LITEMAAS_DIR/users.sh"
# VALUES_FILE="$LITEMAAS_DIR/values_oc.yaml"

# # Deploy OAuthClient
# if [[ -f "$OAUTHCLIENT_FILE" ]]; then
#   echo -e "${BLUE}Deploying OAuthClient from $OAUTHCLIENT_FILE${NC}"
  
#   # Create a temporary file with CLUSTER_URL substituted
#   temp_oauthclient=$(mktemp)
#   sed "s/\${CLUSTER_URL}/$CLUSTER_URL/g" "$OAUTHCLIENT_FILE" > "$temp_oauthclient"
  
#   $KUBECTL_CMD apply -f "$temp_oauthclient"
#   rm -f "$temp_oauthclient"
  
#   echo -e "${GREEN}OAuthClient deployed with cluster URL: $CLUSTER_URL${NC}"
# else
#   echo -e "${YELLOW}Warning: OAuthClient file not found at $OAUTHCLIENT_FILE${NC}"
# fi

# # Create ConfigMap with substituted values
# if [[ -f "$VALUES_FILE" ]]; then
#   echo -e "${BLUE}Creating ConfigMap with substituted values from $VALUES_FILE${NC}"
  
#   # Create a temporary file with CLUSTER_URL substituted
#   temp_values=$(mktemp)
#   sed "s/\${CLUSTER_URL}/$CLUSTER_URL/g" "$VALUES_FILE" > "$temp_values"
  
#   $KUBECTL_CMD create configmap litemaas-values \
#     --from-file=values.yaml="$temp_values" \
#     -n litemaas --dry-run=client -o yaml | $KUBECTL_CMD apply -f -
  
#   rm -f "$temp_values"
  
#   echo -e "${GREEN}ConfigMap 'litemaas-values' created in namespace 'litemaas' with substituted cluster URL: $CLUSTER_URL${NC}"
# else
#   echo -e "${YELLOW}Warning: Values file not found at $VALUES_FILE${NC}"
# fi

# # Run users.sh script
# if [[ -f "$USERS_SCRIPT" ]]; then
#   echo -e "${BLUE}Running users.sh from $USERS_SCRIPT${NC}"
#   bash "$USERS_SCRIPT"
#   echo -e "${GREEN}Users script executed.${NC}"
# else
#   echo -e "${YELLOW}Warning: users.sh script not found at $USERS_SCRIPT${NC}"
# fi

# echo "**********************"


echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deploying root Argo CD application ===${NC}"
echo "**********************"
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
