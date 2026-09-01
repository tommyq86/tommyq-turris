#!/usr/bin/env bash
# Deploy lighttpd configurations to Turris router
# Usage: deploy-lighttpd.sh [root@turris]

set -euo pipefail

TURRIS_HOST="${1:-root@turris}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# ------------------------------------------------------------
# Helpers (consistent with main deploy.sh)
# ------------------------------------------------------------
ssh_exec() {
    ssh "$TURRIS_HOST" "$@"
}

scp_to() {
    scp "$1" "$TURRIS_HOST:$2"
}

echo "Deploying lighttpd configurations to $TURRIS_HOST..."

# Clean up legacy configs. Only remove configs that this repo owns and will
# re-deploy below — the sport config (99-tommyq-30-sport.conf) is owned and
# deployed separately by tommyq-sport/deploy.sh, so it must NOT be removed here.
echo "  Cleaning up old configurations..."
ssh_exec "rm -f /etc/lighttpd/conf.d/99-ca-cert.conf"
for conf in "$CONFIGS_DIR"/*.conf; do
    ssh_exec "rm -f /etc/lighttpd/conf.d/$(basename "$conf")"
done

# Copy config files (skip *.template — only generated *.conf is deployed)
for conf in "$CONFIGS_DIR"/*.conf; do
    filename=$(basename "$conf")
    echo "  Copying $filename..."
    scp_to "$conf" "/etc/lighttpd/conf.d/"
done

# Test configuration before restarting
echo "Testing lighttpd configuration..."
ssh_exec "lighttpd -t -f /etc/lighttpd/lighttpd.conf"

# Restart lighttpd
echo "Restarting lighttpd..."
ssh_exec "/etc/init.d/lighttpd restart"

echo "✓ Deployment complete"
