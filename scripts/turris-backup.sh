#!/bin/sh
# Turris MOX Backup Script

# Help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    if echo "$LANG" | grep -q "^cs"; then
        cat << EOF
$(basename "$0") - Zálohuje Turris router na Leo NAS

Použití:
    $(basename "$0") [volby]

Volby:
    -h, --help    Zobrazí tuto nápovědu

Popis:
    Zálohuje systém, konfiguraci, SSH klíče, assistant a logy
    Uchovává 7 posledních záloh
EOF
    else
        cat << EOF
$(basename "$0") - Backs up Turris router to Leo NAS

Usage:
    $(basename "$0") [options]

Options:
    -h, --help    Show this help message

Description:
    Backs up system, config, SSH keys, assistant and logs
    Keeps last 7 backups
EOF
    fi
    exit 0
fi

BACKUP_DIR="/var/services/homes/tommyq/turris-backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== Turris MOX Backup - $(date) ==="

# Check leo availability
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes tommyq@leo "exit" 2>/dev/null; then
  echo "WARNING: leo is not available"
  exit 1
fi

echo "Creating backup on leo..."
ssh tommyq@leo "mkdir -p ${BACKUP_DIR}/${DATE}"

# System backup
echo "Backup: system..."
schnapps export - 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/system-backup.tar.gz"

# Configuration
echo "Backup: config..."
tar czf - -C / etc/config 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/config.tar.gz"

# SSH keys
echo "Backup: ssh..."
tar czf - -C / root/.ssh 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/ssh.tar.gz"

# Assistant + sport (config, app data, logs) under /srv/tommyq. The map tiles
# are NO LONGER here — they moved to the leo `maps` Docker service
# (/volume1/docker/maps/store), so turris holds no tile store to back up. The
# tar.gz keeps the 7-version rotation for everything small and valuable
# (activity/data jízdy, planner/data routes-users-nogos, config/sport.conf,
# assistant, logs). Code itself comes from git (deploy.sh), but it's tiny so we
# leave it in the tar for a self-contained restore. The maps/ exclude is kept
# as a belt-and-suspenders guard in case a stale store dir lingers on turris.
echo "Backup: /srv/tommyq (excl. maps tiles)..."
tar czf - -C / --exclude='srv/tommyq/sport/maps' srv/tommyq 2>/dev/null \
    | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/srv-tommyq.tar.gz"

# NB: the tile store is no longer backed up from turris — it lives on leo now
# (the `maps` Docker service volume, /volume1/docker/maps/store) and is covered
# by leo's own storage. Self-rendered layers (osm, cyclosm) are regenerable on
# tiger (render-tiles-tiger.sh); the pre-fetched layers were migrated to leo
# (scripts/migrate-tiles-to-leo.sh in tommyq-sport).

# Clean up old DATED backups (keep last 7).
echo "Cleaning up old backups..."
ssh tommyq@leo "cd ${BACKUP_DIR} && ls -t | tail -n +8 | xargs -r rm -rf"

echo "=== Backup completed: ${BACKUP_DIR}/${DATE} ==="
