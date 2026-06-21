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

# Try Bryton API first
BRYTON_OUT=$(python3 /root/sport/bryton.py -f markdown detail "$ID" 2>&1)

if [ $? -eq 0 ] && echo "$BRYTON_OUT" | grep -q "^#"; then
    echo "$BRYTON_OUT" | python3 -c "
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
else
    # Fallback: read from FIT file
    FIT_FILE="/srv/tommyq/sport/activities/${ID}.fit"
    if [ -f "$FIT_FILE" ]; then
        python3 -c "
import sys, json, fitparse

def fmt(s):
    h, rem = divmod(int(s), 3600)
    m, sec = divmod(rem, 60)
    return f'{h}:{m:02d}:{sec:02d}'

f = fitparse.FitFile('$FIT_FILE')
session = {}
for msg in f.get_messages():
    if msg.name == 'session':
        session = {field.name: field.value for field in msg.fields}
        break

sport = str(session.get('sport', 'Activity')).replace('_', ' ').title()
start = session.get('start_time')
date_str = start.strftime('%Y-%m-%d %H:%M') if hasattr(start, 'strftime') else str(start) if start else '?'
fields = []
dist = session.get('total_distance', 0)
if dist: fields.append({'label': 'Vzdálenost', 'value': f'{dist/1000:.2f} km'})
elapsed = session.get('total_elapsed_time', 0)
if elapsed: fields.append({'label': 'Doba trvání', 'value': fmt(elapsed)})
avg_spd = session.get('enhanced_avg_speed') or session.get('avg_speed', 0)
if avg_spd: fields.append({'label': 'Prům. rychlost', 'value': f'{avg_spd*3.6:.1f} km/h'})
max_spd = session.get('enhanced_max_speed') or session.get('max_speed', 0)
if max_spd: fields.append({'label': 'Max. rychlost', 'value': f'{max_spd*3.6:.1f} km/h'})
if session.get('avg_heart_rate'): fields.append({'label': 'Prům. TF', 'value': f\"{session['avg_heart_rate']} bpm\"})
if session.get('max_heart_rate'): fields.append({'label': 'Max. TF', 'value': f\"{session['max_heart_rate']} bpm\"})
if session.get('avg_cadence'): fields.append({'label': 'Prům. kadence', 'value': f\"{session['avg_cadence']} rpm\"})
if session.get('total_ascent'): fields.append({'label': 'Převýšení +', 'value': f\"{session['total_ascent']} m\"})
if session.get('total_descent'): fields.append({'label': 'Převýšení -', 'value': f\"{session['total_descent']} m\"})
print(json.dumps({'title': sport, 'date': date_str, 'fields': fields}))
"
    else
        echo '{"error":"not found"}'
    fi
fi
