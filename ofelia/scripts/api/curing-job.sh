#!/bin/sh
# Usage: curing-job.sh <job>  -- POSTs to $CURING_SERVER/api/jobs/<job>
# Runs one background job of the Curing Dashboard, which is hosted on Vercel
# (so this is a call over the public internet, not the infra Docker network):
#   sync   Google Sheets -> dashboard, then the rules, which queue the WhatsApp alerts
#   w3     "Curing Log not updated" watch
#   w7     daily MD summary
#
# Fails the job on: missing env, bad API key, non-200, or success=false.
#
# Env (set in the ofelia container, not committed):
#   CURING_SERVER    base URL of the app, e.g. https://curing-dashboard.vercel.app (no trailing slash)
#   CURING_API_KEY   must match CURING_API_KEY on the app (Vercel env vars)
set -eu

: "${1:?usage: curing-job.sh <job>}"
: "${CURING_SERVER:?CURING_SERVER is not set in the ofelia container}"
: "${CURING_API_KEY:?CURING_API_KEY is not set in the ofelia container}"

url="${CURING_SERVER}/api/jobs/$1"

# Credential probe: GET authenticates but does NOT run the job. 60 s, not 30:
# the first call after idle waits for the Vercel function and Neon to wake up.
probe=$(wget -qO- -T 60 --header "x-api-key: ${CURING_API_KEY}" "$url" || true)
case "$probe" in
  *'"auth":"ok"'*) : ;;
  *)
    echo "ERROR: credential probe failed for $url"
    echo "$probe"
    exit 1
    ;;
esac

# -T 300 matches the route's maxDuration (a sync takes about 50 s).
echo "POST $url"
body=$(wget -qO- -T 300 \
  --header 'Content-Type: application/json' \
  --header "x-api-key: ${CURING_API_KEY}" \
  --post-data '{}' \
  "$url")

echo "$body"

if echo "$body" | grep -q '"success": *false'; then
  echo "ERROR: curing job $1 reported success=false"
  exit 1
fi

echo "OK: curing job $1 completed"
