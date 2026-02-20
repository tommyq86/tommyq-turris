#!/bin/bash

# Help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    if [[ "$LANG" =~ ^cs ]]; then
        cat << EOF
$(basename "$0") - Spouští backup Turris routeru z Leo NAS

Použití:
    $(basename "$0") [volby]

Volby:
    -h, --help    Zobrazí tuto nápovědu

Popis:
    Spouští backup max 2x měsíčně (min 14 dní mezi zálohy)
EOF
    else
        cat << EOF
$(basename "$0") - Triggers Turris router backup from Leo NAS

Usage:
    $(basename "$0") [options]

Options:
    -h, --help    Show this help message

Description:
    Runs backup max 2x per month (min 14 days between backups)
EOF
    fi
    exit 0
fi

# Leo Trigger Script - starts backup on turris after leo startup
# Runs max 2x per month

LAST_BACKUP_FILE="/volume1/homes/tommyq/.turris-backup-last"
MIN_DAYS=14

# Check when last backup occurred
if [ -f "$LAST_BACKUP_FILE" ]; then
  LAST_BACKUP=$(cat "$LAST_BACKUP_FILE")
  DAYS_SINCE=$((( $(date +%s) - LAST_BACKUP ) / 86400))
  
  if [ $DAYS_SINCE -lt $MIN_DAYS ]; then
    echo "Last backup was $DAYS_SINCE days ago, skipping (min $MIN_DAYS days)"
    exit 0
  fi
fi

echo "Starting backup on turris..."
if ssh -o ConnectTimeout=10 turris "/root/turris-backup.sh"; then
  date +%s > "$LAST_BACKUP_FILE"
  echo "Backup completed successfully"
else
  echo "Backup failed"
  exit 1
fi
