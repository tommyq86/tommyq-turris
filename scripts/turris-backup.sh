#!/bin/sh
# Turris MOX Backup Script

BACKUP_DIR="/var/services/homes/tommyq/turris-backup"
DATE=$(date +%Y%m%d_%H%M%S)

echo "=== Turris MOX Backup - $(date) ==="

# Kontrola dostupnosti leo
if ! ssh -o ConnectTimeout=5 -o BatchMode=yes tommyq@leo "exit" 2>/dev/null; then
  echo "VAROVÁNÍ: leo není dostupné"
  exit 1
fi

echo "Vytvářím zálohu na leo..."
ssh tommyq@leo "mkdir -p ${BACKUP_DIR}/${DATE}"

# Systémový backup
echo "Backup: system..."
schnapps export - 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/system-backup.tar.gz"

# Konfigurace
echo "Backup: config..."
tar czf - -C / etc/config 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/config.tar.gz"

# SSH klíče
echo "Backup: ssh..."
tar czf - -C / root/.ssh 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/ssh.tar.gz"

# Assistant
echo "Backup: assistant..."
tar czf - -C / srv/assistant 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/assistant.tar.gz"

# Logy
echo "Backup: logs..."
tar czf - -C / srv/log 2>/dev/null | ssh tommyq@leo "cat > ${BACKUP_DIR}/${DATE}/logs.tar.gz"

# Vyčisti staré zálohy (ponechej 7 posledních)
echo "Čistím staré zálohy..."
ssh tommyq@leo "cd ${BACKUP_DIR} && ls -t | tail -n +8 | xargs -r rm -rf"

echo "=== Záloha dokončena: ${BACKUP_DIR}/${DATE} ==="
