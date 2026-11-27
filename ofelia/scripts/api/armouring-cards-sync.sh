#!/bin/sh
# Usage: armouring-cards-sync.sh  -- POSTs to $ARMOURING_APP_SERVER/api/jobs/cards
# Syncs the KGP source sheets into the armouring dashboard's database and builds
# today's four cards (Machine Production, Labour Allocation, FG Drum Requirement,
# Drum Assembly). A new card revision is stored only when the cards changed, so
# re-running is a no-op ("status":"unchanged").
#
# The route answers non-2xx when the sync fails (a sheet cannot be read, the SFG
# pull failed or is over 18 h old); wget then exits non-zero and the job fails.
#
# Env (set in the ofelia container, not committed):
#   ARMOURING_APP_SERVER    base URL of the armouring dashboard, e.g. https://armouring.example.com
#   ARMOURING_JOB_SECRET    must match JOB_SECRET on the app
set -eu

: "${ARMOURING_APP_SERVER:?ARMOURING_APP_SERVER is not set in the ofelia container}"
: "${ARMOURING_JOB_SECRET:?ARMOURING_JOB_SECRET is not set in the ofelia container}"

url="${ARMOURING_APP_SERVER}/api/jobs/cards"

# Cheap credential probe first: GET authenticates but does NOT run the job.
probe=$(wget -qO- -T 30 --header "Authorization: Bearer ${ARMOURING_JOB_SECRET}" "${url}" || true)
case "$probe" in
  *'"auth":"ok"'*) : ;;
  *)
    echo "ERROR: credential probe failed for $url"
    echo "$probe"
    exit 1
    ;;
esac

echo "POST $url (secret length ${#ARMOURING_JOB_SECRET})"
body=$(wget -qO- -T 300 \
  --header 'Content-Type: application/json' \
  --header "Authorization: Bearer ${ARMOURING_JOB_SECRET}" \
  --post-data '{}' \
  "$url") || {
  echo "ERROR: armouring cards sync failed (non-2xx from $url; the app log has the reason)"
  exit 1
}

echo "$body"

if echo "$body" | grep -q '"ok": *false'; then
  echo "ERROR: armouring cards sync reported ok=false"
  exit 1
fi

echo "OK: armouring cards sync completed"
