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
│   │   ├── 99-tommyq-00-base.conf          # Base domain, HTTP redirect, SmartHome proxy, sport redirects
│   │   ├── 99-tommyq-10-media.conf         # Media Services (Plex, Seerr, *arr, Calibre-Web, Audiobookshelf)
│   │   └── 99-tommyq-20-tools.conf         # Tools & Downloading (DSM, qBit, etc.)
│   └── deploy-lighttpd.sh              # Lighttpd-only deployment
├── www/                       # Services dashboard (deployed to /www/tommyq/)
│   ├── index.html             # Dashboard page (service icons via dashboard-icons + Iconify MDI CDN)
│   ├── logo.png               # Dashboard header logo
│   └── carbon.png             # Dashboard background
├── scripts/                   # Deployed to /srv/tommyq/scripts/
│   ├── turris-backup.sh              # Backup Turris to Synology NAS
│   ├── leo-trigger-turris-backup.sh  # Trigger backup from Leo
│   ├── turris-mem-monitor.sh         # Memory monitoring (RAM/SWAP)
│   ├── turris-new-device-alert.sh    # New device notification
│   ├── srv-mount-check.sh            # Alert if /srv drops off its USB flash drive (→ SD fallback)
│   ├── pre-update-backup.sh          # Pre-TurrisOS update backup
│   ├── post-update-restore.sh        # Post-TurrisOS update restore
│   ├── safe-reboot.sh                # Safe reboot (clear updater flags)
│   └── kresd-watchdog.sh             # Monitoring and restart kresd on failure
├── system/
│   ├── kresd-custom.conf      # Knot Resolver - local domain overrides
│   ├── dnsmasq-local-domains.conf  # Dnsmasq local domain resolution
│   ├── hosts                  # Custom hosts file
│   ├── dnsmasq.conf.example   # DNS configuration (legacy reference)
│   └── no-foris.lua           # Updater config - disable Foris web interface
└── docs/
    └── setup.md               # Setup documentation
```

**Note:** The sport service (`sport.tommyq.cz` — activity, planner, garage) lives entirely in the
[tommyq-sport](https://github.com/tommyq86/tommyq-sport) repository, including its lighttpd config
(`99-tommyq-30-sport.conf`). It is deployed separately via `~/Systém/tommyq-sport/deploy.sh`.
This repo only installs the lighttpd modules the sport config relies on (via `deploy.sh lighttpd`).

**Note:** DNS configuration is managed via Knot Resolver (`/etc/kresd/custom.conf`). Local domains (`*.tommyq.cz`) resolve to `192.168.2.1`.

## Deployment

### Selective deployment (recommended)

```bash
./deploy.sh <components...> [--host root@turris]
```

Components:
- `lighttpd` — modules (auto-installed via opkg), configs, reverse proxy (restarts lighttpd)
- `scripts` — shell scripts to `/srv/tommyq/scripts/` (+ memory monitor, kresd-watchdog, new-device-alert, srv-mount-check cron)
- `dashboard` — web dashboard (`/www/tommyq/`)
- `system` — DNS, kresd, dnsmasq, hosts, CA cert, kresd init script fix (restarts DNS services)

The sport service (activity, planner, garage) is deployed separately from
[tommyq-sport](https://github.com/tommyq86/tommyq-sport): `~/Systém/tommyq-sport/deploy.sh`.

Examples:
```bash
./deploy.sh lighttpd           # deploy lighttpd modules + configs
./deploy.sh scripts            # deploy scripts + cron jobs
./deploy.sh dashboard          # deploy web dashboard
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

The sport service (`sport.tommyq.cz` — activity viewer, route planner, bike garage)
is fully owned by the [tommyq-sport](https://github.com/tommyq86/tommyq-sport) repository:
frontend, CGI, Python code, its lighttpd config (`99-tommyq-30-sport.conf`) and deployment.

Deploy it with:
```bash
~/Systém/tommyq-sport/deploy.sh          # activity + planner + garage + lighttpd config
```

This Turris repo only provides the shared infrastructure the sport config depends on:
lighttpd modules (`auth`, `cgi`, `authn_pam`, `proxy`, `setenv`, …), the base config
(`var.nas_ip`, HTTP→HTTPS, `sport.tommyq.cz` routing) and DNS. Install/refresh them with
`./deploy.sh lighttpd`.

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
- `https://sport.tommyq.cz/activity/` - Sport activities (token required)
- `https://sport.tommyq.cz/planner/` - Gravel route planner (BRouter routing API proxy na leo:17777)
- `https://sport.tommyq.cz/garage/` - Bike garage
- `https://portainer.tommyq.cz` - Docker management
- `https://actualbudget.tommyq.cz` - Accounting
- `https://dozzle.tommyq.cz` - Docker logs viewer
- `https://radarr.tommyq.cz` - Movies
- `https://sonarr.tommyq.cz` - TV Shows
- `https://lidarr.tommyq.cz` - Music
- `https://seerr.tommyq.cz` - Media requests
- `https://prowlarr.tommyq.cz` - Indexer management
- `https://calibre.tommyq.cz` - Calibre-Web (e-knihy, port 8083)
- `https://audiobookshelf.tommyq.cz` - Audiobookshelf (audioknihy, port 13378)
- `https://filezilla.tommyq.cz` - FTP client (KasmVNC)
- `https://jdownloader.tommyq.cz` - Download manager
- `https://qbittorrent.tommyq.cz` - Torrent client
- `https://download.tommyq.cz` - Synology Download Station
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
ssh turris '/srv/tommyq/scripts/pre-update-backup.sh'
```

**AFTER update:**
```bash
ssh turris '/srv/tommyq/scripts/post-update-restore.sh'
# If configuration is missing:
cd ~/Systém/tommyq-turris && ./deploy.sh
```

### Configuration Backup

```bash
# On Turris
/srv/tommyq/scripts/turris-backup.sh

# Trigger from Leo (cron)
~/Systém/tommyq-turris/scripts/leo-trigger-turris-backup.sh
```

### Memory Monitoring

```bash
ssh turris '/srv/tommyq/scripts/turris-mem-monitor.sh'
```

### Safe Reboot After Update

```bash
ssh turris '/srv/tommyq/scripts/safe-reboot.sh'
```

This script clears updater flags before reboot to prevent the updater from reinstalling updates.
