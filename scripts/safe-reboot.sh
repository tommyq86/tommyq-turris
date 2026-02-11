#!/bin/sh
# Safe reboot that clears updater flags
# Use this instead of plain 'reboot' after updates

echo "Clearing updater reboot flag..."
rm -f /usr/share/updater/need_reboot

echo "Rebooting in 5 seconds..."
sleep 5
reboot
