#!/bin/sh
# Pre-update backup script for Turris
# Run this BEFORE TurrisOS update
# Note: Turris creates snapshots automatically, this just backs up to NAS

echo "=== Pre-Update Backup ==="

# Backup to NAS
echo "Backing up to NAS..."
/root/scripts/turris-backup.sh

echo -e "\n✓ Backup complete. Safe to update now."
echo "After update, run: /root/scripts/post-update-restore.sh"
