#!/bin/sh
echo "Content-Type: application/json"
echo "Access-Control-Allow-Origin: *"
echo ""
TOKEN=$(echo "$QUERY_STRING" | sed -n 's/.*token=\([^&]*\).*/\1/p')
ID=$(echo "$QUERY_STRING" | sed -n 's/.*id=\([^&]*\).*/\1/p')
ADMIN_TOKEN=$(grep '^TOKEN=' /root/.tommyq/sport-token.conf | cut -d= -f2)
PUB_TOKEN=$(grep '^PUBLIC_TOKEN=' /root/.tommyq/sport-token.conf | cut -d= -f2)

if [ "$TOKEN" != "$ADMIN_TOKEN" ] && [ "$TOKEN" != "$PUB_TOKEN" ]; then
    echo '{"error":"unauthorized"}'
    exit 0
fi
if [ -z "$ID" ]; then
    echo '{"error":"missing id"}'
    exit 0
fi

python3 /root/sport/bryton.py -f markdown detail "$ID" 2>/dev/null | python3 -c "
import sys, json, re
lines = sys.stdin.read().strip().split('\n')
title = lines[0].lstrip('# ') if lines else ''
date = lines[1].strip('* ') if len(lines) > 1 else ''
rows = []
for l in lines:
    m = re.match(r'\| (.+?) \| (.+?) \|', l)
    if m and '---' not in m.group(1) and m.group(1).strip() not in ('Metrika', 'Metric'):
        rows.append({'label': m.group(1).strip(), 'value': m.group(2).strip()})
print(json.dumps({'title': title, 'date': date, 'fields': rows}))
"
