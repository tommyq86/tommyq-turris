#!/bin/bash
# Deploy Turris configuration and scripts
# Usage: deploy.sh [components...] [--host HOST]
# Components: lighttpd, scripts, dashboard, system, sport, all (default)

set -e

TURRIS_HOST="root@turris"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPONENTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            if [[ "$LANG" =~ ^cs ]]; then
                cat << EOF
$(basename "$0") - Nasadí konfiguraci a skripty na Turris router

Použití:
    $(basename "$0") [komponenty...] [--host HOST]

Komponenty:
    lighttpd    Lighttpd moduly, konfigurace a reverse proxy
    scripts     Shell skripty (/root/scripts/)
    dashboard   Webový dashboard (/www/tommyq/)
    system      DNS, kresd, dnsmasq, hosts, CA certifikát
    sport       Sport service (CGI, Python skripty, activity.html)
    all         Vše (výchozí, pokud není zadána žádná komponenta)

Volby:
    --host HOST   SSH host (výchozí: root@turris)
    -h, --help    Zobrazí tuto nápovědu

Příklady:
    $(basename "$0")                    # nasadí vše
    $(basename "$0") sport              # jen sport service
    $(basename "$0") lighttpd sport     # lighttpd + sport
    $(basename "$0") dashboard --host root@192.168.2.1
EOF
            else
                cat << EOF
$(basename "$0") - Deploys configuration and scripts to Turris router

Usage:
    $(basename "$0") [components...] [--host HOST]

Components:
    lighttpd    Lighttpd modules, configs and reverse proxy
    scripts     Shell scripts (/root/scripts/)
    dashboard   Web dashboard (/www/tommyq/)
    system      DNS, kresd, dnsmasq, hosts, CA certificate
    sport       Sport service (CGI, Python scripts, activity.html)
    all         Everything (default if no component specified)

Options:
    --host HOST   SSH host (default: root@turris)
    -h, --help    Show this help message

Examples:
    $(basename "$0")                    # deploy everything
    $(basename "$0") sport              # only sport service
    $(basename "$0") lighttpd sport     # lighttpd + sport
    $(basename "$0") dashboard --host root@192.168.2.1
EOF
            fi
            exit 0
            ;;
        --host)
            TURRIS_HOST="$2"
            shift 2
            ;;
        lighttpd|scripts|dashboard|system|sport|all)
            COMPONENTS+=("$1")
            shift
            ;;
        *)
            echo "Unknown argument: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# Default to all if no components specified
if [[ ${#COMPONENTS[@]} -eq 0 ]] || [[ " ${COMPONENTS[*]} " == *" all "* ]]; then
    COMPONENTS=(lighttpd scripts dashboard system sport)
fi

# Check if component is requested
has_component() {
    [[ " ${COMPONENTS[*]} " == *" $1 "* ]]
}

echo "=== Turris Deployment ==="
echo "Target: $TURRIS_HOST"
echo "Components: ${COMPONENTS[*]}"
echo ""

# --- LIGHTTPD ---
if has_component lighttpd; then
    echo "▸ Deploying lighttpd..."

    # Install required modules
    ssh "$TURRIS_HOST" "opkg list-installed | grep -q lighttpd-mod-proxy || opkg install lighttpd-mod-proxy"
    ssh "$TURRIS_HOST" "opkg list-installed | grep -q lighttpd-mod-redirect || opkg install lighttpd-mod-redirect"

    # Disable conflicting Turris configs
    ssh "$TURRIS_HOST" "cd /etc/lighttpd/conf.d && for f in 50-turris-auth.conf 80-*.conf; do [ -f \$f ] && [ ! -f \$f.disabled ] && mv \$f \$f.disabled; done || true"

    # Generate sport config from template with tokens
    SPORT_TOKEN_FILE="$HOME/.tommyq/sport-token.conf"
    if [ -f "$SPORT_TOKEN_FILE" ]; then
        ADMIN_TOKEN=$(grep '^TOKEN=' "$SPORT_TOKEN_FILE" | cut -d= -f2)
        PUBLIC_TOKEN=$(grep '^PUBLIC_TOKEN=' "$SPORT_TOKEN_FILE" | cut -d= -f2)
        sed -e "s/__ADMIN_TOKEN__/$ADMIN_TOKEN/g" -e "s/__PUBLIC_TOKEN__/$PUBLIC_TOKEN/g" \
            "$SCRIPT_DIR/lighttpd/configs/99-tommyq-30-sport.conf.template" \
            > "$SCRIPT_DIR/lighttpd/configs/99-tommyq-30-sport.conf"
    else
        echo "  ⚠ Missing $SPORT_TOKEN_FILE — sport config will have no tokens!"
    fi

    cd "$SCRIPT_DIR/lighttpd"
    ./deploy.sh "$TURRIS_HOST"

    # Restart lighttpd
    ssh "$TURRIS_HOST" "/etc/init.d/lighttpd enable && /etc/init.d/lighttpd restart"
    echo "  ✓ Lighttpd deployed and restarted"
    echo ""
fi

# --- SCRIPTS ---
if has_component scripts; then
    echo "▸ Deploying scripts..."
    ssh "$TURRIS_HOST" "mkdir -p /root/scripts"
    for script in "$SCRIPT_DIR/scripts"/*.sh; do
        filename=$(basename "$script")
        echo "  $filename"
        scp "$script" "$TURRIS_HOST:/root/scripts/"
        ssh "$TURRIS_HOST" "chmod +x /root/scripts/$filename"
    done
    echo "  ✓ Scripts deployed"
    echo ""
fi

# --- DASHBOARD ---
if has_component dashboard; then
    echo "▸ Deploying dashboard..."
    ssh "$TURRIS_HOST" "mkdir -p /www/tommyq"
    scp -r "$SCRIPT_DIR/www/"* "$TURRIS_HOST:/www/tommyq/"
    echo "  ✓ Dashboard deployed"
    echo ""
fi

# --- SYSTEM ---
if has_component system; then
    echo "▸ Deploying system configurations..."
    ssh "$TURRIS_HOST" "mkdir -p /etc/updater/conf.d /etc/kresd"

    scp "$SCRIPT_DIR/system/no-foris.lua" "$TURRIS_HOST:/etc/updater/conf.d/"
    echo "  ✓ Updater config"

    scp "$SCRIPT_DIR/system/kresd-custom.conf" "$TURRIS_HOST:/etc/kresd/custom.conf"
    ssh "$TURRIS_HOST" "uci set resolver.kresd=kresd; uci set resolver.kresd.include_config='/etc/kresd/custom.conf'; uci commit resolver"
    echo "  ✓ Knot Resolver config"

    scp "$SCRIPT_DIR/system/hosts" "$TURRIS_HOST:/etc/hosts"
    echo "  ✓ Hosts file"

    ssh "$TURRIS_HOST" "mkdir -p /etc/dnsmasq.d"
    scp "$SCRIPT_DIR/system/dnsmasq-local-domains.conf" "$TURRIS_HOST:/etc/dnsmasq.d/local-domains.conf"
    ssh "$TURRIS_HOST" "uci set dhcp.@dnsmasq[0].port='0'; uci commit dhcp"
    echo "  ✓ Dnsmasq local domains"

    # Clean up unnecessary UCI domain entries
    ssh "$TURRIS_HOST" "
for i in \$(seq 0 20); do
  uci delete dhcp.@domain[0] 2>/dev/null || break
done
uci commit dhcp
" 2>/dev/null
    echo "  ✓ UCI domains cleaned"

    # DNS rebinding exception for plex.direct
    ssh "$TURRIS_HOST" "
uci get dhcp.@dnsmasq[0].rebind_domain 2>/dev/null | grep -q plex.direct || uci add_list dhcp.@dnsmasq[0].rebind_domain='plex.direct'
uci commit dhcp
"
    echo "  ✓ plex.direct rebind exception"

    # CA certificate
    if ! ssh "$TURRIS_HOST" "test -f /www/ca.crt"; then
        ssh "$TURRIS_HOST" "curl -fsSL https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem -o /www/ca.crt"
        echo "  ✓ CA certificate installed"
    else
        echo "  ✓ CA certificate exists"
    fi

    # Restart DNS services
    ssh "$TURRIS_HOST" "/etc/init.d/resolver restart"
    ssh "$TURRIS_HOST" "/etc/init.d/dnsmasq restart"
    echo "  ✓ DNS services restarted"
    echo ""
fi

# --- SPORT ---
if has_component sport; then
    echo "▸ Deploying sport service..."
    PYTHON_SPORT="$SCRIPT_DIR/../tommyq-python/sport"
    PYTHON_COMMON="$SCRIPT_DIR/../tommyq-python/common"

    # Python scripts
    ssh "$TURRIS_HOST" "mkdir -p /root/sport /root/common /root/scripts"
    scp "$PYTHON_SPORT/bryton.py" "$TURRIS_HOST:/root/sport/"
    scp "$PYTHON_SPORT/import_activity.py" "$TURRIS_HOST:/root/sport/"
    scp "$PYTHON_COMMON"/*.py "$TURRIS_HOST:/root/common/"

    # Sport shell script
    scp "$SCRIPT_DIR/scripts/generate-sport-maps.sh" "$TURRIS_HOST:/root/scripts/"
    ssh "$TURRIS_HOST" "chmod +x /root/scripts/generate-sport-maps.sh"

    # Install Python modules if missing
    ssh "$TURRIS_HOST" "python3 -c 'import websocket' 2>/dev/null" || {
        WSPATH=$(python3 -c "import websocket, os; print(os.path.dirname(websocket.__file__))")
        scp -r "$WSPATH" "$TURRIS_HOST:/usr/lib/python3.11/site-packages/"
    }
    ssh "$TURRIS_HOST" "python3 -c 'import garmin_fit_sdk' 2>/dev/null" || {
        FITPATH=$(python3 -c "import garmin_fit_sdk, os; print(os.path.dirname(garmin_fit_sdk.__file__))")
        scp -r "$FITPATH" "$TURRIS_HOST:/usr/lib/python3.11/site-packages/"
    }
    ssh "$TURRIS_HOST" "python3 -c 'import fitparse' 2>/dev/null" || {
        FPPATH=$(python3 -c "import fitparse, os; print(os.path.dirname(fitparse.__file__))")
        scp -r "$FPPATH" "$TURRIS_HOST:/usr/lib/python3.11/site-packages/"
    }

    # Configs
    ssh "$TURRIS_HOST" "mkdir -p /root/.tommyq"
    [ -f "$HOME/.tommyq/bryton.conf" ] && scp "$HOME/.tommyq/bryton.conf" "$TURRIS_HOST:/root/.tommyq/"
    [ -f "$HOME/.tommyq/sport-token.conf" ] && scp "$HOME/.tommyq/sport-token.conf" "$TURRIS_HOST:/root/.tommyq/"

    # CGI scripts
    ssh "$TURRIS_HOST" "mkdir -p /srv/tommyq/sport/cgi"
    for cgi in "$SCRIPT_DIR/scripts"/sport-*.cgi; do
        name=$(basename "$cgi" | sed 's/^sport-//')
        scp "$cgi" "$TURRIS_HOST:/srv/tommyq/sport/cgi/$name"
        ssh "$TURRIS_HOST" "chmod +x /srv/tommyq/sport/cgi/$name"
    done
    scp "$SCRIPT_DIR/www/sport/activity.html" "$TURRIS_HOST:/srv/tommyq/sport/activity.html"

    # Cron
    ssh "$TURRIS_HOST" "crontab -l 2>/dev/null | grep -q generate-sport-maps || (crontab -l 2>/dev/null; echo '0 6 * * * /root/scripts/generate-sport-maps.sh >/dev/null 2>&1') | crontab -"
    ssh "$TURRIS_HOST" "crontab -l 2>/dev/null | grep -q turris-new-device-alert || (crontab -l 2>/dev/null; echo '*/5 * * * * /root/scripts/turris-new-device-alert.sh >/dev/null 2>&1') | crontab -"
    echo "  ✓ Sport service deployed"
    echo ""
fi

# --- VERIFY ---
echo "=== Deployment Complete ==="
echo ""
echo -n "  Lighttpd: "
ssh "$TURRIS_HOST" "/etc/init.d/lighttpd status" && echo "✓ running" || echo "⚠ not running"
echo -n "  Assistant: "
ssh "$TURRIS_HOST" "/etc/init.d/assistant status 2>/dev/null" && echo "✓ running" || echo "⚠ not installed/running"
