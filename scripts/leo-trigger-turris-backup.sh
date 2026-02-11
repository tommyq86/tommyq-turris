#!/bin/bash

# Help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat << EOF
$(basename "$0")

Použití:
    $(basename "$0") [options]

Volby:
    -h, --help    Zobrazí tuto nápovědu

EOF
    exit 0
fi

# Leo Trigger Script - spustí backup na turris po startu leo
# Spouští se max 2x měsíčně

LAST_BACKUP_FILE="/volume1/homes/tommyq/.turris-backup-last"
MIN_DAYS=14

# Kontrola, kdy byl poslední backup
if [ -f "$LAST_BACKUP_FILE" ]; then
  LAST_BACKUP=$(cat "$LAST_BACKUP_FILE")
  DAYS_SINCE=$((( $(date +%s) - LAST_BACKUP ) / 86400))
  
  if [ $DAYS_SINCE -lt $MIN_DAYS ]; then
    echo "Poslední backup byl před $DAYS_SINCE dny, přeskakuji (min $MIN_DAYS dnů)"
    exit 0
  fi
fi

echo "Spouštím backup na turris..."
if ssh -o ConnectTimeout=10 turris "/root/turris-backup.sh"; then
  date +%s > "$LAST_BACKUP_FILE"
  echo "Backup dokončen úspěšně"
else
  echo "Backup selhal"
  exit 1
fi
