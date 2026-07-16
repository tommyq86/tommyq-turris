#!/bin/bash
# Generate sport activity JSON data files and index page
set -e

BRYTON="/root/sport/bryton.py"
SPORT_DIR="/srv/tommyq/sport"
ACTIVITIES_DIR="$SPORT_DIR/activities"
TOKEN_FILE="/root/.tommyq/sport-token.conf"

source "$TOKEN_FILE"
mkdir -p "$ACTIVITIES_DIR"

# Fetch activities from Bryton
if [ "$1" != "list-only" ]; then
    LIST_OUTPUT=$(python3 "$BRYTON" list 2>/dev/null)
    ACTIVITIES=$(echo "$LIST_OUTPUT" | tail -n +3 | awk '{print $1}')

    # Cache durations from list output
    LIST_TMP=$(mktemp)
    echo "$LIST_OUTPUT" > "$LIST_TMP"
    python3 - "$SPORT_DIR/.activity_cache.json" "$LIST_TMP" << 'PYCACHE'
import sys, json, re
cache_path = sys.argv[1]
lines = open(sys.argv[2]).read().strip().split('\n')[2:]
cache = {}
for line in lines:
    parts = line.split()
    if len(parts) >= 5:
        aid = parts[0]
        m = re.match(r'(\d+):(\d+):(\d+)', parts[-1])
        if m:
            cache[aid] = int(m.group(1))*3600 + int(m.group(2))*60 + int(m.group(3))
try:
    existing = json.loads(open(cache_path).read())
    existing.update(cache)
    cache = existing
except (FileNotFoundError, json.JSONDecodeError):
    pass
open(cache_path, 'w').write(json.dumps(cache))
PYCACHE
    rm -f "$LIST_TMP"

    for ID in $ACTIVITIES; do
        if [ -f "$SPORT_DIR/.exclude" ] && grep -qx "$ID" "$SPORT_DIR/.exclude"; then
            continue
        fi
        [ -f "$ACTIVITIES_DIR/${ID}.html" ] || python3 "$BRYTON" -o "$ACTIVITIES_DIR/${ID}.html" map "$ID" 2>/dev/null || true
        [ -f "$ACTIVITIES_DIR/${ID}.fit" ] || python3 "$BRYTON" -o "$ACTIVITIES_DIR/${ID}.fit" download "$ID" 2>/dev/null || true
    done

    # Process imported FIT/GPX files
    IMPORT_SCRIPT="/root/sport/import_activity.py"
    if [ -f "$IMPORT_SCRIPT" ]; then
        for FILE in "$ACTIVITIES_DIR"/*.fit "$ACTIVITIES_DIR"/*.gpx; do
            [ -f "$FILE" ] || continue
            BASE=$(basename "$FILE")
            ID="${BASE%.*}"
            case "$ID" in [0-9][0-9][0-9][0-9][0-9]*) continue ;; esac
            [ -f "$ACTIVITIES_DIR/${ID}.html" ] && continue
            python3 "$IMPORT_SCRIPT" -o "$ACTIVITIES_DIR/${ID}.html" "$FILE" 2>/dev/null || true
        done
    fi

    # Cache duration for imported FIT files
    python3 - "$ACTIVITIES_DIR" "$SPORT_DIR/.activity_cache.json" << 'PYFIT'
import sys, json
from pathlib import Path
activities_dir = Path(sys.argv[1])
cache_path = Path(sys.argv[2])
try:
    cache = json.loads(cache_path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    cache = {}
try:
    import fitparse
    for f in activities_dir.glob("*.fit"):
        aid = f.stem
        if aid in cache:
            continue
        fit = fitparse.FitFile(str(f))
        for msg in fit.get_messages():
            if msg.name == "session":
                for field in msg.fields:
                    if field.name == "total_elapsed_time" and field.value:
                        cache[aid] = int(field.value)
                        break
                break
    cache_path.write_text(json.dumps(cache))
except ImportError:
    pass
PYFIT
fi

# Fetch HR zones from Bryton API for activities missing them
python3 - "$ACTIVITIES_DIR" "$SPORT_DIR/.exclude" << 'PYZONES'
import sys, json, re
from pathlib import Path

activities_dir = Path(sys.argv[1])
exclude_file = Path(sys.argv[2])

# Find activities missing hr_zones
needs_zones = []  # (json_path, [source_bryton_ids])
for f in activities_dir.glob("*.json"):
    data = json.loads(f.read_text())
    if "hr_zones" in data:
        continue
    stem = f.stem
    if stem.startswith("merged_"):
        # Try to extract Bryton IDs from filename (merged_ID1_ID2 format)
        parts = stem.replace("merged_", "").split("_")
        bryton_ids = [p for p in parts if len(p) > 10 and p.isalnum()]
        if not bryton_ids:
            # Date-based name — find source IDs from exclude file
            # These are excluded IDs not used by other merged files
            pass
        if bryton_ids:
            needs_zones.append((f, bryton_ids))
    elif len(stem) > 10:
        # Regular Bryton activity
        needs_zones.append((f, [stem]))

if not needs_zones:
    # Check for date-based merged files that need exclude-file lookup
    has_unresolved = False
    for f in activities_dir.glob("merged_*.json"):
        data = json.loads(f.read_text())
        if "hr_zones" not in data:
            parts = f.stem.replace("merged_", "").split("_")
            bryton_ids = [p for p in parts if len(p) > 10 and p.isalnum()]
            if not bryton_ids:
                has_unresolved = True
    if not has_unresolved:
        sys.exit(0)

# Connect to Bryton API and fetch zones
try:
    sys.path.insert(0, "/root/sport")
    sys.path.insert(0, "/root")
    from bryton import connect_and_login, load_config
    import time
    from datetime import datetime, timezone

    cfg = load_config()
    client = connect_and_login(cfg)
    client.subscribe("activityList")
    time.sleep(1)
    activities = client.collections.get("userActivities", {})

    # Resolve date-based merged files using exclude list + activity timestamps
    exclude_ids = []
    if exclude_file.exists():
        exclude_ids = [l.strip() for l in exclude_file.read_text().strip().split("\n") if l.strip()]

    # Find which exclude IDs are already claimed by ID-based merged files
    claimed_ids = set()
    for f in activities_dir.glob("merged_*.json"):
        parts = f.stem.replace("merged_", "").split("_")
        for p in parts:
            if len(p) > 10 and p.isalnum():
                claimed_ids.add(p)

    unclaimed_ids = [eid for eid in exclude_ids if eid not in claimed_ids]

    for f in activities_dir.glob("merged_*.json"):
        data = json.loads(f.read_text())
        if "hr_zones" in data:
            continue
        parts = f.stem.replace("merged_", "").split("_")
        bryton_ids = [p for p in parts if len(p) > 10 and p.isalnum()]
        if not bryton_ids and unclaimed_ids:
            # Match by date from filename
            date_match = re.findall(r"(\d{4}-\d{2}-\d{2})_(\d{4})", f.stem)
            if date_match:
                matched = []
                for eid in unclaimed_ids:
                    meta = activities.get(eid, {})
                    ts = meta.get("start_time", 0)
                    if ts:
                        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
                        local_str = f"{dt.strftime('%Y-%m-%d')}_{(dt.hour+2):02d}{dt.minute:02d}"
                        for d, t in date_match:
                            if local_str == f"{d}_{t}":
                                matched.append(eid)
                if matched:
                    bryton_ids = matched
        if bryton_ids:
            needs_zones.append((f, bryton_ids))

    # Fetch zones for all needed activities
    for json_path, source_ids in needs_zones:
        try:
            combined_zones = None
            for aid in source_ids:
                result = client.call("activity.detail.2", [aid])
                if not result:
                    continue
                vendor = result.get("vendor", {})
                summary = vendor.get("summary", {})
                zones = summary.get("time_in_hr_zone")
                if zones and any(z > 0 for z in zones):
                    if combined_zones is None:
                        combined_zones = list(zones)
                    else:
                        for i in range(min(len(combined_zones), len(zones))):
                            combined_zones[i] += zones[i]
            if combined_zones and any(z > 0 for z in combined_zones):
                data = json.loads(json_path.read_text())
                data["hr_zones"] = combined_zones
                json_path.write_text(json.dumps(data))
        except Exception:
            continue

    client.close()
except Exception:
    pass
PYZONES

# Generate JSON from HTML source files
python3 - "$ACTIVITIES_DIR" << 'PYJSON'
import sys, re, json, urllib.request
from datetime import datetime
from pathlib import Path

WMO_CODES = {
    0: "☀️ Jasno", 1: "🌤️ Převážně jasno", 2: "⛅ Polojasno", 3: "☁️ Zataženo",
    45: "🌫️ Mlha", 48: "🌫️ Námraza",
    51: "🌦️ Slabé mrholení", 53: "🌦️ Mrholení", 55: "🌦️ Silné mrholení",
    61: "🌧️ Slabý déšť", 63: "🌧️ Déšť", 65: "🌧️ Silný déšť",
    66: "🌧️ Slabý mrznoucí déšť", 67: "🌧️ Mrznoucí déšť",
    71: "🌨️ Slabé sněžení", 73: "🌨️ Sněžení", 75: "🌨️ Silné sněžení",
    80: "🌦️ Slabé přeháňky", 81: "🌦️ Přeháňky", 82: "🌦️ Silné přeháňky",
    85: "🌨️ Slabé sněhové přeháňky", 86: "🌨️ Sněhové přeháňky",
    95: "⛈️ Bouřka", 96: "⛈️ Bouřka s kroupami", 99: "⛈️ Bouřka se silnými kroupami",
}

def fetch_weather(lat, lon, date_str, hour):
    """Fetch weather from Open-Meteo for given coords, date, and hour."""
    url = (
        f"https://archive-api.open-meteo.com/v1/archive"
        f"?latitude={lat:.4f}&longitude={lon:.4f}"
        f"&start_date={date_str}&end_date={date_str}"
        f"&hourly=temperature_2m,relative_humidity_2m,precipitation,windspeed_10m,windgusts_10m,weathercode"
    )
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read())
        hourly = data.get("hourly", {})
        if not hourly or hour >= len(hourly.get("time", [])):
            return None
        code = hourly.get("weathercode", [None])[hour]
        return {
            "conditions": WMO_CODES.get(code, "?") if code is not None else None,
            "temperature": hourly.get("temperature_2m", [None])[hour],
            "humidity": hourly.get("relative_humidity_2m", [None])[hour],
            "precipitation": hourly.get("precipitation", [None])[hour],
            "wind_speed": hourly.get("windspeed_10m", [None])[hour],
            "wind_gusts": hourly.get("windgusts_10m", [None])[hour],
        }
    except Exception:
        return None

activities_dir = Path(sys.argv[1])
for f in activities_dir.glob("*.html"):
    json_path = f.with_suffix('.json')
    existing_data = None
    if json_path.exists():
        try:
            existing_data = json.loads(json_path.read_text())
        except (json.JSONDecodeError, OSError):
            pass
        # Skip if JSON is newer than HTML AND already has weather AND coords_sampled AND overview
        if existing_data and json_path.stat().st_mtime >= f.stat().st_mtime and "weather" in existing_data and "coords_sampled" in existing_data and "overview" in existing_data:
            continue

    content = f.read_text()
    def extract(name):
        m = re.search(rf'const {name} = (\[.*?\]);', content, re.DOTALL)
        if m:
            try: return json.loads(m.group(1))
            except: return []
        return []

    # If JSON exists with correct data but just missing weather/coords_sampled, patch it
    if existing_data and json_path.stat().st_mtime >= f.stat().st_mtime:
        data = existing_data
        coords = data.get("coords", [])
        date_str = data.get("date_str", "")
        if "coords_sampled" not in data:
            data["coords_sampled"] = extract("coordsSampled")
    else:
        title_m = re.search(r'<title>(.*?)</title>', content)
        h1_m = re.search(r'<h1>(.*?)</h1>', content)
        sub_m = re.search(r'class="subtitle">(.*?)</div>', content)
        title = title_m.group(1) if title_m else f.stem
        name = h1_m.group(1) if h1_m else title.split(' - ')[0] if ' - ' in title else title
        date_str = ''
        if sub_m:
            parts = sub_m.group(1).split(' · ')
            date_str = parts[0] if parts else ''
        elif ' - ' in title:
            date_str = title.split(' - ', 1)[1]
        coords = extract("coords")
        coords_sampled = extract("coordsSampled")
        data = {
            "name": name,
            "date_str": date_str,
            "subtitle": sub_m.group(1) if sub_m else '',
            "coords": coords,
            "coords_sampled": coords_sampled,
            "dist": extract("dist"),
            "alt": extract("alt"),
            "spd": extract("spd"),
            "hr": extract("hr"),
            "grad": extract("grad"),
        }

    # Fetch weather at midpoint of activity (if not already present)
    if coords and date_str and "weather" not in data:
        try:
            mid = coords[len(coords) // 2]
            dt = datetime.strptime(date_str, "%Y-%m-%d %H:%M")
            weather = fetch_weather(mid[0], mid[1], dt.strftime("%Y-%m-%d"), dt.hour)
            if weather:
                data["weather"] = weather
        except (ValueError, IndexError):
            pass

    # Generate overview from FIT file (if not already present)
    if "overview" not in data:
        fit_path = f.with_suffix('.fit')
        if fit_path.exists():
            try:
                import fitparse
                fit = fitparse.FitFile(str(fit_path))
                session = {}
                for msg in fit.get_messages():
                    if msg.name == 'session':
                        session = {field.name: field.value for field in msg.fields}
                        break
                def fmt_time(s):
                    h, rem = divmod(int(s), 3600)
                    m, sec = divmod(rem, 60)
                    return f"{h}:{m:02d}:{sec:02d}"
                fields = []
                # Speed
                avg_spd = session.get('enhanced_avg_speed') or session.get('avg_speed', 0)
                if avg_spd: fields.append({"label": "Prům. rychlost", "value": f"{avg_spd*3.6:.1f} km/h"})
                max_spd = session.get('enhanced_max_speed') or session.get('max_speed', 0)
                if max_spd: fields.append({"label": "Max. rychlost", "value": f"{max_spd*3.6:.1f} km/h"})
                # Cadence
                if session.get('avg_cadence'): fields.append({"label": "Prům. kadence", "value": f"{session['avg_cadence']} rpm"})
                # Elevation
                if session.get('total_ascent'): fields.append({"label": "Převýšení +", "value": f"{session['total_ascent']} m"})
                if session.get('total_descent'): fields.append({"label": "Převýšení −", "value": f"{session['total_descent']} m"})
                # Heart rate
                if session.get('avg_heart_rate'): fields.append({"label": "Prům. TF", "value": f"{session['avg_heart_rate']} bpm"})
                if session.get('max_heart_rate'): fields.append({"label": "Max. TF", "value": f"{session['max_heart_rate']} bpm"})
                # HR zones from Bryton API data
                hr_zones = data.get("hr_zones")
                if hr_zones and any(z > 0 for z in hr_zones):
                    zone_names = ["Zotavení", "Nízká intenzita", "Aerobní", "Anaerobní", "Maximální", "Nadmaximální", "Zóna 7", "Zóna 8"]
                    total_z = sum(hr_zones)
                    for i, ms in enumerate(hr_zones):
                        if ms > 0:
                            secs = ms / 1000
                            pct = ms * 100 / total_z
                            h, rem = divmod(int(secs), 3600)
                            m, sec = divmod(rem, 60)
                            time_str = f"{h}:{m:02d}:{sec:02d}" if h else f"{m}:{sec:02d}"
                            name = zone_names[i] if i < len(zone_names) else f"Zóna {i+1}"
                            fields.append({"label": f"Z{i+1} {name}", "value": f"{time_str}  ({pct:.0f}%)"})
                if fields:
                    data["overview"] = fields
            except Exception:
                pass

    json_path.write_text(json.dumps(data))
PYJSON

# Generate index page
python3 - "$ACTIVITIES_DIR" "$TOKEN" "$PUBLIC_TOKEN" << 'PYTHON'
import sys, re, json
from pathlib import Path

activities_dir = Path(sys.argv[1])
token = sys.argv[2]
public_token = sys.argv[3]
files = sorted(activities_dir.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True)

rows = []
total_km = 0.0
total_seconds = 0

durations = {}
cache_file = activities_dir.parent / ".activity_cache.json"
if cache_file.exists():
    try: durations = json.loads(cache_file.read_text())
    except: pass

for f in files:
    data = json.loads(f.read_text())
    aid = f.stem
    title = data.get("name", aid)
    date_str = data.get("date_str", "")
    dist_km = data["dist"][-1] if data.get("dist") else 0.0
    rows.append((aid, f"{title} - {date_str}" if date_str else title, dist_km, date_str))
    total_km += dist_km

rows.sort(key=lambda r: r[3], reverse=True)

for aid, _, _, _ in rows:
    if aid in durations:
        total_seconds += durations[aid]

def fmt_time(s):
    h, rem = divmod(int(s), 3600)
    m, _ = divmod(rem, 60)
    return f"{h}h {m:02d}min" if h else f"{m} min"

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Aktivity</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 0; padding: 2rem; background: #1a1a2e; color: #eee; }}
h1 {{ margin-bottom: 1.5rem; }}
.header {{ display: flex; align-items: center; gap: 1rem; flex-wrap: wrap; margin-bottom: 1.5rem; }}
.totals {{ color: #aaa; font-size: 0.95rem; }}
.list {{ max-width: 800px; }}
a {{ color: #ff6b35; text-decoration: none; display: flex; justify-content: space-between; align-items: center; padding: 0.75rem 1rem; border-radius: 8px; margin-bottom: 0.5rem; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); }}
a:hover {{ background: rgba(255,255,255,0.1); }}
.meta {{ color: #aaa; font-size: 0.85rem; white-space: nowrap; margin-left: 1rem; }}
.row {{ display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; }}
.share,.del {{ background: none; border: none; color: #aaa; cursor: pointer; padding: 0.4rem; font-size: 1.1rem; border-radius: 4px; display: none; }}
.share:hover {{ color: #fff; background: rgba(255,255,255,0.1); }}
.del:hover {{ color: #ff4444; background: rgba(255,68,68,0.1); }}
.overview {{ background: none; border: none; color: #aaa; cursor: pointer; padding: 0.4rem; font-size: 1.1rem; border-radius: 4px; }}
.overview:hover {{ color: #fff; background: rgba(255,255,255,0.1); }}
button {{ background: #ff6b35; color: #fff; border: none; padding: 0.6rem 1.2rem; border-radius: 8px; cursor: pointer; font-size: 1rem; }}
button:hover {{ background: #e55a2b; }}
button:disabled {{ opacity: 0.5; cursor: wait; }}
</style></head><body>
<h1>🚴 Aktivity</h1>
<div class="header">
<button id="refreshBtn" onclick="refresh(this)" style="display:none">🔄 Aktualizovat</button>
<button id="shareListBtn" onclick="share(this,'?token=""" + public_token + f"""')" style="display:none" title="Kopírovat odkaz na seznam">🔗 Sdílet seznam</button>
<button id="deleteAllBtn" onclick="deleteAll(this)" style="display:none">🗑️ Smazat vše</button>
<span class="totals">Celkem: {total_km:.1f} km""" + (f" · {fmt_time(total_seconds)}" if total_seconds else "") + """</span>
</div>
<div class="list">
"""
for aid, title, dist_km, _ in rows:
    dur_str = ""
    if aid in durations:
        dur_str = f" · {fmt_time(durations[aid])}"
    meta = f"{dist_km:.1f} km{dur_str}" if dist_km > 0 else ""
    activity_url = f"activity.html?id={aid}&token={public_token}"
    html += f'<div class="row"><button class="del" onclick="del(this,\'{aid}\')" title="Smazat">🗑️</button><button class="share" onclick="share(this,\'activity.html?id={aid}&token={public_token}\')" title="Kopírovat odkaz">🔗</button><button class="overview" onclick="overview(this,\'{aid}\')" title="Přehled">📊</button><a href="{activity_url}"><span>{title}</span><span class="meta">{meta}</span></a></div>\n'
html += """</div>
<script>
var isAdmin = location.search.includes('token=""" + token + """');
var reqToken = new URLSearchParams(location.search).get('token');
if (isAdmin) {
  document.getElementById('refreshBtn').style.display = '';
  document.getElementById('shareListBtn').style.display = '';
  document.getElementById('deleteAllBtn').style.display = '';
  document.querySelectorAll('.share').forEach(b => b.style.display = 'inline-block');
  document.querySelectorAll('.del').forEach(b => b.style.display = 'inline-block');
  // Fix activity links to use admin token
  document.querySelectorAll('.list a').forEach(a => a.href = a.href.replace('token=""" + public_token + """', 'token=""" + token + """'));
}
function share(btn, path) {
  navigator.clipboard.writeText(location.origin + '/sport/' + path).then(() => {
    btn.textContent = '✓'; setTimeout(() => btn.textContent = '🔗', 1500);
  });
}
function overview(btn, id) {
  btn.textContent = '⏳';
  fetch('cgi/overview.cgi?token=' + reqToken + '&id=' + id)
    .then(r => r.json()).then(d => {
      var text = d.title + '\\n' + d.date + '\\n\\n' + d.fields.map(f => f.label + ': ' + f.value).join('\\n');
      return navigator.clipboard.writeText(text);
    }).then(() => { btn.textContent = '✓'; setTimeout(() => btn.textContent = '📊', 1500); })
    .catch(() => { btn.textContent = '✗'; setTimeout(() => btn.textContent = '📊', 1500); });
}
function del(btn, id) {
  if (!confirm('Smazat aktivitu?')) return;
  btn.disabled = true;
  fetch('cgi/delete.cgi?token=""" + token + """&id=' + id)
    .then(() => btn.closest('.row').remove());
}
function deleteAll(btn) {
  if (!confirm('Smazat VŠECHNY aktivity?')) return;
  btn.disabled = true; btn.textContent = '⏳ Mažu...';
  fetch('cgi/delete.cgi?token=""" + token + """&id=all')
    .then(() => { btn.textContent = '✓ Smazáno'; setTimeout(() => location.reload(), 5000); });
}
function refresh(btn) {
  btn.disabled = true; btn.textContent = '⏳ Generuji...';
  fetch('cgi/refresh.cgi?' + location.search.slice(1)).then(function() {
    var poll = setInterval(function() {
      fetch('cgi/api.cgi?token=' + reqToken + '&id=refresh-status').then(r => r.json()).then(function(s) {
        if (s.done) { clearInterval(poll); location.reload(); }
      });
    }, 3000);
  }).catch(() => { btn.textContent = '✗ Chyba'; btn.disabled = false; });
}
</script>
</body></html>"""

Path(sys.argv[1]).parent.joinpath("index.html").write_text(html)
PYTHON
