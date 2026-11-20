#!/bin/sh
# Turris MOX Backup Script

# Help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    if echo "$LANG" | grep -q "^cs"; then
        cat << EOF
$(basename "$0") - Zálohuje Turris router na NAS

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
$(basename "$0") - Backs up Turris router to the NAS

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

# Where the backups go is NOT in git: /srv/tommyq/config/backup.conf (deployed from
# ~/.tommyq/backup.conf, see backup.conf.example) sets NAS_SSH (user@host or an ssh alias)
# and optionally BACKUP_DIR.
CONF="${BACKUP_CONF:-/srv/tommyq/config/backup.conf}"
[ -f "$CONF" ] && . "$CONF"
if [ -z "${NAS_SSH:-}" ]; then
    echo "ERROR: NAS_SSH is not set - create $CONF (see backup.conf.example)" >&2
    exit 1
fi
BACKUP_DIR="${BACKUP_DIR:-turris-backup}"   # relative to the NAS user's home
nas() { ssh "$NAS_SSH" "$@"; }

DATE=$(date +%Y%m%d_%H%M%S)

echo "=== Turris MOX Backup - $(date) ==="

# Check NAS availability
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes "$NAS_SSH" "exit" 2>/dev/null; then
  echo "WARNING: NAS is not available"
  exit 1
fi

echo "Creating backup on the NAS..."
nas "mkdir -p ${BACKUP_DIR}/${DATE}"

# System backup
echo "Backup: system..."
schnapps export - 2>/dev/null | nas "cat > ${BACKUP_DIR}/${DATE}/system-backup.tar.gz"

# Configuration
echo "Backup: config..."
tar czf - -C / etc/config 2>/dev/null | nas "cat > ${BACKUP_DIR}/${DATE}/config.tar.gz"

# SSH keys
echo "Backup: ssh..."
tar czf - -C / root/.ssh 2>/dev/null | nas "cat > ${BACKUP_DIR}/${DATE}/ssh.tar.gz"

# Assistant + sport (config, app data, logs) under /srv/tommyq. The map tiles
# are NO LONGER here — they moved to the NAS `maps` Docker service
# (/volume1/docker/maps/store), so turris holds no tile store to back up. The
# tar.gz keeps the 7-version rotation for everything small and valuable
# (activity/data jízdy, planner/data routes-users-nogos, config/sport.conf,
# assistant, logs). Code itself comes from git (deploy.sh), but it's tiny so we
# leave it in the tar for a self-contained restore. The maps/ exclude is kept
# as a belt-and-suspenders guard in case a stale store dir lingers on turris.
echo "Backup: /srv/tommyq (excl. maps tiles)..."
tar czf - -C / --exclude='srv/tommyq/sport/maps' srv/tommyq 2>/dev/null \
    | nas "cat > ${BACKUP_DIR}/${DATE}/srv-tommyq.tar.gz"

# NB: the tile store is no longer backed up from turris — it lives on the NAS now
# (the `maps` Docker service volume, /volume1/docker/maps/store) and is covered
# by the NAS's own storage. Self-rendered layers (osm, cyclosm) are regenerable on
# the desktop (render-tiles.sh); the pre-fetched layers were migrated to the NAS.

# Clean up old DATED backups (keep last 7).
echo "Cleaning up old backups..."
nas "cd ${BACKUP_DIR} && ls -t | tail -n +8 | xargs -r rm -rf"

echo "=== Backup completed on the NAS: ${BACKUP_DIR}/${DATE} ==="
