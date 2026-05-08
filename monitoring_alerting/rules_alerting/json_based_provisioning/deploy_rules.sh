#!/bin/bash
set -e

# Prompt for Grafana connection details
read -rp "Grafana URL (e.g. https://grafana.example.com): " GRAFANA_URL
read -rsp "Grafana API Token: " GRAFANA_TOKEN
echo

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

  envsubst < templates/alert-rule.json.tmpl | \
    curl -sf -X POST "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
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
