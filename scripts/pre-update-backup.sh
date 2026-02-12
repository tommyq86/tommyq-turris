#!/bin/sh
# Pre-update backup script for Turris
# Run this BEFORE TurrisOS update
# Note: Turris creates snapshots automatically, this just backs up to NAS

# Help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    if echo "$LANG" | grep -q "^cs"; then
        cat << EOF
$(basename "$0") - Záloha před aktualizací TurrisOS

Použití:
    $(basename "$0") [volby]

Volby:
    -h, --help    Zobrazí tuto nápovědu

Popis:
    Spusť PŘED aktualizací TurrisOS
    Po aktualizaci spusť: post-update-restore.sh
EOF
    else
        cat << EOF
$(basename "$0") - Backup before TurrisOS update

Usage:
    $(basename "$0") [options]

Options:
    -h, --help    Show this help message

Description:
    Run BEFORE TurrisOS update
    After update, run: post-update-restore.sh
EOF
    fi
    exit 0
fi

echo "=== Pre-Update Backup ==="

# Backup to NAS
echo "Backing up to NAS..."
/root/scripts/turris-backup.sh

echo -e "\n✓ Backup complete. Safe to update now."
echo "After update, run: /root/scripts/post-update-restore.sh"
