#!/bin/sh
# Safe reboot that clears updater flags
# Use this instead of plain 'reboot' after updates

# Help
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    if echo "$LANG" | grep -q "^cs"; then
        cat << EOF
$(basename "$0") - Bezpečný restart po aktualizaci

Použití:
    $(basename "$0") [volby]

Volby:
    -h, --help    Zobrazí tuto nápovědu

Popis:
    Vyčistí updater flagy před restartem
    Použij místo obyčejného 'reboot' po aktualizacích
EOF
    else
        cat << EOF
$(basename "$0") - Safe reboot after update

Usage:
    $(basename "$0") [options]

Options:
    -h, --help    Show this help message

Description:
    Clears updater flags before reboot
    Use instead of plain 'reboot' after updates
EOF
    fi
    exit 0
fi

echo "Clearing updater reboot flag..."
rm -f /usr/share/updater/need_reboot

echo "Rebooting in 5 seconds..."
sleep 5
reboot
