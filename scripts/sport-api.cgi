#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""

# Extract params
REQ_TOKEN=$(echo "$QUERY_STRING" | sed -n 's/.*token=\([^&]*\).*/\1/p')
ID=$(echo "$QUERY_STRING" | sed -n 's/.*id=\([^&]*\).*/\1/p')

# Validate token
ADMIN_TOKEN=$(grep '^TOKEN=' /root/.tommyq/sport-token.conf | cut -d= -f2)
PUB_TOKEN=$(grep '^PUBLIC_TOKEN=' /root/.tommyq/sport-token.conf | cut -d= -f2)

if [ "$REQ_TOKEN" != "$ADMIN_TOKEN" ] && [ "$REQ_TOKEN" != "$PUB_TOKEN" ]; then
    echo '{"error":"unauthorized"}'
    exit 0
fi

# Validate ID (only alphanumeric, dash, underscore allowed)
if [ -n "$ID" ]; then
    case "$ID" in
        *[!a-zA-Z0-9_-]*) echo '{"error":"invalid id"}'; exit 0 ;;
    esac
fi

if [ -z "$ID" ]; then
    # List all activities
    python3 - /srv/tommyq/sport/activities << 'PYLIST'
import sys, re, json
from pathlib import Path
activities = sorted(Path(sys.argv[1]).glob("*.html"), key=lambda f: f.stat().st_mtime, reverse=True)
result = []
for f in activities:
    content = f.read_text()
    title_m = re.search(r'<title>(.*?)</title>', content)
    sub_m = re.search(r'class="subtitle">(.*?)</div>', content)
    result.append({"id": f.stem, "title": title_m.group(1) if title_m else f.stem, "subtitle": sub_m.group(1) if sub_m else None})
print(json.dumps(result))
PYLIST
    exit 0
fi

FILE="/srv/tommyq/sport/activities/${ID}.html"
if [ ! -f "$FILE" ]; then
    echo '{"error":"not found"}'
    exit 0
fi

python3 - "$FILE" << 'PYTHON'
import sys, re, json

content = open(sys.argv[1]).read()

def extract(name):
    m = re.search(rf'const {name} = (\[.*?\]);', content, re.DOTALL)
    if m:
        try:
            return json.loads(m.group(1))
        except:
            return None
    return None

title_m = re.search(r'<title>(.*?)</title>', content)
sub_m = re.search(r'class="subtitle">(.*?)</div>', content)

data = {
    "title": title_m.group(1) if title_m else None,
    "subtitle": sub_m.group(1) if sub_m else None,
    "coords": extract("coords"),
    "distance_km": extract("dist"),
    "altitude_m": extract("alt"),
    "speed_kmh": extract("spd"),
    "heart_rate_bpm": extract("hr"),
    "gradient_pct": extract("grad"),
}

print(json.dumps(data))
PYTHON
