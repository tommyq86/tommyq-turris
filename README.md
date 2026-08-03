# tommyq-turris

Configuration and scripts for Turris MOX router.

## Quick Links

- [Setup Documentation](docs/setup.md)
- [Lighttpd Configuration](lighttpd/)
- [Scripts](scripts/)
- [System Configuration](system/)
- [Web Dashboard](www/)

## Structure

```
├── deploy.sh                  # Main deployment script
├── lighttpd/
│   ├── configs/
│   │   ├── 49-tommyq-no-auth.conf          # Disable Turris auth for tommyq.cz
│   │   ├── 99-tommyq-00-base.conf          # Base domain, HTTP redirect, BRouter API proxy, CGI
│   │   ├── 99-tommyq-10-media.conf         # Media Services (Plex, Seerr, *arr, Calibre-Web, Audiobookshelf)
│   │   ├── 99-tommyq-20-tools.conf         # Tools & Downloading (DSM, qBit, etc.)
│   │   ├── 99-tommyq-30-sport.conf.template # Sport service (token auth)
│   │   └── 99-tommyq-30-sport.conf         # Generated from template by deploy.sh
│   └── deploy.sh              # Lighttpd-only deployment
├── www/
│   ├── index.html             # Services dashboard
│   ├── sport/
│   │   └── activity.html      # Activity viewer template (loads JSON data)
│   └── garage/                # Bike garage gallery
├── scripts/
│   ├── generate-sport-maps.sh        # Generate sport activity JSON + index
│   ├── sport-api.cgi                 # Sport API (list, detail, admin check)
│   ├── sport-delete.cgi              # Delete activities (admin)
│   ├── sport-overview.cgi            # Activity overview (copy text)
│   ├── sport-refresh.cgi             # Trigger activity regeneration
│   ├── sport-rename.cgi              # Rename activity (admin)
│   ├── sport-auth.cgi                # HTTP Basic auth endpoint (sport admin mimo LAN)
│   ├── turris-backup.sh              # Backup Turris to Synology NAS
│   ├── leo-trigger-turris-backup.sh  # Trigger backup from Leo
│   ├── turris-mem-monitor.sh         # Memory monitoring (RAM/SWAP)
│   ├── turris-new-device-alert.sh    # New device notification
│   ├── pre-update-backup.sh          # Pre-TurrisOS update backup
│   ├── post-update-restore.sh        # Post-TurrisOS update restore
│   ├── restore-assistant.sh          # Restore assistant service
│   ├── safe-reboot.sh               # Safe reboot (clear updater flags)
│   └── kresd-watchdog.sh            # Monitoring and restart kresd při výpadku
├── system/
│   ├── kresd-custom.conf      # Knot Resolver - local domain overrides
│   ├── dnsmasq-local-domains.conf  # Dnsmasq local domain resolution
│   ├── hosts                  # Custom hosts file
│   ├── dnsmasq.conf.example   # DNS configuration (legacy reference)
│   └── no-foris.lua           # Updater config - disable Foris web interface
└── docs/
    └── setup.md               # Setup documentation
```

**Note:** DNS configuration is managed via Knot Resolver (`/etc/kresd/custom.conf`). Local domains (`*.tommyq.cz`) resolve to `192.168.2.1`.

## Deployment

### Selective deployment (recommended)

```bash
./deploy.sh <components...> [--host root@turris]
```

Components:
- `lighttpd` — modules, configs, reverse proxy (restarts lighttpd)
- `scripts` — shell scripts to `/root/scripts/`
- `dashboard` — web dashboard (`/www/tommyq/`)
- `system` — DNS, kresd, dnsmasq, hosts, CA cert, kresd init script fix (restarts DNS services)
- `sport` — CGI, Python scripts, activity.html, cron jobs

Examples:
```bash
./deploy.sh sport              # deploy only sport service
./deploy.sh lighttpd sport     # lighttpd + sport
./deploy.sh system --host root@192.168.2.1
```

### Complete deployment

```bash
./deploy.sh                    # no arguments = deploy all components
```

### Lighttpd configuration only

```bash
cd lighttpd
./deploy.sh [root@turris]
```

## Sport Service

Token-authenticated activity viewer at `/sport/`. Architecture:

- **Template:** `www/sport/activity.html` — single page that loads activity data from JSON
- **Data:** `/srv/tommyq/sport/activities/{id}.json` — coords, altitude, speed, HR, gradient
- **Source:** `/srv/tommyq/sport/activities/{id}.html` — generated from Bryton API (data source for JSON)
- **FIT files:** `/srv/tommyq/sport/activities/{id}.fit` — downloadable (admin only)

### Access Control

Two tokens:
- **admin** — plný přístup (rename, delete, FIT download, refresh)
- **public** — view only, pro sdílení aktivit

Admin akce z LAN fungují bez hesla. Z VPN/venku vyžadují HTTP Basic auth (PAM) — endpoint `sport-auth.cgi`. Frontend zobrazuje login tlačítko 🔑.

### BRouter Route Planner

Gravel route planner dostupný na `tommyq.cz/brouter`. Frontend je v `tommyq-sport/brouter/`, deploy přes `deploy.sh sport`. Routing API proxy směřuje na BRouter kontejner na leo:17777.

Features: map with route, charts (altitude/speed/HR/gradient), GPX export (route only), FIT download (admin), rename (admin), PNG export, overview copy.

Regeneration:
```bash
ssh turris '/root/scripts/generate-sport-maps.sh'              # full (fetch + generate)
ssh turris '/root/scripts/generate-sport-maps.sh list-only'    # regenerate index only
ssh turris '/root/scripts/generate-sport-maps.sh <ID>'         # regenerate specific activity (weather, overview, zones)
```

### Merged activities

When a ride is split into multiple Bryton activities (e.g. device restart), merge and upload:

```bash
bryton merge-upload    # one command: download last 2, merge, upload, exclude, regenerate
```

See [tommyq-sport](https://github.com/tommyq86/tommyq-sport) for manual merge workflow.

The `.exclude` file contains Bryton activity IDs (one per line) skipped during generation. Imported FIT files (names not starting with 5+ digits) are processed via `import_activity.py`.

## Docker on Leo

Reverse proxy routes requests to Docker containers running on leo (Synology NAS). Notable containers:

- **BRouter** (`ghcr.io/abrensch/brouter`, port 17777) — offline routing engine for cycling. OSM segmenty pro střední Evropu, profily: gravel, trekking, fastbike. API proxy přes lighttpd na `tommyq.cz/brouter`.

## Related Repositories

- [tommyq-sport](https://github.com/tommyq86/tommyq-sport) - Cycling activities (Bryton CLI, Strava, import)
- [tommyq-assistant](https://github.com/tommyq86/tommyq-assistant) - SmartHome assistant service
- [tommyq-bash](https://github.com/tommyq86/tommyq-bash) - Universal bash scripts
- [tommyq-python](https://github.com/tommyq86/tommyq-python) - Python utilities

## Services

All services are available via HTTPS with Cloudflare Origin CA certificate:

- `https://tommyq.cz` - Services dashboard
- `https://tommyq.cz/sport/` - Sport activities (token required)
- `https://tommyq.cz/brouter` - BRouter gravel route planner (routing API proxy na leo:17777)
- `https://portainer.tommyq.cz` - Docker management
- `https://radarr.tommyq.cz` - Movies
- `https://sonarr.tommyq.cz` - TV Shows
- `https://seerr.tommyq.cz` - Media requests
- `https://prowlarr.tommyq.cz` - Indexer management
- `https://calibre.tommyq.cz` - Calibre-Web (e-knihy, port 8083)
- `https://audiobookshelf.tommyq.cz` - Audiobookshelf (audioknihy, port 13378)
- `https://filezilla.tommyq.cz` - FTP client (KasmVNC)
- `https://jdownloader.tommyq.cz` - Download manager
- `https://qbittorrent.tommyq.cz` - Torrent client
- `https://plex.tommyq.cz` - Media server
- `https://dsm.tommyq.cz` - Synology DSM

## CA Certificate

Cloudflare Origin CA certificate is available at:
- `http://192.168.2.1/ca.crt`
- `http://router.local/ca.crt` (with local DNS)

Installation on clients:
```bash
# Linux
sudo install-cert  # from tommyq-bash

# Windows
Install-Certificate  # from tommyq-pwsh
```

## Maintenance

### TurrisOS Update

**BEFORE update:**
```bash
ssh turris '/root/scripts/pre-update-backup.sh'
```

**AFTER update:**
```bash
ssh turris '/root/scripts/post-update-restore.sh'
# If configuration is missing:
cd ~/Systém/tommyq-turris && ./deploy.sh
```

### Configuration Backup

```bash
# On Turris
/root/scripts/turris-backup.sh

# Trigger from Leo (cron)
~/Systém/tommyq-turris/scripts/leo-trigger-turris-backup.sh
```

### Memory Monitoring

```bash
ssh turris '/root/scripts/turris-mem-monitor.sh'
```

### Safe Reboot After Update

```bash
ssh turris '/root/scripts/safe-reboot.sh'
```

This script clears updater flags before reboot to prevent the updater from reinstalling updates.
