#!/bin/sh
# Usage: docket-followup-sync.sh  -- POSTs to $GMD_APP_SERVER/api/scheduler/docket-followup
# Flags new GMD docket-request mails (GMD CLIENTS label, sent to Laser Entry,
# no real docket number yet) as pendingDocket = true so they appear on the
# Pending Dockets tab and feed docket-creation-sync. Before this job the scan
# only ran while someone had the Docket Follow-up page open.
#
# Incremental: rows already pending plus mail from the last 48h. Concurrent
# calls share one scan inside the app, so a slow run cannot stack up.
#
# Env (set in the ofelia container, not committed):
#   GMD_APP_SERVER      base URL of this app, e.g. http://gmd-quotation-process:4570
#   GMD_SYNC_API_KEY    must match GMD_SYNC_API_KEY on the app
set -eu

: "${GMD_APP_SERVER:?GMD_APP_SERVER is not set in the ofelia container}"
: "${GMD_SYNC_API_KEY:?GMD_SYNC_API_KEY is not set in the ofelia container}"

url="${GMD_APP_SERVER}/api/scheduler/docket-followup"

# No GET probe here: GET on this route runs the sync instead of only checking
# the key, so POST is the single call.
echo "POST $url (key length ${#GMD_SYNC_API_KEY})"
body=$(wget -qO- -T 900 \
  --header 'Content-Type: application/json' \
  --header "x-api-key: ${GMD_SYNC_API_KEY}" \
  --post-data '{}' \
  "$url")

echo "$body"

if echo "$body" | grep -q '"success": *false'; then
  echo "ERROR: docket-followup sync reported success=false"
  exit 1
fi

echo "OK: docket-followup sync completed"
