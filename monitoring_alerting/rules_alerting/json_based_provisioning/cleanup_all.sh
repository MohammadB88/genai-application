#!/bin/bash
set -euo pipefail

# Use env vars if set, otherwise prompt interactively
if [[ -z "${GRAFANA_URL:-}" ]]; then
  read -rp "Grafana URL (e.g. https://grafana.example.com): " GRAFANA_URL
else
  echo "Using GRAFANA_URL from environment: $GRAFANA_URL"
fi

if [[ -z "${GRAFANA_TOKEN:-}" ]]; then
  read -rsp "Grafana API Token: " GRAFANA_TOKEN
  echo
else
  echo "Using GRAFANA_TOKEN from environment."
fi

AUTH_HEADER="Authorization: Bearer ${GRAFANA_TOKEN}"

# Load provisioning defaults — GRAFANA_FOLDER_UID scopes deletion to rules
# provisioned by this repo instead of every rule in the Grafana instance.
if [[ -f config/global.env ]]; then
  source config/global.env
fi

if [[ -z "${GRAFANA_FOLDER_UID:-}" || "${GRAFANA_FOLDER_UID}" == "your-folder-uid" ]]; then
  echo "[ERROR] GRAFANA_FOLDER_UID is not set in config/global.env — refusing to run"
  echo "        an unscoped cleanup against a shared Grafana instance."
  exit 1
fi

# Collect alert group names from topic-specific config files.
# Groups are not separate Grafana resources; they are metadata on alert rules.
ALERT_GROUPS=()
for cfg in config/*.env; do
  [[ "$cfg" == "config/global.env" ]] && continue
  if group=$(grep -E '^ALERT_GROUP=' "$cfg" | tail -n1 | cut -d= -f2- | sed 's/^"//;s/"$//'); then
    if [[ -n "$group" ]]; then
      ALERT_GROUPS+=("$group")
    fi
  fi
done
if [[ ${#ALERT_GROUPS[@]} -gt 0 ]]; then
  IFS=$'\n' ALERT_GROUPS=( $(printf '%s\n' "${ALERT_GROUPS[@]}" | sort -u) )
  unset IFS
fi

# **********************************
# Options
# **********************************
DELETE_RULES=true
DELETE_POLICY=false
ASSUME_YES=false

usage() {
  echo ""
  echo "Usage: $0 [--rules] [--policy] [--all] [--yes]"
  echo ""
  echo "  --rules    Delete alert rules in GRAFANA_FOLDER_UID (config/global.env)"
  echo "  --policy   Reset notification policy to default"
  echo "  --all      Delete rules and reset policy"
  echo "  --yes      Do not prompt for confirmation per rule (non-interactive)"
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
      --yes)    ASSUME_YES=true ;;
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
  if [[ ${#ALERT_GROUPS[@]} -gt 0 ]]; then
    echo "Detected alert groups from config files: ${ALERT_GROUPS[*]}"
    echo "Deleting alert rules removes these groups automatically because rule groups are metadata on alerts."
  fi
  echo "Fetching alert rules in folder ${GRAFANA_FOLDER_UID}..."

  RULES=$(curl -sf -X GET "${GRAFANA_URL}/api/v1/provisioning/alert-rules" \
    -H "Content-Type: application/json" \
    -H "${AUTH_HEADER}") || {
    echo "[ERROR] Failed to fetch alert rules from ${GRAFANA_URL} — check GRAFANA_URL/GRAFANA_TOKEN"
    exit 1
  }

  # Scope to rules in our folder so this never touches rules owned by other teams.
  UIDS=$(echo "$RULES" | jq -r --arg f "$GRAFANA_FOLDER_UID" \
    '.[] | select(.folderUID == $f) | "\(.uid)\t\(.title)"')

  if [[ -z "$UIDS" ]]; then
    echo "No alert rules found in folder ${GRAFANA_FOLDER_UID}."
  else
    echo ""
    echo "The following rules were found in folder ${GRAFANA_FOLDER_UID}:"
    echo "----------------------------------------------"
    while IFS=$'\t' read -r uid title; do
      echo "  [$uid] $title"
    # Feed the contents of the UIDS variable into the loop via a here-string,
    # allowing the while/read loop to process each line from UIDS before ending.
    done <<< "$UIDS"
    echo "----------------------------------------------"
    echo ""

    while IFS=$'\t' read -r uid title; do
      if [[ "$ASSUME_YES" == true ]]; then
        CONFIRM="yes"
      else
        read -rp "Delete rule '$title' [$uid]? (yes/no): " CONFIRM < /dev/tty
      fi
      if [[ "${CONFIRM,,}" =~ ^(yes|y)$ ]]; then
        if curl -sf -X DELETE "${GRAFANA_URL}/api/v1/provisioning/alert-rules/${uid}" \
          -H "${AUTH_HEADER}"; then
          echo "Deleted: $title [$uid]"
        else
          echo "[ERROR] Failed to delete: $title [$uid]"
        fi
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

  if curl -sf -X DELETE "${GRAFANA_URL}/api/v1/provisioning/policies" \
    -H "${AUTH_HEADER}"; then
    echo "Notification policy reset to default."
  else
    echo "[ERROR] Failed to reset notification policy"
    exit 1
  fi
fi

echo ""
echo "Cleanup complete."
