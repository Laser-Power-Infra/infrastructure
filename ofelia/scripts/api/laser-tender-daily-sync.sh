#!/bin/sh
# Usage: laser-tender-daily-sync.sh  -- POSTs to $LASER_TENDER_SERVER/api/scheduler/daily-refresh-allocate
# Runs what the laser-tender dashboard's "Refresh Data" and "Allocate tender"
# buttons do, in that order: Smartsheet -> SmartsheetTender refresh, then
# allocation of unallocated tenders. If the refresh does not complete the app
# skips allocation and returns success:false.
#
# Allocation only fills rows that have no allocatedTo, so re-running is safe.
#
# Env (set in the ofelia container, not committed):
#   LASER_TENDER_SERVER    base URL of the app, e.g. http://laser-tender:4173
#   LASER_TENDER_API_KEY   must match WORKER_API_KEY on the app
set -eu

: "${LASER_TENDER_SERVER:?LASER_TENDER_SERVER is not set in the ofelia container}"
: "${LASER_TENDER_API_KEY:?LASER_TENDER_API_KEY is not set in the ofelia container}"

url="${LASER_TENDER_SERVER}/api/scheduler/daily-refresh-allocate"

# Cheap credential probe first: GET authenticates but does NOT run the job.
probe=$(wget -qO- -T 30 --header "x-api-key: ${LASER_TENDER_API_KEY}" "${url}" || true)
case "$probe" in
  *'"auth":"ok"'*) : ;;
  *)
    echo "ERROR: credential probe failed for $url"
    echo "$probe"
    exit 1
    ;;
esac

echo "POST $url (key length ${#LASER_TENDER_API_KEY})"
body=$(wget -qO- -T 900 \
  --header 'Content-Type: application/json' \
  --header "x-api-key: ${LASER_TENDER_API_KEY}" \
  --post-data '{}' \
  "$url")

echo "$body"

# The route returns 200 even when the refresh or allocation fails, so check the body.
if echo "$body" | grep -q '"success": *false'; then
  echo "ERROR: laser-tender daily refresh + allocate reported success=false"
  exit 1
fi

echo "OK: laser-tender daily refresh + allocate completed"
