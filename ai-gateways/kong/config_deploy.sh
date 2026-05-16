#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kong"
CONFIGMAP="kong-deck-config"
JOB_FILE="config_job.yaml"
FILE="test_service_route.yaml"
JOB_NAME=$(grep "name:" "$JOB_FILE" | head -1 | awk '{print $2}')

echo "======================================"
echo " 1. Create/Update ConfigMap"
echo "======================================"

oc create configmap "$CONFIGMAP" \
  --from-file="$FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | oc apply -f -

echo ""
echo "======================================"
echo " 2. CURRENT SERVICES"
echo "======================================"

oc exec deploy/kong-kong -- \
  curl -s http://kong-kong-admin:8001/services | jq '.data[].name' || true

echo ""
echo "======================================"
echo " 3. CURRENT ROUTES"
echo "======================================"

oc exec deploy/kong-kong -- \
  curl -s http://kong-kong-admin:8001/routes | jq '.data[].name' || true

echo ""
echo "======================================"
echo " 4. APPLY NEW RULE?"
echo "======================================"
read -p "Do you want to apply the new Kong config via decK Job? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" ]]; then
  echo "Aborted. No changes applied."
  exit 0
fi

echo ""
echo "======================================"
echo " 5. RESTART JOB (force re-run)"
echo "======================================"

oc delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true

oc apply -f "$JOB_FILE" -n "$NAMESPACE"

echo ""
echo "Waiting for job to complete..."
oc wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout=180s || true

echo ""
echo "======================================"
echo " 6. JOB LOGS"
echo "======================================"

oc logs job/"$JOB_NAME" -n "$NAMESPACE"

echo ""
echo "======================================"
echo " 7. POST-DEPLOY SERVICES"
echo "======================================"

oc exec deploy/kong-kong -- \
  curl -s http://kong-kong-admin:8001/services | jq '.data[].name' || true

echo ""
echo "======================================"
echo " 8. POST-DEPLOY ROUTES"
echo "======================================"

oc exec deploy/kong-kong -- \
  curl -s http://kong-kong-admin:8001/routes | jq '.data[].name' || true

echo ""
echo "DONE"