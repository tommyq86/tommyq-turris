# Turris Configuration & Setup

Documentation for custom configuration and scripts on Turris Omnia.

## Initial Setup

### 1. SSH Access
Ensure SSH access is enabled and keys are authorized.

### 2. Custom Scripts
Deploy scripts from this repository to `/root/scripts`:

```bash
./deploy.sh
```

### 3. SSL Certificates
Install root CA and certificates for local services:

```bash
/root/scripts/install-tommyq-cert.sh
```

### 4. Lighttpd Configuration
Copy configurations from `lighttpd/configs/` to `/etc/lighttpd/conf.d/`.

### 5. Wake-on-LAN for the NAS (dashboard CGI + loading screen)
`deploy.sh cgi` installs `cgi/wol.cgi` and copies `~/.tommyq/wol.conf` (not in git) to
`/srv/tommyq/config/wol.conf` on the router. The file needs the MAC and the address of the NAS, one `key=value`
per line (the same file the `wol` helper on the desktop uses):

```
nas=aa:bb:cc:dd:ee:ff
nas_ip=192.168.2.4
```

Optional keys: `nas_label`, `nas_broadcast`, `nas_alive_port`, `routing_ports`, `lan_cidr`
(see the README, "Wake-on-LAN"). Without this file `wol.cgi` can't wake the NAS and the loading
screen shown for NAS services only waits.

### 6. Assistant Service (Optional)
Setup SmartHome assistant:

```bash
/root/scripts/setup_smart_home.sh
```

## Maintenance

### Configuration Backup
The script `scripts/turris-backup.sh` handles automated backups of `/etc` and other important paths.
It needs `/srv/tommyq/config/backup.conf` on the router (`NAS_SSH=user@host`); create `~/.tommyq/backup.conf` from
`scripts/backup.conf.example` and `deploy.sh scripts` installs it.

### Memory Monitoring
`scripts/turris-mem-monitor.sh` monitors memory usage and restarts services if necessary.

### DNS Monitoring
`scripts/kresd-watchdog.sh` monitors kresd DNS service and restarts it if not running or not responding. Runs every 2 minutes via cron.

## Troubleshooting

### Assistant service not working
Check if the Python service is running:

```bash
ps | grep app.py
```

Check logs:

```bash
logread -f | grep assistant
```
