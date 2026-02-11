# Turris MOX Setup

## Počáteční nastavení

### 1. Lighttpd konfigurace

Nasazení reverse proxy konfigurace:

```bash
cd lighttpd
./deploy.sh
```

### 2. DNS konfigurace

V Turris webovém rozhraní (reForis nebo LuCI):

**Network → DHCP and DNS → Domain Names**

Přidat záznamy pro lokální resolvování:
- `tommyq.cz` → `192.168.2.1`
- `*.tommyq.cz` → `192.168.2.1`

Nebo ručně v `/etc/config/dhcp`:

```
config domain
    option name 'tommyq.cz'
    option ip '192.168.2.1'

config domain
    option name 'portainer.tommyq.cz'
    option ip '192.168.2.1'

# ... další služby
```

### 3. SSL certifikáty

Umístit Cloudflare Origin certifikáty:
- `/etc/ssl/certs/tommyq.crt` - certifikát
- `/etc/ssl/certs/tommyq.key` - privátní klíč

Cloudflare Origin CA root certifikát:
```bash
curl -o /www/ca.crt https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem
```

### 4. Dashboard

Vytvořit `/www/tommyq/index.html` s rozcestníkem služeb.

### 5. Assistant služba (volitelné)

Pro SmartHome webhook:

```bash
# Naklonovat tommyq-assistant
git clone https://github.com/tommyq86/tommyq-assistant.git
cd tommyq-assistant
./install.sh
```

Po TurrisOS update obnovit:
```bash
./scripts/restore-assistant.sh
```

## Údržba

### Záloha konfigurace

Automatická záloha na Synology NAS:

Na Turrisu:
```bash
./scripts/turris-backup.sh
```

Trigger z Leo (cron):
```bash
./scripts/leo-trigger-turris-backup.sh
```

### Monitoring paměti

```bash
./scripts/turris-mem-monitor.sh
```

### Update lighttpd konfigurace

1. Upravit soubory v `lighttpd/configs/`
2. Commitnout změny
3. Nasadit: `./lighttpd/deploy.sh`

## Troubleshooting

### Lighttpd nefunguje

```bash
# Test konfigurace
lighttpd -t -f /etc/lighttpd/lighttpd.conf

# Restart
/etc/init.d/lighttpd restart

# Logy
tail -f /var/log/lighttpd/error.log
```

### DNS nefunguje

```bash
# Test DNS
nslookup tommyq.cz 192.168.2.1

# Restart dnsmasq
/etc/init.d/dnsmasq restart
```

### Assistant služba nefunguje

```bash
# Status
/etc/init.d/assistant status

# Restart
/etc/init.d/assistant restart

# Logy
logread | grep assistant
```
