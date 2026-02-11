#!/bin/sh
# Restore assistant service after TurrisOS update

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
