#!/bin/sh
echo "Content-Type: application/json"
echo ""
DONE_FLAG="/tmp/sport-refresh-done"
rm -f "$DONE_FLAG"
( /root/scripts/generate-sport-maps.sh >/dev/null 2>&1; touch "$DONE_FLAG" ) &
echo '{"status":"started"}'
