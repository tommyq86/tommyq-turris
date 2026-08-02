#!/bin/sh
# CGI endpoint for uploading GPX route to Bryton Active
# Receives POST with GPX body, uploads via bryton.py routes upload

echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: POST, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# Handle CORS preflight
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    exit 0
fi

if [ "$REQUEST_METHOD" != "POST" ]; then
    echo '{"error":"method not allowed"}'
    exit 0
fi

# Read GPX from stdin
TMPFILE="/tmp/brouter_upload_$$.gpx"
cat > "$TMPFILE"

if [ ! -s "$TMPFILE" ]; then
    echo '{"error":"empty body"}'
    rm -f "$TMPFILE"
    exit 0
fi

# Extract route name from GPX
NAME=$(grep -oP '(?<=<name>)[^<]+' "$TMPFILE" | head -1)
[ -z "$NAME" ] && NAME="Route $(date +%Y-%m-%d_%H%M)"

# Upload via bryton.py
RESULT=$(python3 /root/sport/bryton.py routes upload "$TMPFILE" --name "$NAME" 2>&1)
RC=$?

rm -f "$TMPFILE"

if [ $RC -eq 0 ]; then
    echo "{\"status\":\"ok\",\"name\":\"$NAME\",\"message\":\"$RESULT\"}"
else
    # Escape quotes in error message
    ERROR=$(echo "$RESULT" | tr '"' "'")
    echo "{\"error\":\"$ERROR\"}"
fi
