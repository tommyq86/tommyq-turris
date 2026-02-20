#!/bin/bash
# Deploy Turris configuration and scripts

set -e

# Help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    if [[ "$LANG" =~ ^cs ]]; then
        cat << EOF
$(basename "$0") - Nasadí konfiguraci a skripty na Turris router

Použití:
    $(basename "$0") [host] [volby]

Argumenty:
    host          SSH host (výchozí: root@turris)

Volby:
    -h, --help    Zobrazí tuto nápovědu

Popis:
    Nasadí lighttpd konfigurace, skripty, dashboard, systémové
    konfigurace a CA certifikát na Turris router
EOF
    else
        cat << EOF
$(basename "$0") - Deploys configuration and scripts to Turris router

Usage:
    $(basename "$0") [host] [options]

Arguments:
    host          SSH host (default: root@turris)

Options:
    -h, --help    Show this help message

Description:
    Deploys lighttpd configs, scripts, dashboard, system
    configs and CA certificate to Turris router
EOF
    fi
    exit 0
fi

TURRIS_HOST="${1:-root@turris}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Turris Deployment ==="
echo "Target: $TURRIS_HOST"
echo ""

# 1. Install required lighttpd modules
echo "1. Installing required lighttpd modules..."
ssh "$TURRIS_HOST" "opkg list-installed | grep -q lighttpd-mod-proxy || opkg install lighttpd-mod-proxy"
ssh "$TURRIS_HOST" "opkg list-installed | grep -q lighttpd-mod-redirect || opkg install lighttpd-mod-redirect"
echo "  ✓ Modules installed"
echo ""

# 2. Disable conflicting Turris configs
echo "2. Disabling conflicting Turris configs..."
ssh "$TURRIS_HOST" "cd /etc/lighttpd/conf.d && for f in 50-turris-auth.conf 80-*.conf; do [ -f \$f ] && [ ! -f \$f.disabled ] && mv \$f \$f.disabled; done || true"
echo "  ✓ Conflicts resolved"
echo ""

# 3. Deploy lighttpd configs
echo "3. Deploying lighttpd configurations..."
cd "$SCRIPT_DIR/lighttpd"
./deploy.sh "$TURRIS_HOST"
echo ""

# 4. Deploy scripts
echo "4. Deploying scripts..."
ssh "$TURRIS_HOST" "mkdir -p /root/scripts"
for script in "$SCRIPT_DIR/scripts"/*.sh; do
    filename=$(basename "$script")
    echo "  Copying $filename..."
    scp "$script" "$TURRIS_HOST:/root/scripts/"
    ssh "$TURRIS_HOST" "chmod +x /root/scripts/$filename"
done
echo ""

# 5. Deploy dashboard
echo "5. Deploying dashboard..."
ssh "$TURRIS_HOST" "mkdir -p /www/tommyq"
scp "$SCRIPT_DIR/www/index.html" "$TURRIS_HOST:/www/tommyq/"
scp "$SCRIPT_DIR/www/logo.png" "$TURRIS_HOST:/www/tommyq/"
echo "  ✓ Dashboard deployed"
echo ""

# 6. Deploy system configs
echo "6. Deploying system configurations..."
ssh "$TURRIS_HOST" "mkdir -p /etc/updater/conf.d /etc/kresd"
scp "$SCRIPT_DIR/system/no-foris.lua" "$TURRIS_HOST:/etc/updater/conf.d/"
scp "$SCRIPT_DIR/system/kresd-custom.conf" "$TURRIS_HOST:/etc/kresd/custom.conf"
echo "  ✓ Updater config deployed"
echo "  ✓ Knot Resolver config deployed"

# Clean up unnecessary UCI domain entries (DNS is handled via Knot Resolver)
echo "  Cleaning up UCI domain entries..."
ssh "$TURRIS_HOST" "
for i in \$(seq 0 20); do
  uci delete dhcp.@domain[0] 2>/dev/null || break
done
uci commit dhcp
" && echo "  ✓ UCI domains cleaned" || echo "  ⚠ No domains to clean"
echo ""

# 7. Deploy CA certificate
echo "7. Checking CA certificate..."
if ! ssh "$TURRIS_HOST" "test -f /www/ca.crt"; then
    echo "  Downloading Cloudflare Origin CA..."
    ssh "$TURRIS_HOST" "curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem -o /www/ca.crt"
    echo "  ✓ CA certificate installed"
else
    echo "  ✓ CA certificate already exists"
fi
echo ""

# 8. Enable and restart lighttpd
echo "8. Enabling and restarting services..."
ssh "$TURRIS_HOST" "/etc/init.d/lighttpd enable && /etc/init.d/lighttpd restart"
echo "  ✓ Lighttpd restarted"
ssh "$TURRIS_HOST" "/etc/init.d/resolver restart"
echo "  ✓ Resolver restarted"
echo ""

# 9. Verify services
echo "9. Verifying services..."
echo -n "  Lighttpd: "
ssh "$TURRIS_HOST" "/etc/init.d/lighttpd status" && echo "✓ running" || echo "✗ not running"

echo -n "  Assistant: "
ssh "$TURRIS_HOST" "/etc/init.d/assistant status 2>/dev/null" && echo "✓ running" || echo "⚠ not installed/running"
echo ""

echo "=== Deployment Complete ==="
echo ""
echo "Next steps:"
echo "  - Verify services: https://tommyq.cz"
echo "  - Check logs: ssh $TURRIS_HOST 'logread | tail -50'"
echo "  - Test CA cert: curl http://192.168.2.1/ca.crt"
