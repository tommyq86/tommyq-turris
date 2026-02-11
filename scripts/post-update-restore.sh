#!/bin/sh
# Post-update restore script for Turris
# Run this AFTER TurrisOS update

echo "=== Post-Update Restore ==="

# Restore assistant service
echo "1. Restoring assistant service..."
/etc/init.d/assistant enable
/etc/init.d/assistant start

# Check lighttpd configs
echo -e "\n2. Checking lighttpd configurations..."
MISSING=0
for conf in 99-ca-cert.conf 99-tommyq-services.conf 99-tommyq-jdownloader.conf 99-tommyq-dsm.conf 99-tommyq-smarthome.conf; do
    if [ ! -f "/etc/lighttpd/conf.d/$conf" ]; then
        echo "  ⚠ Missing: $conf"
        MISSING=1
    fi
done

if [ $MISSING -eq 1 ]; then
    echo -e "\n⚠ Some configs missing. Run from Leo:"
    echo "  cd ~/Systém/tommyq-turris && ./deploy.sh"
else
    echo "  ✓ All configs present"
fi

# Check scripts
echo -e "\n3. Checking scripts..."
if [ ! -d "/root/scripts" ]; then
    echo "  ⚠ /root/scripts/ missing. Run from Leo:"
    echo "  cd ~/Systém/tommyq-turris && ./deploy.sh"
else
    echo "  ✓ Scripts directory exists"
fi

# Check CA cert
echo -e "\n4. Checking CA certificate..."
if [ ! -f "/www/ca.crt" ]; then
    echo "  ⚠ CA cert missing, downloading..."
    curl -s -o /www/ca.crt https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem
    echo "  ✓ CA cert restored"
else
    echo "  ✓ CA cert present"
fi

# Service status
echo -e "\n5. Service status:"
echo -n "  Lighttpd: "
/etc/init.d/lighttpd status
echo -n "  Assistant: "
/etc/init.d/assistant status

echo -e "\n✓ Post-update check complete"
