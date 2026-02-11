# tommyq-turris

Konfigurace a skripty pro Turris MOX router.

## Struktura

```
├── lighttpd/
│   ├── configs/              # Lighttpd reverse proxy konfigurace
│   │   ├── 99-ca-cert.conf          # CA certifikát download
│   │   ├── 99-tommyq-base.conf      # Base doména + HTTP redirect
│   │   ├── 99-tommyq-services.conf  # Standardní služby (Portainer, *arr, qBittorrent)
│   │   ├── 99-tommyq-filezilla.conf # FileZilla (KasmVNC + WebSocket)
│   │   ├── 99-tommyq-jdownloader.conf # JDownloader
│   │   ├── 99-tommyq-download.conf  # Synology Download Station
│   │   ├── 99-tommyq-dsm.conf       # Synology DSM
│   │   ├── 99-tommyq-plex.conf      # Plex Media Server
│   │   └── 99-tommyq-smarthome.conf # SmartHome webhook
│   └── deploy.sh             # Skript pro nasazení konfigurace
├── scripts/
│   ├── restore-assistant.sh         # Restore assistant po TurrisOS update
│   ├── turris-backup.sh             # Záloha Turris na Synology NAS
│   ├── leo-trigger-turris-backup.sh # Trigger zálohy z Leo
│   └── turris-mem-monitor.sh        # Monitoring paměti (RAM/SWAP)
├── system/
│   └── dnsmasq.conf.example  # DNS konfigurace pro lokální resolvování
└── docs/
    └── setup.md              # Dokumentace nastavení
```

## Nasazení

### Kompletní deployment

```bash
./deploy.sh [root@turris]
```

Nasadí:
- Lighttpd konfigurace
- Skripty do `/root/scripts/`
- CA certifikát (pokud chybí)
- Ověří běžící služby

### Pouze lighttpd konfigurace

```bash
cd lighttpd
./deploy.sh [root@turris]
```

### Skripty

Skripty se nasazují přes hlavní `deploy.sh` nebo ručně podle potřeby.

## Související repozitáře

- [tommyq-assistant](https://github.com/tommyq86/tommyq-assistant) - SmartHome assistant služba
- [tommyq-bash](https://github.com/tommyq86/tommyq-bash) - Univerzální bash skripty
- [tommyq-python](https://github.com/tommyq86/tommyq-python) - Python utility

## Služby

Všechny služby jsou dostupné přes HTTPS s Cloudflare Origin CA certifikátem:

- `https://tommyq.cz` - Dashboard služeb
- `https://portainer.tommyq.cz` - Docker management
- `https://radarr.tommyq.cz` - Filmy
- `https://sonarr.tommyq.cz` - Seriály
- `https://overseerr.tommyq.cz` - Media requests
- `https://prowlarr.tommyq.cz` - Indexer management
- `https://filezilla.tommyq.cz` - FTP client (KasmVNC)
- `https://jdownloader.tommyq.cz` - Download manager
- `https://qbittorrent.tommyq.cz` - Torrent client
- `https://plex.tommyq.cz` - Media server
- `https://dsm.tommyq.cz` - Synology DSM

## CA Certifikát

Cloudflare Origin CA certifikát je dostupný na:
- `http://192.168.2.1/ca.crt`
- `http://tommyq.cz/ca.crt` (s lokálním DNS)

Instalace na klientech:
```bash
# Linux
sudo install-tommyq-cert  # z tommyq-bash

# Windows
Install-TommyqCertificate  # z tommyq-pwsh
```

