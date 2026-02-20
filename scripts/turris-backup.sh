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

# Assistant
echo "Backup: assistant..."
tar czf - -C / srv/assistant 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/assistant.tar.gz"

# Logs
echo "Backup: logs..."
tar czf - -C / srv/log 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/logs.tar.gz"

# Clean up old backups (keep last 7)
echo "Cleaning up old backups..."
ssh tommyq@leo "cd ${BACKUP_DIR} && ls -t | tail -n +8 | xargs -r rm -rf"

echo "=== Backup completed: ${BACKUP_DIR}/${DATE} ==="
