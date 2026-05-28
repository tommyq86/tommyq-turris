#!/bin/bash
# Generate sport activity maps - runs locally on Turris
set -e

BRYTON="/root/sport/bryton.py"
SPORT_DIR="/srv/tommyq/sport"
ACTIVITIES_DIR="$SPORT_DIR/activities"
TOKEN_FILE="/root/.tommyq/sport-token.conf"

source "$TOKEN_FILE"
mkdir -p "$ACTIVITIES_DIR"

# Generate maps for activities and cache metadata
if [ "$1" = "all" ]; then
    LIST_OUTPUT=$(python3 "$BRYTON" list 2>/dev/null)
else
    LIST_OUTPUT=$(python3 "$BRYTON" list -n 20 2>/dev/null)
fi
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

# Generate JSON files from HTML
python3 - "$ACTIVITIES_DIR" "$PUBLIC_TOKEN" << 'PYJSON'
import sys, re, json
from pathlib import Path
activities_dir = Path(sys.argv[1])
public_token = sys.argv[2]
for f in activities_dir.glob("*.html"):
    jf = f.with_suffix(".json")
    content = f.read_text()
    # Generate JSON
    if not jf.exists():
        def extract(name):
            m = re.search(rf'const {name} = (\[.*?\]);', content, re.DOTALL)
            if m:
                try: return json.loads(m.group(1))
                except: return None
            return None
        title_m = re.search(r'<title>(.*?)</title>', content)
        sub_m = re.search(r'class="subtitle">(.*?)</div>', content)
        data = {
            "title": title_m.group(1) if title_m else f.stem,
            "subtitle": sub_m.group(1) if sub_m else None,
            "coords": extract("coords"),
            "distance_km": extract("dist"),
            "altitude_m": extract("alt"),
            "speed_kmh": extract("spd"),
            "heart_rate_bpm": extract("hr"),
            "gradient_pct": extract("grad"),
        }
        jf.write_text(json.dumps(data))
    # Inject/update share buttons
    share_html = f'''<script src="https://cdn.jsdelivr.net/npm/html2canvas@1.4.1/dist/html2canvas.min.js"></script>
<div id="shareBar" style="position:fixed;top:8px;right:8px;display:flex;gap:4px;z-index:9999">
<button onclick="navigator.clipboard.writeText(location.href).then(()=>this.textContent='✓')" style="background:#ff6b35;border:none;color:#fff;padding:6px 10px;border-radius:6px;cursor:pointer;font-size:1rem" title="Kopírovat odkaz">🔗</button>
<a href="{f.stem}.json?token={public_token}" download="{f.stem}.json" style="background:#ff6b35;border:none;color:#fff;padding:6px 10px;border-radius:6px;cursor:pointer;font-size:1rem;text-decoration:none" title="Stáhnout JSON">⬇️</a>
<button onclick="exportPng(this)" style="background:#ff6b35;border:none;color:#fff;padding:6px 10px;border-radius:6px;cursor:pointer;font-size:1rem" title="Stáhnout mapu jako PNG">🖼️</button>
</div>
<script>
function exportPng(btn) {{
  btn.disabled = true; btn.textContent = '⏳';
  html2canvas(document.body, {{useCORS:true}}).then(function(canvas) {{
    var a = document.createElement('a');
    a.download = document.title.replace(/[^a-zA-Z0-9_-]/g,'_') + '.png';
    a.href = canvas.toDataURL('image/png');
    a.click();
    btn.textContent = '🖼️'; btn.disabled = false;
  }}).catch(function() {{ btn.textContent = '✗'; btn.disabled = false; }});
}}
</script>'''
    # Remove old shareBar and exportPng if present, then inject new
    import re as _re
    content = _re.sub(r'<script src="https://cdn\.jsdelivr\.net/npm/html2canvas.*?</script>', '', content, flags=_re.DOTALL)
    content = _re.sub(r'<div id="shareBar".*?</div>', '', content, flags=_re.DOTALL)
    content = _re.sub(r'<script>\s*function exportPng.*?</script>', '', content, flags=_re.DOTALL)
    content = content.replace('</body>', share_html + '</body>')
    f.write_text(content)
PYJSON

# Generate index page
python3 - "$ACTIVITIES_DIR" "$TOKEN" "$PUBLIC_TOKEN" << 'PYTHON'
import sys, re, json
from pathlib import Path

activities_dir = Path(sys.argv[1])
token = sys.argv[2]
public_token = sys.argv[3]
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
.row {{ display: flex; align-items: center; gap: 0.5rem; margin-bottom: 0.5rem; }}
.share {{ background: none; border: none; color: #aaa; cursor: pointer; padding: 0.4rem; font-size: 1.1rem; border-radius: 4px; display: none; }}
.share:hover {{ color: #fff; background: rgba(255,255,255,0.1); }}
.del {{ background: none; border: none; color: #aaa; cursor: pointer; padding: 0.4rem; font-size: 1.1rem; border-radius: 4px; display: none; }}
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
<button id="shareListBtn" onclick="share(this,'?token=""" + public_token + """')" style="display:none" title="Kopírovat odkaz na seznam">🔗 Sdílet seznam</button>
<button id="deleteAllBtn" onclick="deleteAll(this)" style="display:none">🗑️ Smazat vše</button>
<span class="totals">Celkem: {total_km:.1f} km""" + (f" · {fmt_time(total_seconds)}" if total_seconds else "") + """</span>
</div>
<div class="list">
"""
for aid, title, dist_km in rows:
    dur_str = ""
    if aid in durations:
        dur_str = f" · {fmt_time(durations[aid])}"
    meta = f"{dist_km:.1f} km{dur_str}" if dist_km > 0 else ""
    share_url = f"activities/{aid}.html?token={public_token}"
    json_url = f"activities/{aid}.json?token={public_token}"
    html += f'<div class="row"><button class="del" onclick="del(this,\'{aid}\')" title="Smazat">🗑️</button><button class="share" onclick="share(this,\'{share_url}\')" title="Kopírovat odkaz">🔗</button><button class="share" onclick="download(\'{json_url}\',\'{aid}.json\')" title="Stáhnout JSON">⬇️</button><button class="overview" onclick="overview(this,\'{aid}\')" title="Přehled">📊</button><a href="{share_url}"><span>{title}</span><span class="meta">{meta}</span></a></div>\n'
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
}
function share(btn, path) {
  var url = location.origin + '/sport/' + path;
  navigator.clipboard.writeText(url).then(() => {
    btn.textContent = '✓'; setTimeout(() => btn.textContent = '🔗', 1500);
  });
}
function download(url, name) {
  var a = document.createElement('a'); a.href = url; a.download = name; a.click();
}
function overview(btn, id) {
  btn.textContent = '⏳';
  fetch('cgi/overview.cgi?token=' + reqToken + '&id=' + id)
    .then(r => r.json()).then(d => {
      var text = d.title + '\\n' + d.date + '\\n\\n' + d.fields.map(f => f.label + ': ' + f.value).join('\\n');
      return navigator.clipboard.writeText(text);
    }).then(() => {
      btn.textContent = '✓'; setTimeout(() => btn.textContent = '📊', 1500);
    }).catch(() => { btn.textContent = '✗'; setTimeout(() => btn.textContent = '📊', 1500); });
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
  fetch('cgi/refresh.cgi?' + location.search.slice(1))
    .then(() => { btn.textContent = '✓ Hotovo'; setTimeout(() => location.reload(), 30000); })
    .catch(() => { btn.textContent = '✗ Chyba'; btn.disabled = false; });
}
</script>
</body></html>"""

Path(sys.argv[1]).parent.joinpath("index.html").write_text(html)
PYTHON
