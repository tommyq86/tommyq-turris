#!/bin/sh

# Kresd Watchdog for Turris
# Monitors kresd service and restarts it if not running
# Usage: kresd-watchdog.sh [--help]

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    if echo "$LANG" | grep -q "^cs"; then
        cat << EOF
$(basename "$0") - Sleduje kresd službu a restartuje ji při potřebě

Použití:
    $(basename "$0") [volby]

Volby:
    -h, --help    Zobrazí tuto nápovědu

Funkce:
    - Kontroluje, zda běží kresd proces
    - Kontroluje, zda kresd odpovídá na DNS dotazy
    - Restartuje kresd při problémech
    - Loguje události do syslog
EOF
    else
        cat << EOF
$(basename "$0") - Monitors kresd service and restarts if needed

Usage:
    $(basename "$0") [options]

Options:
    -h, --help    Show this help message

Functions:
    - Check if kresd process is running
    - Check if kresd responds to DNS queries
    - Restart kresd on problems
    - Log events to syslog
EOF
    fi
    exit 0
fi

LOCK_FILE="/var/run/kresd-watchdog.lock"

# Exit if already running
if [ -f "$LOCK_FILE" ]; then
    PID=$(cat "$LOCK_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        exit 0
    else
        rm -f "$LOCK_FILE"
    fi
fi

# Create lock file
echo $$ > "$LOCK_FILE"
trap "rm -f $LOCK_FILE" EXIT

# Check if kresd process is running
if ! pgrep kresd > /dev/null; then
    logger -t kresd-watchdog "Kresd process not found, starting service"
    service kresd start
    sleep 10
fi

# Check if DNS is responding (test with localhost query)
if ! nslookup localhost 127.0.0.1 > /dev/null 2>&1; then
    logger -t kresd-watchdog "DNS not responding, restarting kresd"
    service kresd restart
    sleep 10
    
    # Verify restart worked
    if pgrep kresd > /dev/null && nslookup localhost 127.0.0.1 > /dev/null 2>&1; then
        logger -t kresd-watchdog "Kresd successfully restarted"
    else
        logger -t kresd-watchdog "Failed to restart kresd, manual intervention needed"
    fi
fi

rm -f "$LOCK_FILE"