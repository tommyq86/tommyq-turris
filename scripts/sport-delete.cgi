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

# Validate ID (only alphanumeric, dash, underscore allowed)
if [ "$ID" != "all" ] && [ -n "$ID" ]; then
    case "$ID" in
        *[!a-zA-Z0-9_-]*) echo '{"error":"invalid id"}'; exit 0 ;;
    esac
fi

if [ "$ID" = "all" ]; then
    rm -f /srv/tommyq/sport/activities/*.html
    rm -f /srv/tommyq/sport/activities/*.json
    rm -f /srv/tommyq/sport/activities/*.fit
    rm -f /srv/tommyq/sport/.activity_cache.json
    /root/scripts/generate-sport-maps.sh list-only >/dev/null 2>&1 &
    echo '{"status":"all deleted"}'
elif [ -n "$ID" ]; then
    rm -f "/srv/tommyq/sport/activities/${ID}.html"
    rm -f "/srv/tommyq/sport/activities/${ID}.json"
    rm -f "/srv/tommyq/sport/activities/${ID}.fit"
    /root/scripts/generate-sport-maps.sh list-only >/dev/null 2>&1 &
    echo "{\"status\":\"deleted\",\"id\":\"$ID\"}"
else
    echo '{"error":"missing id"}'
fi
