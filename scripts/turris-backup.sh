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

# Assistant + sport (config, app data, logs) under /srv/tommyq — EXCEPT the
# map tiles (maps/), which are large and change rarely. The tar.gz keeps the
# 7-version rotation for everything small and valuable (activity/data jízdy,
# planner/data routes-users-nogos, config/sport.conf, assistant, logs); the
# tiles get a separate single live mirror below (no point tar'ing GBs of
# rarely-changing tiles into 7 full copies). Code itself comes from git
# (deploy.sh), but it's tiny so we leave it in the tar for a self-contained
# restore.
echo "Backup: /srv/tommyq (excl. maps tiles)..."
tar czf - -C / --exclude='srv/tommyq/sport/maps' srv/tommyq 2>/dev/null \
    | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/srv-tommyq.tar.gz"

# Map tiles: a single live rsync mirror (not in the dated rotation). Tiles are
# regenerable (scripts/maps.sh) and large, so one mirror of the current state
# is enough; rsync transfers only what changed since last run. Kept OUTSIDE the
# per-date dirs so the 7-version cleanup below never touches it.
TILES_MIRROR="/var/services/homes/tommyq/turris-tiles-mirror"
if [ -d /srv/tommyq/sport/maps ]; then
    echo "Backup: map tiles (rsync mirror)..."
    ssh tommyq@leo "mkdir -p ${TILES_MIRROR}"
    rsync -rlt --delete --rsync-path=/usr/bin/rsync \
        /srv/tommyq/sport/maps/ "tommyq@leo:${TILES_MIRROR}/" \
        || echo "WARNING: tiles rsync failed (non-fatal)"
fi

# Clean up old DATED backups (keep last 7). The tiles mirror is a sibling dir,
# not under BACKUP_DIR/<date>, so it is not affected.
echo "Cleaning up old backups..."
ssh tommyq@leo "cd ${BACKUP_DIR} && ls -t | tail -n +8 | xargs -r rm -rf"

echo "=== Backup completed: ${BACKUP_DIR}/${DATE} (+ tiles mirror ${TILES_MIRROR}) ==="
