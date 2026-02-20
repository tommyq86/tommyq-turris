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

### 5. Assistant Service (Optional)
Setup SmartHome assistant:

```bash
/root/scripts/setup_smart_home.sh
```

## Maintenance

### Configuration Backup
The script `scripts/turris-backup.sh` handles automated backups of `/etc` and other important paths.

### Memory Monitoring
`scripts/turris-mem-monitor.sh` monitors memory usage and restarts services if necessary.

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
