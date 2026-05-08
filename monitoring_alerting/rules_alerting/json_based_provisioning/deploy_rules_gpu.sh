#!/bin/bash
set -e

# Use env vars if set, otherwise prompt interactively
if [[ -z "$GRAFANA_URL" ]]; then
  read -rp "Grafana URL (e.g. https://grafana.example.com): " GRAFANA_URL
else
  echo "Using GRAFANA_URL from environment: $GRAFANA_URL"
fi

if [[ -z "$GRAFANA_TOKEN" ]]; then
  read -rsp "Grafana API Token: " GRAFANA_TOKEN
  echo
else
  echo "Using GRAFANA_TOKEN from environment."
fi

RULE_ENV=$1

if [[ -z "$RULE_ENV" ]]; then
  echo "Usage: $0 <path-to-rule.env>  |  $0 --all"
  exit 1
fi

deploy() {
  local env_file=$1
  set -a
  source config/global.env
  source "$env_file"
  set +a

  # Escape any inner double quotes in ALERT_EXPR so they are valid JSON
  ALERT_EXPR="${ALERT_EXPR//\"/\\\"}"

  # Only substitute known variables — prevents envsubst from eating
  # Prometheus label selectors like {namespace="gpu-operator"}
  VARS=$(env | grep -E '^(ALERT_|DATASOURCE_|GRAFANA_|THRESHOLD_|ORGID)' \
    | cut -d= -f1 | sed 's/^/$/' | tr '\n' ',')

  RENDERED=$(envsubst "$VARS" < templates/alert-rule.json.tmpl)

  echo ""
  echo "****************************"
  echo "Rendered JSON for: $ALERT_TITLE"
  echo "****************************"
  echo "$RENDERED"
  echo "****************************"

  # Validate JSON before sending
  echo "$RENDERED" | python3 -m json.tool > /dev/null || {
    echo "[ERROR] Invalid JSON for '$ALERT_TITLE' — aborting"
    exit 1
  }

   # Check if rule already exists by title using jq
  echo "Checking if rule already exists..."
  EXISTING=$(curl -sf -X GET "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GRAFANA_TOKEN}" | \
    grep -o '"uid":"[^"]*".*"title":"'"$ALERT_TITLE"'"' | \
    grep -o '"uid":"[^"]*"' | cut -d'"' -f4 | head -1) || true
 
  if [[ -n "$EXISTING" ]]; then
    # Update existing rule
    echo "Rule exists with UID: $EXISTING"
    echo "Updating rule..."
    echo "$RENDERED" | curl -sf -X PUT "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${EXISTING}" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
      -d @-
    echo "[OK] Updated: $ALERT_TITLE"
  else
    # Create new rule
    echo "Rule does not exist. Creating..."
    echo "$RENDERED" | curl -sf -X POST "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
      -d @-
    echo "[OK] Created: $ALERT_TITLE"
  fi
}
 
if [[ "$RULE_ENV" == "--all" ]]; then
  for env_file in rules/gpu/*.env; do
    deploy "$env_file"
  done
else
  deploy "$RULE_ENV"
fi