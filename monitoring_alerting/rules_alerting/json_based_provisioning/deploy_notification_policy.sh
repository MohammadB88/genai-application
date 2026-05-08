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

# **********************************
# Notification Policy Tree
#
# Simple routing by severity — all teams go to TEST.
# The "team" label is carried on each alert for future use.
#
# To route per team later, add team matchers as parent routes
# and assign dedicated contact points per team.
# **********************************

POLICY=$(cat <<'JSON'
{
  "receiver": "TEST",
  "group_by": ["grafana_folder", "alertname", "team"],
  "routes": [
    {
      "receiver": "TEST",
      "matchers": ["severity = critical"],
      "group_wait": "30s",
      "group_interval": "5m",
      "repeat_interval": "1h"
    },
    {
      "receiver": "TEST",
      "matchers": ["severity = warning"],
      "group_wait": "1m",
      "group_interval": "10m",
      "repeat_interval": "6h"
    }
  ]
}
JSON
)

echo ""
echo "**********************************"
echo "Notification Policy to be deployed:"
echo "**********************************"
echo "$POLICY"
echo "**********************************"

# Validate JSON before sending
echo "$POLICY" | python3 -m json.tool > /dev/null || {
  echo "Invalid JSON — aborting"
  exit 1
}

# Deploy — note: this is a PUT (replaces the entire policy tree)
curl -X PUT "${GRAFANA_URL}/api/v1/provisioning/policies" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GRAFANA_TOKEN}" \
  -d "$POLICY"

echo ""
echo "Notification policy deployed."