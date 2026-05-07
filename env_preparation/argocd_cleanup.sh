#!/usr/bin/env bash

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GITOPS_DIR="$SCRIPT_DIR/../gitops"
APP_MANIFESTS=(
  "$GITOPS_DIR/root-application.yaml"
  "$GITOPS_DIR/anythingllm.yaml"
  "$GITOPS_DIR/minio.yaml"
  "$GITOPS_DIR/llm_llama.yaml"
  "$GITOPS_DIR/llm_vllm_granite.yaml"
)
NAMESPACES=(
  "web-interface"
  "s3-storage"
  "llms"
  "llms-vllm"
)

if command -v oc >/dev/null 2>&1; then
  KUBECTL_CMD="oc"
elif command -v kubectl >/dev/null 2>&1; then
  KUBECTL_CMD="kubectl"
else
  echo -e "${RED}Error: neither oc nor kubectl is installed or available in PATH.${NC}"
  exit 1
fi

echo -e "${BLUE}=== Cleaning up Argo CD root deployment ===${NC}"
for manifest in "${APP_MANIFESTS[@]}"; do
  if [[ -f "$manifest" ]]; then
    echo -e "${YELLOW}Deleting application manifest: $manifest${NC}"
    $KUBECTL_CMD delete -f "$manifest" --ignore-not-found
  else
    echo -e "${YELLOW}Skipping missing manifest: $manifest${NC}"
  fi
done

echo "**********************"
echo -e "${BLUE}=== Cleaning up all resources in namespaces ===${NC}"
echo "**********************"
for ns in "${NAMESPACES[@]}"; do
  if $KUBECTL_CMD get namespace "$ns" >/dev/null 2>&1; then
    echo -e "${YELLOW}Deleting all resources in namespace: $ns${NC}"
    
    # Delete standard resources (pods, deployments, services, etc.)
    echo -e "${BLUE}  Deleting deployments...${NC}"
    $KUBECTL_CMD delete deployment --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting statefulsets...${NC}"
    $KUBECTL_CMD delete statefulset --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting daemonsets...${NC}"
    $KUBECTL_CMD delete daemonset --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting services...${NC}"
    $KUBECTL_CMD delete service --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting routes...${NC}"
    $KUBECTL_CMD delete route --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting PersistentVolumeClaims...${NC}"
    $KUBECTL_CMD delete pvc --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting ConfigMaps...${NC}"
    $KUBECTL_CMD delete configmap --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${BLUE}  Deleting Secrets...${NC}"
    $KUBECTL_CMD delete secret --all -n "$ns" --ignore-not-found 2>/dev/null || true
    
    echo -e "${GREEN}✓ All resources cleaned from namespace: $ns${NC}"
  else
    echo -e "${YELLOW}Namespace does not exist: $ns (skipping)${NC}"
  fi
done

echo "**********************"
echo -e "${BLUE}=== Deleting namespaces ===${NC}"
echo "**********************"
for ns in "${NAMESPACES[@]}"; do
  echo -e "${YELLOW}Deleting namespace: $ns${NC}"
  $KUBECTL_CMD delete namespace "$ns" --ignore-not-found 2>/dev/null || true
done

echo -e "${GREEN}=== Cleanup complete ===${NC}"
