#!/bin/sh
# Usage: sfg-sync.sh  -- POSTs to $SFG_APP_SERVER/api/scheduler/sfg-sync
# Runs the full SFG pipeline: fetch every endpoint -> CSV -> mirror into Postgres schema sfg.
#
# Env (set in the ofelia container, not committed):
#   SFG_APP_SERVER    base URL of the api, e.g. http://sfg-automation:8090
#   SFG_SYNC_API_KEY  must match SFG_SYNC_API_KEY on the app
set -eu

: "${SFG_APP_SERVER:?SFG_APP_SERVER is not set in the ofelia container}"
: "${SFG_SYNC_API_KEY:?SFG_SYNC_API_KEY is not set in the ofelia container}"

url="${SFG_APP_SERVER}/api/scheduler/sfg-sync"

# Cheap credential probe first: GET authenticates but does NOT run the job.
probe=$(wget -qO- -T 30 --header "x-api-key: ${SFG_SYNC_API_KEY}" "${url}" || true)
case "$probe" in
  *'"auth":"ok"'*) : ;;
  *)
    echo "ERROR: credential probe failed for $url"
    echo "$probe"
    exit 1
    ;;
esac

echo "POST $url (key length ${#SFG_SYNC_API_KEY})"
# The full pipeline (pull + DB mirror of ~444MB) can take minutes; allow 30 min.
body=$(wget -qO- -T 1800 \
  --header 'Content-Type: application/json' \
  --header "x-api-key: ${SFG_SYNC_API_KEY}" \
  --post-data '{}' \
  "$url")

echo "$body"

if echo "$body" | grep -q '"success": *false'; then
  echo "ERROR: sfg-sync reported success=false"
  exit 1
fi

echo "OK: sfg-sync completed"
