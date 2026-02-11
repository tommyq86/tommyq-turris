#!/bin/bash
# Deploy Turris configuration and scripts

set -e

TURRIS_HOST="${1:-root@turris}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Turris Deployment ==="
echo "Target: $TURRIS_HOST"
echo ""

# 1. Deploy lighttpd configs
echo "1. Deploying lighttpd configurations..."
cd "$SCRIPT_DIR/lighttpd"
./deploy.sh "$TURRIS_HOST"
echo ""

# 2. Deploy scripts
echo "2. Deploying scripts..."
ssh "$TURRIS_HOST" "mkdir -p /root/scripts"
for script in "$SCRIPT_DIR/scripts"/*.sh; do
    filename=$(basename "$script")
    echo "  Copying $filename..."
    scp "$script" "$TURRIS_HOST:/root/scripts/"
    ssh "$TURRIS_HOST" "chmod +x /root/scripts/$filename"
done
echo ""

# 3. Deploy dashboard
echo "3. Deploying dashboard..."
ssh "$TURRIS_HOST" "mkdir -p /www/tommyq"
scp "$SCRIPT_DIR/www/index.html" "$TURRIS_HOST:/www/tommyq/"
echo "  ✓ Dashboard deployed"
echo ""

# 4. Deploy CA certificate
echo "4. Checking CA certificate..."
if ! ssh "$TURRIS_HOST" "test -f /www/ca.crt"; then
    echo "  Downloading Cloudflare Origin CA..."
    ssh "$TURRIS_HOST" "curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem -o /www/ca.crt"
    echo "  ✓ CA certificate installed"
else
    echo "  ✓ CA certificate already exists"
fi
echo ""

# 5. Verify services
echo "5. Verifying services..."
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
