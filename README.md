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
├── lighttpd/
│   ├── configs/              # Lighttpd reverse proxy configuration
│   │   ├── 99-ca-cert.conf          # CA certificate download
│   │   ├── 99-tommyq-base.conf      # Base domain + HTTP redirect
│   │   ├── 99-tommyq-services.conf  # Standard services (Portainer, *arr, qBittorrent)
│   │   ├── 99-tommyq-filezilla.conf # FileZilla (KasmVNC + WebSocket)
│   │   ├── 99-tommyq-jdownloader.conf # JDownloader
│   │   ├── 99-tommyq-download.conf  # Synology Download Station
│   │   ├── 99-tommyq-dsm.conf       # Synology DSM
│   │   ├── 99-tommyq-plex.conf      # Plex Media Server
│   │   └── 99-tommyq-smarthome.conf # SmartHome webhook
│   └── deploy.sh             # Deployment script
├── www/
│   └── index.html            # Services dashboard
├── scripts/
│   ├── restore-assistant.sh         # Restore assistant after TurrisOS update
│   ├── turris-backup.sh             # Backup Turris to Synology NAS
│   ├── leo-trigger-turris-backup.sh # Trigger backup from Leo
│   └── turris-mem-monitor.sh        # Memory monitoring (RAM/SWAP)
├── system/
│   ├── kresd-custom.conf     # Knot Resolver - local domain overrides
│   ├── dnsmasq.conf.example  # DNS configuration (legacy reference)
│   └── no-foris.lua          # Updater config - disable Foris web interface
└── docs/
    └── setup.md              # Setup documentation
```

**Note:** DNS configuration is managed via Knot Resolver (`/etc/kresd/custom.conf`). Local domains (`*.tommyq.cz`) resolve to `192.168.2.1`. The `dnsmasq.conf.example` file is a legacy reference.

## Deployment

### Complete deployment

```bash
./deploy.sh [root@turris]
```

Deploys:
- Lighttpd configuration
- Scripts to `/root/scripts/`
- System configuration (updater, Knot Resolver)
- CA certificate (if missing)
- Cleans up legacy UCI domain entries
- Verifies running services

### Lighttpd configuration only

```bash
cd lighttpd
./deploy.sh [root@turris]
```

### Scripts

Scripts are deployed via main `deploy.sh` or manually as needed.

## Related Repositories

- [tommyq-assistant](https://github.com/tommyq86/tommyq-assistant) - SmartHome assistant service
- [tommyq-bash](https://github.com/tommyq86/tommyq-bash) - Universal bash scripts
- [tommyq-python](https://github.com/tommyq86/tommyq-python) - Python utilities

## Services

All services are available via HTTPS with Cloudflare Origin CA certificate:

- `https://example.com` - Services dashboard
- `https://portainer.example.com` - Docker management
- `https://radarr.example.com` - Movies
- `https://sonarr.example.com` - TV Shows
- `https://overseerr.example.com` - Media requests
- `https://prowlarr.example.com` - Indexer management
- `https://filezilla.example.com` - FTP client (KasmVNC)
- `https://jdownloader.example.com` - Download manager
- `https://qbittorrent.example.com` - Torrent client
- `https://plex.example.com` - Media server
- `https://dsm.example.com` - Synology DSM

## CA Certificate

Cloudflare Origin CA certificate is available at:
- `http://192.168.1.1/ca.crt`
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
# If configuration is missing, from Leo:
cd ~/Scripts/tommyq-turris && ./deploy.sh
```

### Configuration Backup

```bash
# On Turris
/root/scripts/turris-backup.sh

# Trigger from Leo (cron)
~/Scripts/tommyq-turris/scripts/leo-trigger-turris-backup.sh
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
