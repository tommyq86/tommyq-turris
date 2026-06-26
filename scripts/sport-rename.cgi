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

if [ -z "$NAME" ]; then
    echo '{"error":"missing name"}'
    exit 0
fi

JSON_FILE="/srv/tommyq/sport/activities/${ID}.json"
HTML_FILE="/srv/tommyq/sport/activities/${ID}.html"

if [ ! -f "$JSON_FILE" ] && [ ! -f "$HTML_FILE" ]; then
    echo '{"error":"not found"}'
    exit 0
fi

# Update JSON
if [ -f "$JSON_FILE" ]; then
    python3 -c "
import sys, json
path, name = sys.argv[1], sys.argv[2]
data = json.loads(open(path).read())
data['name'] = name
data['subtitle'] = name + ' · ' + ' · '.join(data.get('subtitle','').split(' · ')[1:]) if ' · ' in data.get('subtitle','') else name
open(path, 'w').write(json.dumps(data))
" "$JSON_FILE" "$NAME"
fi

# Update HTML source too
if [ -f "$HTML_FILE" ]; then
    python3 -c "
import sys, re
path, name = sys.argv[1], sys.argv[2]
content = open(path).read()
content = re.sub(r'(<title>).*?(</title>)', rf'\g<1>{name}\g<2>', content, count=1)
content = re.sub(r'(<h1>).*?(</h1>)', rf'\g<1>{name}\g<2>', content, count=1)
open(path, 'w').write(content)
" "$HTML_FILE" "$NAME"
fi

/root/scripts/generate-sport-maps.sh list-only >/dev/null 2>&1 &
echo "{\"status\":\"renamed\",\"id\":\"$ID\"}"
