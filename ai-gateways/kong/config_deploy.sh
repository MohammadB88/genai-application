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
echo "Create persistent debug pod (sleep 10 min)"
echo "======================================"

# oc create pod $DEBUG_POD --image=curlimages/curl:latest -n "$NAMESPACE" --restart=Never -- sleep 600 || true
oc apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: ${DEBUG_POD}
  namespace: ${NAMESPACE}
spec:
  containers:
    - name: curl
      image: curlimages/curl:8.20.0
      command: ["sh", "-c", "sleep 600"]
  restartPolicy: Never
EOF

echo "Waiting for debug pod..."
oc wait --for=condition=Ready pod/$DEBUG_POD -n "$NAMESPACE" --timeout=120s

echo ""
echo "======================================"
echo " 3. CURRENT SERVICES (inside debug pod)"
echo "======================================"

oc exec -n "$NAMESPACE" "$DEBUG_POD" -- \
  curl -s http://kong-kong-admin:8001/services

echo ""
echo "======================================"
echo " 4. CURRENT ROUTES (inside debug pod)"
echo "======================================"

oc exec -n "$NAMESPACE" "$DEBUG_POD" -- \
  curl -s http://kong-kong-admin:8001/routes

echo ""
echo "======================================"
echo " 5. APPLY NEW RULE?"
echo "======================================"

read -p "Do you want to apply the new Kong config via decK Job? (y/n): " CONFIRM

if [[ "$CONFIRM" != "y" ]]; then
  echo "Aborted. No changes applied."
  exit 0
fi

echo ""
echo "======================================"
echo " 6. RESTART JOB"
echo "======================================"

oc delete job "$JOB_NAME" -n "$NAMESPACE" --ignore-not-found=true
oc apply -f "$JOB_FILE" -n "$NAMESPACE"

echo "Waiting for job..."
oc wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout=180s || true

echo ""
echo "======================================"
echo " 7. JOB LOGS"
echo "======================================"

oc logs job/"$JOB_NAME" -n "$NAMESPACE"

echo ""
echo "======================================"
echo " 8. POST-DEPLOY SERVICES"
echo "======================================"

oc exec -n "$NAMESPACE" "$DEBUG_POD" -- \
  curl -s http://kong-kong-admin:8001/services

echo ""
echo "======================================"
echo " 9. POST-DEPLOY ROUTES"
echo "======================================"

oc exec -n "$NAMESPACE" "$DEBUG_POD" -- \
  curl -s http://kong-kong-admin:8001/routes

echo ""
echo "DONE"