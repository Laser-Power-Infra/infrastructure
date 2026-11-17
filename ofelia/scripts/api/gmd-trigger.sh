#!/bin/sh
# Usage: gmd-trigger.sh /api/<route>  -- POSTs to $GMD_APP_SERVER with the API key
# Used by the daily PBG reminders (/api/scheduler/pbg-reminders) and the
# hourly purchase-orders sync (/api/scheduler/purchase-orders).
#
# Fails the job on: missing env, bad API key, non-200, or success=false.
set -eu

: "${1:?usage: gmd-trigger.sh /api/<route>}"
: "${GMD_APP_SERVER:?GMD_APP_SERVER is not set in the ofelia container}"
: "${GMD_SYNC_API_KEY:?GMD_SYNC_API_KEY is not set in the ofelia container}"

url="${GMD_APP_SERVER}$1"

# Credential probe: GET authenticates but does NOT run the job.
probe=$(wget -qO- -T 30 --header "x-api-key: ${GMD_SYNC_API_KEY}" "$url" || true)
case "$probe" in
  *'"auth":"ok"'*) : ;;
  *)
    echo "ERROR: credential probe failed for $url"
    echo "$probe"
    exit 1
    ;;
esac

echo "POST $url"
body=$(wget -qO- -T 900 \
  --header 'Content-Type: application/json' \
  --header "x-api-key: ${GMD_SYNC_API_KEY}" \
  --post-data '{}' \
  "$url")

echo "$body"

if echo "$body" | grep -q '"success": *false'; then
  echo "ERROR: $1 reported success=false"
  exit 1
fi

echo "OK: $1 completed"
