#!/bin/sh

# Memory Monitor for Turris
# Monitors RAM and SWAP usage, sends notifications on high usage
# Usage: memory-monitor.sh [--help]

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Memory Monitor - Turris memory usage monitoring"
    echo ""
    echo "Usage: memory-monitor.sh [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help    Show this help message"
    echo ""
    echo "Thresholds:"
    echo "  RAM:  85%"
    echo "  SWAP: 90% (monitoring only, no notifications)"
    echo ""
    echo "Actions on high RAM usage:"
    echo "  - Kill duplicate foris-controller processes"
    echo "  - Clear system caches"
    echo "  - Restart kresd if needed"
    echo "  - Send notification"
    exit 0
fi

THRESHOLD=85
SWAP_THRESHOLD=90
STATE_FILE=/tmp/memory-monitor.state

mem_total=$(awk "/MemTotal/ {print \$2}" /proc/meminfo)
mem_available=$(awk "/MemAvailable/ {print \$2}" /proc/meminfo)
mem_used=$((mem_total - mem_available))
mem_percent=$((mem_used * 100 / mem_total))

swap_total=$(awk "/SwapTotal/ {print \$2}" /proc/meminfo)
swap_free=$(awk "/SwapFree/ {print \$2}" /proc/meminfo)
swap_used=$((swap_total - swap_free))
swap_percent=$((swap_used * 100 / swap_total))

# Check only RAM for notifications (SWAP monitoring disabled)
if [ $mem_percent -ge $THRESHOLD ]; then
    if [ -f $STATE_FILE ]; then
        logger -t memory-monitor "High memory usage: RAM ${mem_percent}%, SWAP ${swap_percent}%"
        
        foris_count=$(ps aux | grep -v grep | grep foris-controller | wc -l)
        if [ $foris_count -gt 1 ]; then
            logger -t memory-monitor "Killing $((foris_count - 1)) duplicate foris-controller"
            ps aux | grep -v grep | grep foris-controller | awk "{print \$2}" | tail -n +2 | xargs kill -9 2>/dev/null
            sleep 2
        fi
        
        sync
        echo 3 > /proc/sys/vm/drop_caches
        
        if ! pgrep kresd > /dev/null && [ $mem_percent -lt 80 ]; then
            logger -t memory-monitor "Restarting kresd"
            /etc/init.d/resolver start >/dev/null 2>&1 &
        fi
        
        # Notification only for RAM usage
        MSG="Vysoke vyuziti pameti: RAM ${mem_percent}%"
        create_notification -s error "$MSG" "High memory usage: RAM ${mem_percent}%"
        rm -f $STATE_FILE
    else
        touch $STATE_FILE
    fi
else
    rm -f $STATE_FILE
fi

# Original condition with SWAP notification (commented out):
# if [ $mem_percent -ge $THRESHOLD ] || [ $swap_percent -ge $SWAP_THRESHOLD ]; then
#     MSG="Vysoke vyuziti pameti: RAM ${mem_percent}%, SWAP ${swap_percent}%"
#     create_notification -s error "$MSG" "High memory usage: RAM ${mem_percent}%, SWAP ${swap_percent}%"
# fi
