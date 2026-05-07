#!/usr/bin/env bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITORING_DIR="$SCRIPT_DIR"
GRAFANA_NAMESPACE="grafana"
GRAFANA_RELEASE="grafana"
USER_WORKLOAD_NAMESPACE="openshift-user-workload-monitoring"

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

echo -e "${BLUE}=== Welcome to Monitoring Deployment Helper ===${NC}"
echo "This script will deploy user workload monitoring and optionally Grafana for OpenShift."

echo " "
echo "**********************"
echo "**********************"

# Step 1: Enable user workload monitoring
echo -e "${BLUE}=== Enabling User Workload Monitoring ===${NC}"
echo "**********************"

if $KUBECTL_CMD -n openshift-monitoring get configmap cluster-monitoring-config >/dev/null 2>&1; then
  echo -e "${YELLOW}ConfigMap 'cluster-monitoring-config' already exists. Patching it...${NC}"
  $KUBECTL_CMD -n openshift-monitoring patch configmap cluster-monitoring-config \
    --type=merge \
    -p='{"data":{"config.yaml":"enableUserWorkload: true\n"}}' || true
else
  echo -e "${BLUE}Creating ConfigMap 'cluster-monitoring-config'...${NC}"
  $KUBECTL_CMD -n openshift-monitoring create configmap cluster-monitoring-config \
    --from-literal=config.yaml='enableUserWorkload: true'
fi

echo -e "${GREEN}User workload monitoring configuration applied.${NC}"

echo " "
echo "**********************"
echo -e "${BLUE}=== Waiting for user workload monitoring pods to be ready ===${NC}"
echo "Namespace: $USER_WORKLOAD_NAMESPACE"
echo "**********************"

wait_for_user_workload_pods() {
  local max_attempts=60
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    local ready_count=$($KUBECTL_CMD get pods -n "$USER_WORKLOAD_NAMESPACE" \
      -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' \
      2>/dev/null | grep -c "True" || 0)

    if [[ $ready_count -gt 0 ]]; then
      echo -e "${GREEN}✓ Found $ready_count Ready pod(s) in namespace $USER_WORKLOAD_NAMESPACE${NC}"
      return 0
    fi

    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 5))
    echo -e "${YELLOW}[$attempt/$max_attempts] No Ready pods yet; waiting... | $remaining_time${NC}"
    sleep 5
    ((attempt++))
  done
  
  echo -e "${YELLOW}Timeout waiting for user workload monitoring pods. Continuing anyway...${NC}"
  return 1
}

wait_for_user_workload_pods || true

# Step 2: Ask about Grafana deployment
echo " "
echo "**********************"
read -r -p "Deploy Grafana for monitoring dashboards? [y/N]: " DEPLOY_GRAFANA
if ! [[ "$DEPLOY_GRAFANA" =~ ^([yY]|[yY][eE][sS])$ ]]; then
  echo -e "${YELLOW}Skipping Grafana deployment.${NC}"
  echo " "
  echo "**********************"
  echo -e "${GREEN}=== User Workload Monitoring Enabled ===${NC}"
  echo "**********************"
  echo -e "${BLUE}You can now deploy ServiceMonitor resources in user namespaces.${NC}"
  echo "**********************"
  exit 0
fi

# Step 3: Deploy Grafana
echo " "
echo "**********************"
echo "**********************"
echo -e "${BLUE}=== Deploying Grafana ===${NC}"
echo "**********************"
echo "**********************"

# Ensure project exists
echo -e "${BLUE}Ensuring project '$GRAFANA_NAMESPACE' exists...${NC}"
if $KUBECTL_CMD get project "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${GREEN}Project '$GRAFANA_NAMESPACE' already exists.${NC}"
else
  echo -e "${BLUE}Creating project '$GRAFANA_NAMESPACE'...${NC}"
  $KUBECTL_CMD new-project "$GRAFANA_NAMESPACE"
  echo -e "${GREEN}Project '$GRAFANA_NAMESPACE' created.${NC}"
fi

# Add Helm repo
echo " "
echo -e "${BLUE}Adding Grafana Helm chart repository...${NC}"
helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
helm repo update > /dev/null 2>&1

# Check if Helm release exists
if helm status "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
  echo -e "${YELLOW}Helm release '$GRAFANA_RELEASE' already exists. Skipping installation.${NC}"
else
  echo -e "${BLUE}Installing Helm release '$GRAFANA_RELEASE'...${NC}"
  helm install "$GRAFANA_RELEASE" grafana/grafana \
    --set securityContext.runAsUser=null,securityContext.fsGroup=null \
    -n "$GRAFANA_NAMESPACE" > /dev/null
  echo -e "${GREEN}Grafana Helm release installed.${NC}"
fi

# Grant permissions
echo " "
echo -e "${BLUE}Granting cluster-monitoring-view role to grafana service account...${NC}"
$KUBECTL_CMD adm policy add-cluster-role-to-user cluster-monitoring-view -z "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" 2>/dev/null || true

# Wait for Grafana deployment
echo " "
echo "**********************"
echo -e "${BLUE}=== Waiting for Grafana to be ready (up to 3 minutes) ===${NC}"
echo "**********************"

wait_for_grafana_ready() {
  local max_attempts=36
  local attempt=1
  
  while [[ $attempt -le $max_attempts ]]; do
    local ready_replicas=$($KUBECTL_CMD get deployment "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" \
      -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas=$($KUBECTL_CMD get deployment "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    
    if [[ "$ready_replicas" == "$desired_replicas" ]] && [[ "$desired_replicas" != "0" ]]; then
      echo -e "${GREEN}✓ Grafana is READY!${NC}"
      echo -e "${GREEN}  Ready Replicas: $ready_replicas/$desired_replicas${NC}"
      return 0
    fi
    
    printf -v remaining_time '%d seconds remaining\n' $((($max_attempts - $attempt) * 5))
    echo -e "${YELLOW}[$attempt/$max_attempts] Ready: $ready_replicas/$desired_replicas | $remaining_time${NC}"
    
    sleep 5
    ((attempt++))
  done
  
  echo -e "${RED}✗ Grafana did not reach ready state within 3 minutes${NC}"
  return 1
}

wait_for_grafana_ready

# Get Grafana credentials
echo " "
echo -e "${BLUE}=== Retrieving Grafana credentials ===${NC}"

GRAFANA_SECRET_NAME="$GRAFANA_RELEASE"
GRAFANA_USER_B64=$($KUBECTL_CMD get secret "$GRAFANA_SECRET_NAME" -n "$GRAFANA_NAMESPACE" \
  -o jsonpath='{.data.admin-user}' 2>/dev/null || echo "")
GRAFANA_PASS_B64=$($KUBECTL_CMD get secret "$GRAFANA_SECRET_NAME" -n "$GRAFANA_NAMESPACE" \
  -o jsonpath='{.data.admin-password}' 2>/dev/null || echo "")

if [[ -n "$GRAFANA_USER_B64" ]] && [[ -n "$GRAFANA_PASS_B64" ]]; then
  GRAFANA_USER=$(echo "$GRAFANA_USER_B64" | base64 -d)
  GRAFANA_PASS=$(echo "$GRAFANA_PASS_B64" | base64 -d)
else
  GRAFANA_USER="admin"
  GRAFANA_PASS="(check secret: oc get secret $GRAFANA_SECRET_NAME -n $GRAFANA_NAMESPACE)"
fi

# Deploy route if oc is available
if [[ "$KUBECTL_CMD" == "oc" ]]; then
  echo -e "${BLUE}Creating Route for Grafana...${NC}"
  if [[ -f "$MONITORING_DIR/route.yaml" ]]; then
    $KUBECTL_CMD apply -f "$MONITORING_DIR/route.yaml"
    echo -e "${GREEN}Route applied from $MONITORING_DIR/route.yaml${NC}"
  else
    echo -e "${YELLOW}Route manifest not found. Creating default route...${NC}"
    $KUBECTL_CMD expose svc/"$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" --name="$GRAFANA_RELEASE" 2>/dev/null || true
  fi
fi

# Create service account token
echo " "
echo -e "${BLUE}=== Creating long-lived token for Grafana service account ===${NC}"
GRAFANA_TOKEN=$($KUBECTL_CMD create token "$GRAFANA_RELEASE" --duration=200h -n "$GRAFANA_NAMESPACE" 2>/dev/null || echo "")

echo " "
echo "**********************"
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo "**********************"
echo -e "Namespace: ${BLUE}${GRAFANA_NAMESPACE}${NC}"
echo -e "Release: ${BLUE}${GRAFANA_RELEASE}${NC}"

echo " "
echo -e "${BLUE}=== Grafana Access ===${NC}"
echo -e "Username: ${BLUE}${GRAFANA_USER}${NC}"
echo -e "Password: ${BLUE}${GRAFANA_PASS}${NC}"

if [[ "$KUBECTL_CMD" == "oc" ]]; then
  if $KUBECTL_CMD get route "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" >/dev/null 2>&1; then
    GRAFANA_HOST=$($KUBECTL_CMD get route "$GRAFANA_RELEASE" -n "$GRAFANA_NAMESPACE" -o jsonpath='{.spec.host}')
    echo -e "Web UI: ${BLUE}https://${GRAFANA_HOST}${NC}"
  else
    echo -e "Route: ${YELLOW}Not yet available. Check with:${NC}"
    echo -e "  $KUBECTL_CMD get route -n $GRAFANA_NAMESPACE"
  fi
fi

echo " "
echo -e "${BLUE}=== Service Account Token ===${NC}"
if [[ -n "$GRAFANA_TOKEN" ]]; then
  echo -e "Token (first 50 chars): ${BLUE}${GRAFANA_TOKEN:0:50}...${NC}"
  echo -e "Full token available via: ${BLUE}oc get secret -n $GRAFANA_NAMESPACE | grep token${NC}"
else
  echo -e "${YELLOW}Token creation skipped or failed.${NC}"
fi

echo " "
echo -e "${BLUE}=== Resources ===${NC}"
$KUBECTL_CMD get all -n "$GRAFANA_NAMESPACE" || true

echo " "
echo "**********************"
echo -e "${GREEN}=== Monitoring Deployment finished ===${NC}"
echo "**********************"
