#!/bin/sh
echo "Content-Type: application/json"
echo ""
# Extract token and id from QUERY_STRING
TOKEN=$(echo "$QUERY_STRING" | sed -n 's/.*token=\([^&]*\).*/\1/p')
ID=$(echo "$QUERY_STRING" | sed -n 's/.*id=\([^&]*\).*/\1/p')
ADMIN_TOKEN=$(grep '^TOKEN=' /root/.tommyq/sport-token.conf | cut -d= -f2)

if [ "$TOKEN" != "$ADMIN_TOKEN" ]; then
    echo '{"error":"unauthorized"}'
    exit 0
fi

if [ "$ID" = "all" ]; then
    rm -f /srv/tommyq/sport/activities/*.html
    /root/scripts/generate-sport-maps.sh >/dev/null 2>&1 &
    echo '{"status":"all deleted"}'
elif [ -n "$ID" ]; then
    rm -f "/srv/tommyq/sport/activities/${ID}.html"
    /root/scripts/generate-sport-maps.sh >/dev/null 2>&1 &
    echo "{\"status\":\"deleted\",\"id\":\"$ID\"}"
else
    echo '{"error":"missing id"}'
fi
