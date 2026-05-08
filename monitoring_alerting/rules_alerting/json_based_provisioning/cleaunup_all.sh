#!/bin/bash
set -euo pipefail

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

AUTH_HEADER="Authorization: Bearer ${GRAFANA_TOKEN}"

# **********************************
# Options
# **********************************
DELETE_RULES=true
DELETE_POLICY=false

usage() {
  echo ""
  echo "Usage: $0 [--rules] [--policy] [--all]"
  echo ""
  echo "  --rules    Delete all alert rules"
  echo "  --policy   Reset notification policy to default"
  echo "  --all      Delete rules and reset policy"
  echo ""
  exit 0
}

if [[ $# -gt 0 ]]; then
  DELETE_RULES=false
  DELETE_POLICY=false
  for arg in "$@"; do
    case $arg in
      --rules)  DELETE_RULES=true ;;
      --policy) DELETE_POLICY=true ;;
      --all)    DELETE_RULES=true; DELETE_POLICY=true ;;
      --help)   usage ;;
      *) echo "Unknown option: $arg"; usage ;;
    esac
  done
fi


# **********************************
# Delete Alert Rules
# **********************************
if [[ "$DELETE_RULES" == true ]]; then
  echo ""
  echo "Fetching all alert rules..."

  RULES=$(curl -X GET "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}")

  UIDS=$(echo "$RULES" | jq -r '.[] | "\(.uid)\t\(.title)"')

  if [[ -z "$UIDS" ]]; then
    echo "No alert rules found."
  else
    echo ""
    echo "The following rules were found:"
    echo "----------------------------------------------"
    while IFS=$'\t' read -r uid title; do
      echo "  [$uid] $title"
    # Feed the contents of the UIDS variable into the loop via a here-string,
    # allowing the while/read loop to process each line from UIDS before ending.
    done <<< "$UIDS"
    echo "----------------------------------------------"
    echo ""

    while IFS=$'\t' read -r uid title; do
      read -rp "Delete rule '$title' [$uid]? (yes/no): " CONFIRM < /dev/tty
      if [[ "${CONFIRM,,}" =~ ^(yes|y)$ ]]; then
        curl -X DELETE "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${uid}" \
          -H "${AUTH_HEADER}"
        echo "Deleted: $title [$uid]"
      else
        echo "Skipped: $title [$uid]"
      fi
    done <<< "$UIDS"

    echo ""
    echo "Alert rules processing complete."
  fi
fi

# **********************************
# Reset Notification Policy
# **********************************
if [[ "$DELETE_POLICY" == true ]]; then
  echo ""
  echo "Resetting notification policy to Grafana default..."

  curl -X DELETE "${GRAFANA_URL}/api/v1/provisioning/policies" \
    -H "${AUTH_HEADER}"

  echo "Notification policy reset to default."
fi

echo ""
echo "Cleanup complete."