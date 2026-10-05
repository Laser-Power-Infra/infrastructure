#!/bin/sh
# Usage: ted-sync.sh /api/<route>  -- POSTs to $LASER_TED_SERVER with the API key
set -eu
echo "POST ${LASER_TED_SERVER}$1"
wget -qO- -T 360 --post-data '' \
  --header "x-api-key: ${LASER_TED_API_KEY}" \
  "${LASER_TED_SERVER}$1"
echo
