#!/bin/sh
# Verify /srv is mounted from the dedicated USB flash drive (btrfs LABEL=srv).
#
# /srv holds all tommyq data (sport tile store, activity data, backups). It
# lives on a USB 3.0 flash drive mounted via UCI fstab. If the drive drops off
# (disconnect / power glitch), /srv falls back to the SD-card root filesystem,
# which is small and NOT where the data belongs — silent data-loss risk for new
# writes. This check alerts via the Turris notification system (email) so it
# can be re-seated.
#
# Runs from cron. Uses Turris' own create_notification (NOT notify.py).
# State file prevents re-notifying every run while it stays disconnected.

SRV_UUID="f94d7f9c-caca-460f-aed6-b8ad8a7e7a35"   # btrfs LABEL=srv flash drive
STATE="/tmp/.srv_mount_alerted"

# Source device currently backing /srv (e.g. /dev/sda or /dev/mmcblk0p1).
srv_dev=$(awk '$2=="/srv"{print $1}' /proc/mounts | tail -1)

# Resolve the expected device from the UUID.
want_dev=$(blkid -U "$SRV_UUID" 2>/dev/null)

if [ -n "$srv_dev" ] && [ "$srv_dev" = "$want_dev" ]; then
    # Healthy: /srv is on the flash drive. Clear any prior alert state.
    rm -f "$STATE"
    exit 0
fi

# Not mounted from the flash drive → alert once (until it recovers).
[ -f "$STATE" ] && exit 0
touch "$STATE"

create_notification -s error \
    "/srv NENÍ na USB flashce! Data /srv (mapové dlaždice, aktivity, zálohy) mají běžet z USB disku (LABEL=srv), ale /srv je teď na '${srv_dev:-nic}' místo '${want_dev:-USB}'. Flashka se nejspíš odpojila — zkontroluj a znovu připoj, jinak hrozí zaplnění SD karty a ztráta nových zápisů." \
    "/srv is NOT on the USB flash drive! /srv data (map tiles, activities, backups) must run from the USB disk (LABEL=srv), but /srv is currently on '${srv_dev:-none}' instead of '${want_dev:-USB}'. The drive likely disconnected — re-seat it, otherwise the SD card may fill up and new writes be lost."

/usr/bin/notifier
