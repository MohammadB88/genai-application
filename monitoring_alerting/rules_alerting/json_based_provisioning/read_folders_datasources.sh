#!/bin/bash
set -e

# Prompt for Grafana connection details
read -rp "Grafana URL (e.g. https://grafana.example.com): " GRAFANA_URL
read -rsp "Grafana API Token: " GRAFANA_TOKEN
echo

AUTH_HEADER="Authorization: Bearer ${GRAFANA_TOKEN}"

# **********************
# Folders
# **********************
echo ""
echo "Available Folders:"
echo "**********************"

curl -sf -X GET "${GRAFANA_URL}/api/folders" \
  -H "Content-Type: application/json" \
  -H "${AUTH_HEADER}" | python3 -c "
import sys, json
folders = json.load(sys.stdin)
if not folders:
    print('  (no folders found)')
else:
    print(f'  {\"Title\":<40} UID')
    print(f'  {\"-\"*40} {\"-\"*20}')
    for f in folders:
        print(f'  {f[\"title\"]:<40} {f[\"uid\"]}')
"

# **********************
# Datasources
# **********************
echo ""
echo "Available Datasources:"
echo "**********************"

curl -sf -X GET "${GRAFANA_URL}/api/datasources" \
  -H "Content-Type: application/json" \
  -H "${AUTH_HEADER}" | python3 -c "
import sys, json
datasources = json.load(sys.stdin)
if not datasources:
    print('  (no datasources found)')
else:
    print(f'  {\"Name\":<30} {\"Type\":<20} UID')
    print(f'  {\"-\"*30} {\"-\"*20} {\"-\"*20}')
    for d in datasources:
        print(f'  {d[\"name\"]:<30} {d[\"type\"]:<20} {d[\"uid\"]}')
"

echo ""