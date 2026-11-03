#!/bin/sh
# Usage: gmd-bg-mail-trigger.sh /api/<route>  -- POSTs to $GMD_APP_SERVER with the API key
set -eu
echo "POST ${GMD_APP_SERVER}$1"
wget -qO- -T 360 --post-data '' \
  --header "x-api-key: ${GMD_SYNC_API_KEY} \
  "${GMD_APP_SERVER}$1"
echo
