#!/bin/sh
# Usage: automation-sync-result.sh [tiger|t247|both]  -- POSTs to $LASER_AUTOMATION_SERVER sync-result
# The route returns 200 even when a source fails, so the body is checked for "success": false.
set -eu
url="${LASER_AUTOMATION_SERVER}/api/v1/sync-result/"
echo "POST $url (type=${1:-both})"
body=$(wget -qO- -T 1800 \
  --header 'Content-Type: application/json' \
  --post-data "{\"type\": \"${1:-both}\"}" \
  "$url")
echo "$body"
if echo "$body" | grep -q '"success": *false'; then
  echo "ERROR: a source returned success=false"
  exit 1
fi
