#!/usr/bin/env bash
# Deploy Turris configuration and scripts
# Usage: deploy.sh [components...] [--host HOST]
# Components: lighttpd, scripts, dashboard, system, all (default)
#
# Note: sport service (activity + brouter + garage) is deployed separately
# from tommyq-sport — run `~/Systém/tommyq-sport/deploy.sh`.

set -euo pipefail

TURRIS_HOST="root@turris"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS=()

# ------------------------------------------------------------
# Logging & Helpers
# ------------------------------------------------------------
log() {
    echo "[$(date +'%F %T')] $*"
}

ssh_exec() {
    ssh "$TURRIS_HOST" "$@"
}

scp_to() {
    scp "$1" "$TURRIS_HOST:$2"
}

scp_dir_to() {
    scp -r "$1" "$TURRIS_HOST:$2"
}

ensure_dir() {
    ssh_exec "mkdir -p $1"
}

install_python_module_if_missing() {
    local module="$1"
    ssh_exec "python3 -c 'import $module' 2>/dev/null" || {
        local path
        path=$(python3 -c "import $module, os; print(os.path.dirname($module.__file__))")
        scp_dir_to "$path" "/usr/lib/python3.11/site-packages/"
        log "Installed Python module: $module"
    }
}

# Ensure a set of lighttpd modules is installed (idempotent, single opkg pass).
# Each lighttpd-mod-* package drops its own /etc/lighttpd/conf.d/*.conf that
# registers the module via `server.modules += (...)`.
install_lighttpd_modules() {
    local modules=("$@")
    local pkgs=""
    for m in "${modules[@]}"; do
        pkgs="$pkgs lighttpd-mod-$m"
    done

    # Compute the set of missing packages remotely, then install in one call.
    ssh_exec "
        installed=\$(opkg list-installed | cut -d' ' -f1)
        missing=''
        for p in $pkgs; do
            echo \"\$installed\" | grep -qx \"\$p\" || missing=\"\$missing \$p\"
        done
        if [ -n \"\$missing\" ]; then
            echo \"  Installing lighttpd modules:\$missing\"
            opkg update >/dev/null 2>&1 || true
            opkg install \$missing
        else
            echo '  All required lighttpd modules already installed'
        fi
    "
}

update_cron() {
    local pattern="$1"
    local entry="$2"

    local tmp
    tmp=$(mktemp)

    ssh_exec "crontab -l 2>/dev/null" > "$tmp" || true

    if ! grep -q "$pattern" "$tmp"; then
        echo "$entry" >> "$tmp"
        scp_to "$tmp" "/tmp/newcron"
        ssh_exec "crontab /tmp/newcron"
        log "Cron updated: $entry"
    fi

    rm -f "$tmp"
}

# ------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            if [[ "${LANG:-}" =~ ^cs ]]; then
                cat << EOF
$(basename "$0") - Nasadí konfiguraci a skripty na Turris router

Použití:
    $(basename "$0") [komponenty...] [--host HOST]

Komponenty:
    lighttpd    Lighttpd moduly, konfigurace a reverse proxy
    scripts     Shell skripty (/srv/tommyq/scripts/)
    dashboard   Webový dashboard (/www/tommyq/)
    system      DNS, kresd, dnsmasq, hosts, CA certifikát
    all         Vše (výchozí, pokud není zadána žádná komponenta)

Volby:
    --host HOST   SSH host (výchozí: root@turris)
    -h, --help    Zobrazí tuto nápovědu

Příklady:
    $(basename "$0")                    # nasadí vše
    $(basename "$0") lighttpd           # jen lighttpd
    $(basename "$0") dashboard --host root@192.168.2.1

Poznámka: sport service (activity + brouter + garage) se nasazuje samostatně
    z tommyq-sport: ~/Systém/tommyq-sport/deploy.sh
EOF
            else
                cat << EOF
$(basename "$0") - Deploys configuration and scripts to Turris router

Usage:
    $(basename "$0") [components...] [--host HOST]

Components:
    lighttpd    Lighttpd modules, configs and reverse proxy
    scripts     Shell scripts (/srv/tommyq/scripts/)
    dashboard   Web dashboard (/www/tommyq/)
    system      DNS, kresd, dnsmasq, hosts, CA certificate
    all         Everything (default if no component specified)

Options:
    --host HOST   SSH host (default: root@turris)
    -h, --help    Show this help message

Examples:
    $(basename "$0")                    # deploy everything
    $(basename "$0") lighttpd           # only lighttpd
    $(basename "$0") dashboard --host root@192.168.2.1

Note: sport service (activity + brouter + garage) is deployed separately
    from tommyq-sport: ~/Systém/tommyq-sport/deploy.sh
EOF
            fi
            exit 0
            ;;
        --host)
            TURRIS_HOST="$2"
            shift 2
            ;;
        lighttpd|scripts|dashboard|system|all)
            COMPONENTS+=("$1")
            shift
            ;;
        sport|activity|brouter|garage)
            echo "Error: '$1' is no longer deployed from tommyq-turris." >&2
            echo "Use: ~/Systém/tommyq-sport/deploy.sh $1" >&2
            exit 1
            ;;
        *)
            echo "Unknown argument: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# Default to all if no components specified
if [[ ${#COMPONENTS[@]} -eq 0 ]] || [[ " ${COMPONENTS[*]} " == *" all "* ]]; then
    COMPONENTS=(lighttpd scripts dashboard system)
fi

# Check if component is requested
has_component() {
    [[ " ${COMPONENTS[*]:-} " == *" $1 "* ]]
}

echo "=== Turris Deployment ==="
echo "Target: $TURRIS_HOST"
echo "Components: ${COMPONENTS[*]}"
echo ""

# --- LIGHTTPD ---
if has_component lighttpd; then
    echo "▸ Deploying lighttpd..."

    # Install required modules (idempotent). tommyq configs use:
    #   proxy    - reverse proxy (SmartHome, media/tools, brouter API)
    #   redirect - HTTP->HTTPS, sport shortcut redirects
    #   alias    - dashboard, ca.crt, sport static paths
    #   openssl  - HTTPS/TLS
    #   auth     - sport admin authentication
    #   authn_pam- PAM backend for sport admin auth
    #   cgi      - sport.cgi / brouter cgi
    #   setenv   - custom request headers on proxied services
    # NB: sport service is deployed from tommyq-sport, but its lighttpd config
    #     relies on these modules, so they are installed here.
    install_lighttpd_modules proxy redirect alias openssl auth authn_pam cgi setenv

    # Disable conflicting Turris configs
    ssh_exec "cd /etc/lighttpd/conf.d && for f in 50-turris-auth.conf 80-*.conf; do [ -f \$f ] && [ ! -f \$f.disabled ] && mv \$f \$f.disabled; done || true"

    cd "$SCRIPT_DIR/lighttpd"
    ./deploy-lighttpd.sh "$TURRIS_HOST"

    # Restart lighttpd
    ssh_exec "/etc/init.d/lighttpd enable && /etc/init.d/lighttpd restart"
    echo "  ✓ Lighttpd deployed and restarted"
    echo ""
fi

# --- SCRIPTS ---
if has_component scripts; then
    echo "▸ Deploying scripts..."
    ensure_dir "/srv/tommyq/scripts/"
    for script in "$SCRIPT_DIR/scripts"/*.sh; do
        filename=$(basename "$script")
        echo "  $filename"
        scp_to "$script" "/srv/tommyq/scripts/"
        ssh_exec "chmod +x /srv/tommyq/scripts/$filename"
    done

    # Memory monitor
    echo "  memory-monitor.sh -> /usr/local/bin/"
    scp_to "$SCRIPT_DIR/scripts/turris-mem-monitor.sh" "/usr/local/bin/memory-monitor.sh"
    ssh_exec "chmod +x /usr/local/bin/memory-monitor.sh"
    update_cron "memory-monitor" \
        "*/5 * * * * /usr/local/bin/memory-monitor.sh"

    # kresd-watchdog
    update_cron "kresd-watchdog" \
        "*/2 * * * * /srv/tommyq/scripts/kresd-watchdog.sh >/dev/null 2>&1"

    # new device alert
    update_cron "turris-new-device-alert" \
        "*/5 * * * * /srv/tommyq/scripts/turris-new-device-alert.sh >/dev/null 2>&1"

    echo "  ✓ Scripts deployed"
    echo ""
fi

# --- DASHBOARD ---
if has_component dashboard; then
    echo "▸ Deploying dashboard..."
    ensure_dir "/www/tommyq"
    scp_dir_to "$SCRIPT_DIR/www/." "/www/tommyq/"
    echo "  ✓ Dashboard deployed"
    echo ""
fi

# --- SYSTEM ---
if has_component system; then
    echo "▸ Deploying system configurations..."
    ensure_dir "/etc/updater/conf.d /etc/kresd"

    scp_to "$SCRIPT_DIR/system/no-foris.lua" "/etc/updater/conf.d/"
    echo "  ✓ Updater config"

    scp_to "$SCRIPT_DIR/system/kresd-custom.conf" "/etc/kresd/custom.conf"
    # Idempotent: only commit if the value actually changes
    ssh_exec "
        cur=\$(uci -q get resolver.kresd.include_config || echo '')
        if [ \"\$cur\" != '/etc/kresd/custom.conf' ]; then
            uci set resolver.kresd=kresd
            uci set resolver.kresd.include_config='/etc/kresd/custom.conf'
            uci commit resolver
        fi
    "
    echo "  ✓ Knot Resolver config"

    # Fix kresd init script - prevent empty line in hints.tmp (idempotent sed)
    ssh_exec "grep -q 'echo \"\" > \\\$HINTS_CONFIG' /etc/init.d/kresd && sed -i 's/echo \"\" > \\\$HINTS_CONFIG/> \\\$HINTS_CONFIG/' /etc/init.d/kresd || true"
    echo "  ✓ Knot Resolver init script patch"

    scp_to "$SCRIPT_DIR/system/hosts" "/etc/hosts"
    echo "  ✓ Hosts file"

    ensure_dir "/etc/dnsmasq.d"
    scp_to "$SCRIPT_DIR/system/dnsmasq-local-domains.conf" "/etc/dnsmasq.d/local-domains.conf"
    # Idempotent: only commit if dnsmasq port differs
    ssh_exec "
        cur=\$(uci -q get dhcp.@dnsmasq[0].port || echo '')
        if [ \"\$cur\" != '0' ]; then
            uci set dhcp.@dnsmasq[0].port='0'
            uci commit dhcp
        fi
    "
    echo "  ✓ Dnsmasq local domains"

    # Clean up unnecessary UCI domain entries
    ssh_exec "
for i in \$(seq 0 20); do
  uci delete dhcp.@domain[0] 2>/dev/null || break
done
uci commit dhcp
" 2>/dev/null || true
    echo "  ✓ UCI domains cleaned"

    # DNS rebinding exception for plex.direct (idempotent)
    ssh_exec "
uci get dhcp.@dnsmasq[0].rebind_domain 2>/dev/null | grep -q plex.direct || { uci add_list dhcp.@dnsmasq[0].rebind_domain='plex.direct'; uci commit dhcp; }
"
    echo "  ✓ plex.direct rebind exception"

    # Disable IPv6 RA/DHCPv6 — no upstream IPv6 (WAN proto has no IPv6).
    # Stops odhcpd spamming "No default route present, setting ra_lifetime to 0!".
    # Idempotent: only commit + restart if something actually changes.
    ssh_exec "
changed=0
for net in lan guest_turris; do
    uci -q get dhcp.\$net >/dev/null || continue
    [ \"\$(uci -q get dhcp.\$net.ra)\" != 'disabled' ]     && { uci set dhcp.\$net.ra='disabled'; changed=1; }
    [ \"\$(uci -q get dhcp.\$net.dhcpv6)\" != 'disabled' ] && { uci set dhcp.\$net.dhcpv6='disabled'; changed=1; }
    uci -q get dhcp.\$net.ra_flags >/dev/null && { uci -q delete dhcp.\$net.ra_flags; changed=1; }
done
if [ \"\$changed\" = 1 ]; then
    uci commit dhcp
    /etc/init.d/odhcpd restart
fi
"
    echo "  ✓ IPv6 RA/DHCPv6 disabled (no upstream IPv6)"

    # CA certificate
    if ! ssh_exec "test -f /www/ca.crt"; then
        ssh_exec "curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem -o /www/ca.crt"
        echo "  ✓ CA certificate installed"
    else
        echo "  ✓ CA certificate exists"
    fi

    # Restart DNS services
    ssh_exec "/etc/init.d/resolver restart"
    ssh_exec "/etc/init.d/dnsmasq restart"
    echo "  ✓ DNS services restarted"
    echo ""
fi

# --- VERIFY ---
echo "=== Deployment Complete ==="
echo ""
echo -n "  Lighttpd: "
ssh_exec "/etc/init.d/lighttpd status" && echo "✓ running" || echo "⚠ not running"
echo -n "  Assistant: "
ssh_exec "/etc/init.d/assistant status 2>/dev/null" && echo "✓ running" || echo "⚠ not installed/running"