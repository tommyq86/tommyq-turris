#!/bin/sh
# Restore assistant service after TurrisOS update

# Help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    if echo "$LANG" | grep -q "^cs"; then
        cat << EOF
$(basename "$0") - Obnoví assistant službu po aktualizaci

Použití:
    $(basename "$0") [volby]

Volby:
    -h, --help    Zobrazí tuto nápovědu

Popis:
    Zapne a spustí assistant službu
    Zkontroluje lighttpd konfiguraci
EOF
    else
        cat << EOF
$(basename "$0") - Restores assistant service after update

Usage:
    $(basename "$0") [options]

Options:
    -h, --help    Show this help message

Description:
    Enables and starts assistant service
    Checks lighttpd configuration
EOF
    fi
    exit 0
fi

echo 'Checking assistant service...'

# Enable and start service
/etc/init.d/assistant enable
/etc/init.d/assistant start

# Check lighttpd config
if ! grep -q '/smarthome' /etc/lighttpd/conf.d/99-tommyq-smarthome.conf 2>/dev/null; then
    echo 'WARNING: lighttpd config missing /smarthome proxy!'
    echo 'Run: vi /etc/lighttpd/conf.d/99-tommyq-smarthome.conf'
fi

echo 'Done. Service status:'
/etc/init.d/assistant status
