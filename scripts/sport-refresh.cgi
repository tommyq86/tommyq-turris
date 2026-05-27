#!/bin/sh
echo "Content-Type: application/json"
echo ""
/root/scripts/generate-sport-maps.sh >/dev/null 2>&1 &
echo '{"status":"started"}'
