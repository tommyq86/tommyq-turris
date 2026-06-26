#!/bin/sh
echo "Content-Type: application/json"
echo ""
TOKEN=$(echo "$QUERY_STRING" | sed -n 's/.*token=\([^&]*\).*/\1/p')
ID=$(echo "$QUERY_STRING" | sed -n 's/.*id=\([^&]*\).*/\1/p')
NAME=$(echo "$QUERY_STRING" | sed -n 's/.*name=\([^&]*\).*/\1/p' | python3 -c "import sys,urllib.parse;print(urllib.parse.unquote(sys.stdin.read().strip()))")
ADMIN_TOKEN=$(grep '^TOKEN=' /root/.tommyq/sport-token.conf | cut -d= -f2)

if [ "$TOKEN" != "$ADMIN_TOKEN" ]; then
    echo '{"error":"unauthorized"}'
    exit 0
fi

case "$ID" in
    *[!a-zA-Z0-9_-]*) echo '{"error":"invalid id"}'; exit 0 ;;
esac

FILE="/srv/tommyq/sport/activities/${ID}.html"
if [ ! -f "$FILE" ]; then
    echo '{"error":"not found"}'
    exit 0
fi

if [ -z "$NAME" ]; then
    echo '{"error":"missing name"}'
    exit 0
fi

python3 - "$FILE" "$NAME" << 'PYTHON'
import sys, re
path, name = sys.argv[1], sys.argv[2]
content = open(path).read()
content = re.sub(r'(<title>).*?(</title>)', rf'\g<1>{name}\g<2>', content, count=1)
content = re.sub(r'(<h1>).*?(</h1>)', rf'\g<1>{name}\g<2>', content, count=1)
open(path, 'w').write(content)
PYTHON

/root/scripts/generate-sport-maps.sh list-only >/dev/null 2>&1 &
echo "{\"status\":\"renamed\",\"id\":\"$ID\"}"
