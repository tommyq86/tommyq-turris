#!/bin/sh
# Detect devices with dynamic DHCP lease (no static lease configured)
# Sends notification via Turris notification system (email)

LEASE_FILE="/tmp/dhcp.leases"
KNOWN_FILE="/root/scripts/.known_devices"

[ -f "$KNOWN_FILE" ] || touch "$KNOWN_FILE"

static_macs=$(uci show dhcp | grep '\.mac=' | sed "s/.*='\(.*\)'/\1/" | tr 'a-f' 'A-F')

while read -r _ts mac ip hostname _rest; do
    mac_upper=$(echo "$mac" | tr 'a-f' 'A-F')
    echo "$static_macs" | grep -qi "$mac_upper" && continue
    grep -q "$mac_upper" "$KNOWN_FILE" && continue

    echo "$mac_upper $ip $hostname $(date +%F_%T)" >> "$KNOWN_FILE"

    create_notification -s news "Nové zařízení v síti" \
        "Hostname: ${hostname:-(neznámý)}, IP: $ip, MAC: $mac_upper"
    NOTIFY=1

done < "$LEASE_FILE"

[ "${NOTIFY:-0}" = "1" ] && /usr/bin/notifier
