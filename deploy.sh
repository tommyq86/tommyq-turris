#!/usr/bin/env bash
# Deploy Turris configuration and scripts
# Usage: deploy.sh [components...] [--host HOST]
# Components: lighttpd, scripts, dashboard, system, sport, garage, activity, brouter, all (default)

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
    sport       Kompletní sport service (activity + brouter + garage)
    activity    Pouze Activity (CGI, index.html, generate_sport_maps)
    brouter     Pouze BRouter (CGI, index.html)
    garage      Pouze Garage
    all         Vše (výchozí, pokud není zadána žádná komponenta)

Volby:
    --host HOST   SSH host (výchozí: root@turris)
    -h, --help    Zobrazí tuto nápovědu

Příklady:
    $(basename "$0")                    # nasadí vše
    $(basename "$0") activity           # jen activity
    $(basename "$0") garage brouter      # garage + brouter
    $(basename "$0") dashboard --host root@192.168.2.1
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
    sport       Full sport service (activity + brouter + garage)
    activity    Only Activity (CGI, index.html, generate_sport_maps)
    brouter     Only BRouter (CGI, index.html)
    garage      Only Garage
    all         Everything (default if no component specified)

Options:
    --host HOST   SSH host (default: root@turris)
    -h, --help    Show this help message

Examples:
    $(basename "$0")                    # deploy everything
    $(basename "$0") activity           # only activity
    $(basename "$0") garage brouter      # garage + brouter
    $(basename "$0") dashboard --host root@192.168.2.1
EOF
            fi
            exit 0
            ;;
        --host)
            TURRIS_HOST="$2"
            shift 2
            ;;
        lighttpd|scripts|dashboard|system|sport|activity|brouter|garage|all)
            COMPONENTS+=("$1")
            shift
            ;;
        *)
            echo "Unknown argument: $1 (use --help for usage)"
            exit 1
            ;;
    esac
done

# Expand 'sport' component into individual components if present
expanded_components=()
for comp in "${COMPONENTS[@]:-}"; do
    if [[ "$comp" == "sport" ]]; then
        expanded_components+=(activity brouter garage)
    else
        expanded_components+=("$comp")
    fi
done
COMPONENTS=("${expanded_components[@]:-}")

# Default to all if no components specified
if [[ ${#COMPONENTS[@]} -eq 0 ]] || [[ " ${COMPONENTS[*]} " == *" all "* ]]; then
    COMPONENTS=(lighttpd scripts dashboard system activity brouter garage)
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

    # Install required modules
    ssh "$TURRIS_HOST" "opkg list-installed | grep -q lighttpd-mod-proxy || opkg install lighttpd-mod-proxy"
    ssh "$TURRIS_HOST" "opkg list-installed | grep -q lighttpd-mod-redirect || opkg install lighttpd-mod-redirect"

    # Disable conflicting Turris configs
    ssh "$TURRIS_HOST" "cd /etc/lighttpd/conf.d && for f in 50-turris-auth.conf 80-*.conf; do [ -f \$f ] && [ ! -f \$f.disabled ] && mv \$f \$f.disabled; done || true"

    # Generate sport config from template with tokens
    SPORT_TOKEN_FILE="/srv/tommyq/sport/config/sport-token.conf"
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
    ./deploy-lighttpd.sh "$TURRIS_HOST"

    # Restart lighttpd
    ssh "$TURRIS_HOST" "/etc/init.d/lighttpd enable && /etc/init.d/lighttpd restart"
    echo "  ✓ Lighttpd deployed and restarted"
    echo ""
fi

# --- SCRIPTS ---
if has_component scripts; then
    echo "▸ Deploying scripts..."
    ssh "$TURRIS_HOST" "mkdir -p /srv/tommyq/scripts/"
    for script in "$SCRIPT_DIR/scripts"/*.sh; do
        filename=$(basename "$script")
        echo "  $filename"
        scp "$script" "$TURRIS_HOST:/srv/tommyq/scripts/"
        ssh "$TURRIS_HOST" "chmod +x /srv/tommyq/scripts/$filename"
    done
    
    # Memory monitor
    echo "  memory-monitor.sh -> /usr/local/bin/"
    scp "$SCRIPT_DIR/scripts/turris-mem-monitor.sh" "$TURRIS_HOST:/usr/local/bin/memory-monitor.sh"
    ssh "$TURRIS_HOST" "chmod +x /usr/local/bin/memory-monitor.sh"
    ssh "$TURRIS_HOST" "crontab -l 2>/dev/null | grep -q memory-monitor || (crontab -l 2>/dev/null; echo '*/5 * * * * /usr/local/bin/memory-monitor.sh') | crontab -"

    # Add cron job for kresd-watchdog
    ssh "$TURRIS_HOST" "crontab -l 2>/dev/null | grep -q kresd-watchdog || (crontab -l 2>/dev/null; echo '*/2 * * * * /srv/tommyq/scripts/kresd-watchdog.sh >/dev/null 2>&1') | crontab -"
    
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

    # Fix kresd init script - prevent empty line in hints.tmp
    ssh "$TURRIS_HOST" "sed -i 's/echo \"\" > \\\$HINTS_CONFIG/> \\\$HINTS_CONFIG/' /etc/init.d/kresd"
    echo "  ✓ Knot Resolver init script patch"

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
" 2>/dev/null || true
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

# --- SPORT SHARED BASE ---
deploy_sport_base() {
    local PYTHON_SPORT="$SCRIPT_DIR/../tommyq-sport"
    local PYTHON_COMMON="$SCRIPT_DIR/../tommyq-sport/common"

    ensure_dir "/srv/tommyq/sport/common"
    ensure_dir "/srv/tommyq/sport/config"

    # Python scripts & common modules
    scp_to "$PYTHON_SPORT/bryton.py" "/srv/tommyq/sport/"
    scp_to "$PYTHON_SPORT/import_activity.py" "/srv/tommyq/sport/"
    scp_dir_to "$PYTHON_COMMON/." "/srv/tommyq/sport/common/"

    # Python modules
    install_python_module_if_missing "websocket"
    install_python_module_if_missing "garmin_fit_sdk"
    install_python_module_if_missing "fitparse"

    # Configs
    [ -f "$HOME/.tommyq/bryton.conf" ] && scp_to "$HOME/.tommyq/bryton.conf" "/root/.tommyq/"
    [ -f "$HOME/.tommyq/sport-token.conf" ] && scp_to "$HOME/.tommyq/sport-token.conf" "/srv/tommyq/sport/config/sport-token.conf"
}

# --- ACTIVITY ---
deploy_activity() {
    echo "▸ Deploying activity service..."
    deploy_sport_base

    local PYTHON_SPORT="$SCRIPT_DIR/../tommyq-sport"

    ensure_dir "/srv/tommyq/sport/activity"
    ensure_dir "/srv/tommyq/sport/activity/cgi"

    # Sport maps generator
    scp_to "$PYTHON_SPORT/activity/generate_sport_maps.py" "/srv/tommyq/sport/activity/"
    ssh_exec "chmod +x /srv/tommyq/sport/activity/generate_sport_maps.py"

    # CGI & Frontend
    scp_to "$PYTHON_SPORT/activity/cgi/sport.cgi" "/srv/tommyq/sport/activity/cgi/sport.cgi"
    ssh_exec "chmod +x /srv/tommyq/sport/activity/cgi/sport.cgi"
    scp_to "$PYTHON_SPORT/activity/index.html" "/srv/tommyq/sport/activity/index.html"

    # Cron
    update_cron "generate_sport_maps.*sync" \
        "*/5 * * * * python3 /srv/tommyq/sport/activity/generate_sport_maps.py sync >/dev/null 2>&1"

    update_cron "generate_sport_maps.*weather" \
        "0 6 * * * python3 /srv/tommyq/sport/activity/generate_sport_maps.py weather >/dev/null 2>&1"

    update_cron "turris-new-device-alert" \
        "*/5 * * * * /srv/tommyq/scripts/turris-new-device-alert.sh >/dev/null 2>&1"

    echo "  ✓ Activity service deployed"
    echo ""
}

if has_component activity; then
    deploy_activity
fi

# --- BROUTER ---
deploy_brouter() {
    echo "▸ Deploying brouter service..."
    deploy_sport_base

    local PYTHON_SPORT="$SCRIPT_DIR/../tommyq-sport"

    ensure_dir "/srv/tommyq/sport/brouter/cgi"
    ensure_dir "/srv/tommyq/sport/brouter/data"

    scp_to "$PYTHON_SPORT/brouter/index.html" "/srv/tommyq/sport/brouter/index.html"
    scp_to "$PYTHON_SPORT/brouter/cgi/bryton-upload.cgi" "/srv/tommyq/sport/brouter/cgi/bryton-upload.cgi"
    scp_to "$PYTHON_SPORT/brouter/cgi/nogos.cgi" "/srv/tommyq/sport/brouter/cgi/nogos.cgi"
    scp_to "$PYTHON_SPORT/brouter/cgi/routes.cgi" "/srv/tommyq/sport/brouter/cgi/routes.cgi"
    ssh_exec "chmod +x /srv/tommyq/sport/brouter/cgi/bryton-upload.cgi /srv/tommyq/sport/brouter/cgi/nogos.cgi /srv/tommyq/sport/brouter/cgi/routes.cgi"

    echo "  ✓ BRouter service deployed"
    echo ""
}

if has_component brouter; then
    deploy_brouter
fi

# --- GARAGE ---
deploy_garage() {
    echo "▸ Deploying garage service..."
    deploy_sport_base

    local PYTHON_SPORT="$SCRIPT_DIR/../tommyq-sport"

    ensure_dir "/srv/tommyq/sport/garage"
    scp_dir_to "$PYTHON_SPORT/garage/." "/srv/tommyq/sport/garage/"

    echo "  ✓ Garage service deployed"
    echo ""
}

if has_component garage; then
    deploy_garage
fi

# --- VERIFY ---
echo "=== Deployment Complete ==="
echo ""
echo -n "  Lighttpd: "
ssh "$TURRIS_HOST" "/etc/init.d/lighttpd status" && echo "✓ running" || echo "⚠ not running"
echo -n "  Assistant: "
ssh "$TURRIS_HOST" "/etc/init.d/assistant status 2>/dev/null" && echo "✓ running" || echo "⚠ not installed/running"