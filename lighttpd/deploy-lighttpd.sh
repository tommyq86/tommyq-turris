#!/bin/bash
# Deploy lighttpd configurations to Turris router

set -e

TURRIS_HOST="${1:-root@turris}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"

echo "Deploying lighttpd configurations to $TURRIS_HOST..."

# Clean up old configurations
echo "  Cleaning up old configurations..."
ssh "$TURRIS_HOST" "rm -f /etc/lighttpd/conf.d/99-ca-cert.conf /etc/lighttpd/conf.d/99-tommyq-*.conf"

# Copy all config files
for conf in "$CONFIGS_DIR"/*.conf; do
    filename=$(basename "$conf")
    echo "  Copying $filename..."
    scp "$conf" "$TURRIS_HOST:/etc/lighttpd/conf.d/"
done

# Test configuration
echo "Testing lighttpd configuration..."
ssh "$TURRIS_HOST" "lighttpd -t -f /etc/lighttpd/lighttpd.conf"

# Restart lighttpd
echo "Restarting lighttpd..."
ssh "$TURRIS_HOST" "/etc/init.d/lighttpd restart"

echo "✓ Deployment complete"
