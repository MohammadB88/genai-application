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

  # Only substitute known variables — prevents envsubst from eating
  # Prometheus label selectors like {namespace="gpu-operator"}
  VARS=$(env | grep -E '^(ALERT_|DATASOURCE_|GRAFANA_|THRESHOLD_|ORGID)' \
    | cut -d= -f1 | sed 's/^/$/' | tr '\n' ',')

  RENDERED=$(envsubst "$VARS" < templates/alert-rule.json.tmpl)

  echo "**********************************"
  echo "Rendered JSON for: $ALERT_TITLE"
  echo "**********************************"
  echo "$RENDERED"
  echo "**********************************"

  # Validate JSON before sending
  echo "$RENDERED" | python3 -m json.tool > /dev/null || {
    echo "❌ Invalid JSON for '$ALERT_TITLE' — aborting"
    exit 1
  }

  echo "$RENDERED" | curl -X POST "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
    -d @-

  echo "✅ Deployed: $ALERT_TITLE"
}

if [[ "$RULE_ENV" == "--all" ]]; then
  for env_file in rules/*.env; do
    deploy "$env_file"
  done
else
  deploy "$RULE_ENV"
fi