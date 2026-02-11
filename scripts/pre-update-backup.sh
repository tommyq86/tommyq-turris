#!/bin/sh
# Pre-update backup script for Turris
# Run this BEFORE TurrisOS update

echo "=== Pre-Update Backup ==="

# Create snapshot
echo "Creating system snapshot..."
schnapps create -t pre-update "Before TurrisOS update $(date +%Y-%m-%d)"

# Backup to NAS
echo "Backing up to NAS..."
/root/scripts/turris-backup.sh

# List snapshots
echo -e "\nCurrent snapshots:"
schnapps list

echo -e "\n✓ Backup complete. Safe to update now."
echo "After update, run: /root/scripts/restore-assistant.sh"
