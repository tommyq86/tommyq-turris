#!/bin/sh
# If redirect param is present, redirect back after successful auth
REDIRECT=$(echo "$QUERY_STRING" | sed -n 's/.*redirect=\([^&]*\).*/\1/p' | python3 -c "import sys,urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))" 2>/dev/null)

if [ -n "$REDIRECT" ]; then
    # Add auth=1 param to signal successful login
    case "$REDIRECT" in
        *\?*) REDIRECT="${REDIRECT}&auth=1" ;;
        *) REDIRECT="${REDIRECT}?auth=1" ;;
    esac
    echo "Status: 302"
    echo "Location: $REDIRECT"
    echo ""
else
    echo "Content-Type: application/json"
    echo ""
    echo '{"admin":true}'
fi
