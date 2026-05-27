#!/bin/bash
# Generate sport activity maps - runs locally on Turris
set -e

BRYTON="/root/sport/bryton.py"
SPORT_DIR="/srv/tommyq/sport"
ACTIVITIES_DIR="$SPORT_DIR/activities"
TOKEN_FILE="/root/.tommyq/sport-token.conf"

source "$TOKEN_FILE"
mkdir -p "$ACTIVITIES_DIR"

# Generate maps for last 20 activities
ACTIVITIES=$(python3 "$BRYTON" list -n 20 2>/dev/null | tail -n +3 | awk '{print $1}')

for ID in $ACTIVITIES; do
    [ -f "$ACTIVITIES_DIR/${ID}.html" ] && continue
    python3 "$BRYTON" -o "$ACTIVITIES_DIR/${ID}.html" map "$ID" 2>/dev/null || true
done

# Generate index page
python3 - "$ACTIVITIES_DIR" "$TOKEN" << 'PYTHON'
import sys, re
from pathlib import Path

activities_dir = Path(sys.argv[1])
token = sys.argv[2]
files = sorted(activities_dir.glob("*.html"), key=lambda f: f.stat().st_mtime, reverse=True)

rows = []
for f in files:
    content = f.read_text()
    m = re.search(r'<title>(.*?)</title>', content)
    rows.append((f.stem, m.group(1) if m else f.stem))
rows.sort(key=lambda r: r[1], reverse=True)

html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Aktivity</title>
<style>
body {{ font-family: system-ui, sans-serif; margin: 0; padding: 2rem; background: #1a1a2e; color: #eee; }}
h1 {{ margin-bottom: 1.5rem; }}
.list {{ max-width: 800px; }}
a {{ color: #ff6b35; text-decoration: none; display: block; padding: 0.75rem 1rem; border-radius: 8px; margin-bottom: 0.5rem; background: rgba(255,255,255,0.05); border: 1px solid rgba(255,255,255,0.1); }}
a:hover {{ background: rgba(255,255,255,0.1); }}
button {{ background: #ff6b35; color: #fff; border: none; padding: 0.6rem 1.2rem; border-radius: 8px; cursor: pointer; font-size: 1rem; margin-bottom: 1.5rem; }}
button:hover {{ background: #e55a2b; }}
button:disabled {{ opacity: 0.5; cursor: wait; }}
</style></head><body>
<h1>🚴 Aktivity</h1>
<button onclick="refresh(this)">🔄 Aktualizovat</button>
<div class="list">
"""
for aid, title in rows:
    html += f'<a href="activities/{aid}.html?token={token}">{title}</a>\n'
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
