#!/bin/bash
# Generate sport activity maps - runs locally on Turris
set -e

BRYTON="/root/sport/bryton.py"
SPORT_DIR="/srv/tommyq/sport"
ACTIVITIES_DIR="$SPORT_DIR/activities"
TOKEN_FILE="/root/.tommyq/sport-token.conf"

source "$TOKEN_FILE"
mkdir -p "$ACTIVITIES_DIR"

# Generate maps for last 20 activities and cache metadata
LIST_OUTPUT=$(python3 "$BRYTON" list -n 20 2>/dev/null)
ACTIVITIES=$(echo "$LIST_OUTPUT" | tail -n +3 | awk '{print $1}')

# Save duration cache (ID -> elapsed seconds) from list output
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
        dur = parts[-1]
        m = re.match(r'(\d+):(\d+):(\d+)', dur)
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
    [ -f "$ACTIVITIES_DIR/${ID}.html" ] && continue
    python3 "$BRYTON" -o "$ACTIVITIES_DIR/${ID}.html" map "$ID" 2>/dev/null || true
done

# Generate index page
python3 - "$ACTIVITIES_DIR" "$TOKEN" << 'PYTHON'
import sys, re, json
from pathlib import Path

activities_dir = Path(sys.argv[1])
token = sys.argv[2]
files = sorted(activities_dir.glob("*.html"), key=lambda f: f.stat().st_mtime, reverse=True)

rows = []
total_km = 0.0
total_seconds = 0
for f in files:
    content = f.read_text()
    m = re.search(r'<title>(.*?)</title>', content)
    title = m.group(1) if m else f.stem
    # Extract distance from last value of dist array
    dm = re.search(r'const dist = (\[.*?\]);', content)
    dist_km = 0.0
    if dm:
        try:
            dist_arr = json.loads(dm.group(1))
            if dist_arr:
                dist_km = dist_arr[-1]
        except (json.JSONDecodeError, IndexError):
            pass
    rows.append((f.stem, title, dist_km))
    total_km += dist_km

# Try to get duration from bryton list cache if available
durations = {}
cache_file = activities_dir.parent / ".activity_cache.json"
if cache_file.exists():
    try:
        cache = json.loads(cache_file.read_text())
        durations = {k: v for k, v in cache.items()}
    except (json.JSONDecodeError, KeyError):
        pass

rows.sort(key=lambda r: r[1], reverse=True)

# Compute total time
for aid, _, _ in rows:
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
button {{ background: #ff6b35; color: #fff; border: none; padding: 0.6rem 1.2rem; border-radius: 8px; cursor: pointer; font-size: 1rem; }}
button:hover {{ background: #e55a2b; }}
button:disabled {{ opacity: 0.5; cursor: wait; }}
</style></head><body>
<h1>🚴 Aktivity</h1>
<div class="header">
<button onclick="refresh(this)">🔄 Aktualizovat</button>
<span class="totals">Celkem: {total_km:.1f} km""" + (f" · {fmt_time(total_seconds)}" if total_seconds else "") + """</span>
</div>
<div class="list">
"""
for aid, title, dist_km in rows:
    dur_str = ""
    if aid in durations:
        dur_str = f" · {fmt_time(durations[aid])}"
    meta = f"{dist_km:.1f} km{dur_str}" if dist_km > 0 else ""
    html += f'<a href="activities/{aid}.html?token={token}"><span>{title}</span><span class="meta">{meta}</span></a>\n'
html += """</div>
<script>
function refresh(btn) {
  btn.disabled = true; btn.textContent = '⏳ Generuji...';
  fetch('cgi/refresh.cgi?' + location.search.slice(1))
    .then(() => { btn.textContent = '✓ Hotovo'; setTimeout(() => location.reload(), 30000); })
    .catch(() => { btn.textContent = '✗ Chyba'; btn.disabled = false; });
}
</script>
</body></html>"""

Path(sys.argv[1]).parent.joinpath("index.html").write_text(html)
PYTHON
