#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="kong"
CONFIGMAP="kong-deck-config"
JOB_FILE="config_job.yaml"
FILE="test_service_route.yaml"

echo "==> 1. Create/Update ConfigMap from file"
oc create configmap "$CONFIGMAP" \
  --from-file="$FILE" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | oc apply -f -

echo "==> 2. Apply Job manifest (idempotent update)"
oc apply -f "$JOB_FILE" -n "$NAMESPACE"

echo "==> 3. Restart Job if it already exists (force re-run)"
JOB_NAME=$(grep "name:" "$JOB_FILE" | head -1 | awk '{print $2}')

if oc get job "$JOB_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "==> Job exists → deleting to force re-run"
  oc delete job "$JOB_NAME" -n "$NAMESPACE"
fi

echo "==> 4. Recreate Job"
oc apply -f "$JOB_FILE" -n "$NAMESPACE"

echo "==> 5. Wait for completion"
oc wait --for=condition=complete job/"$JOB_NAME" -n "$NAMESPACE" --timeout=120s || true

echo "==> 6. Logs"
oc logs job/"$JOB_NAME" -n "$NAMESPACE"