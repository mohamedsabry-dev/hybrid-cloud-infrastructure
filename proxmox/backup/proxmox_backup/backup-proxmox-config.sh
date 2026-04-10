#!/bin/bash
#===============================================================================
# Proxmox Configuration Backup Script
#===============================================================================
# Backs up Proxmox VE configuration files for disaster recovery.
# This does NOT backup VM/LXC data - use vzdump for that.
#
# Location: /root/scripts/backup-proxmox-config.sh (on Proxmox host)
# Usage: /root/scripts/backup-proxmox-config.sh
# Run on: Each Proxmox host (pve-dev, pve-prod)
#
# Backup stored on: NAS via NFS (nas-backups storage)
#
# CRON SETUP (Thursday & Saturday at 9 PM):
#   crontab -e
#   # Add this line:
#   0 21 * * 4,6 /root/scripts/backup-proxmox-config.sh >> /var/log/backup-proxmox-config.log 2>&1
#
# Schedule Reasoning:
#   - Thursday 9 PM: Before weekend work - ensures config backup before major changes
#   - Saturday 9 PM: After weekend work - captures any changes made during weekend
#   - Matches vzdump backup schedule (thu,sat 21:00)
#   - Environment not running 24/7, so backups timed when system is known to be up
#
#===============================================================================

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
HOSTNAME=$(hostname)
BACKUP_DIR="/tmp/proxmox-config-${HOSTNAME}-${TIMESTAMP}"
BACKUP_FILE="proxmox-config-${HOSTNAME}-${TIMESTAMP}.tar.gz"

# NAS backup destination (Proxmox NFS mount)
NAS_BACKUP_PATH="/mnt/pve/nas-backups/dump"

echo "=== Proxmox Config Backup - ${HOSTNAME} ==="
echo "Timestamp: ${TIMESTAMP}"
echo ""

# Create backup directory
mkdir -p "${BACKUP_DIR}"

#-------------------------------------------------------------------------------
# Core Proxmox Configuration
#-------------------------------------------------------------------------------
echo "[1/9] Backing up /etc/pve..."
cp -a /etc/pve "${BACKUP_DIR}/"

#-------------------------------------------------------------------------------
# Network Configuration
#-------------------------------------------------------------------------------
echo "[2/9] Backing up network config..."
mkdir -p "${BACKUP_DIR}/network"
cp /etc/network/interfaces "${BACKUP_DIR}/network/"
cp /etc/hosts "${BACKUP_DIR}/network/"
cp /etc/hostname "${BACKUP_DIR}/network/"
[ -f /etc/resolv.conf ] && cp /etc/resolv.conf "${BACKUP_DIR}/network/"

#-------------------------------------------------------------------------------
# Storage Configuration
#-------------------------------------------------------------------------------
echo "[3/9] Backing up storage config..."
mkdir -p "${BACKUP_DIR}/storage"
cp /etc/fstab "${BACKUP_DIR}/storage/"
[ -d /etc/lvm ] && cp -a /etc/lvm "${BACKUP_DIR}/storage/"
# ZFS pool info (if ZFS is used)
zpool list > "${BACKUP_DIR}/storage/zpool-list.txt" 2>/dev/null || true
zpool status > "${BACKUP_DIR}/storage/zpool-status.txt" 2>/dev/null || true

#-------------------------------------------------------------------------------
# Boot & Kernel Configuration
#-------------------------------------------------------------------------------
echo "[4/9] Backing up boot/kernel config..."
mkdir -p "${BACKUP_DIR}/boot"
[ -f /etc/default/grub ] && cp /etc/default/grub "${BACKUP_DIR}/boot/"
[ -f /etc/modules ] && cp /etc/modules "${BACKUP_DIR}/boot/"
[ -d /etc/modprobe.d ] && cp -a /etc/modprobe.d "${BACKUP_DIR}/boot/"
[ -f /etc/sysctl.conf ] && cp /etc/sysctl.conf "${BACKUP_DIR}/boot/"
[ -d /etc/sysctl.d ] && cp -a /etc/sysctl.d "${BACKUP_DIR}/boot/"

#-------------------------------------------------------------------------------
# APT Sources
#-------------------------------------------------------------------------------
echo "[5/9] Backing up apt sources..."
mkdir -p "${BACKUP_DIR}/apt"
[ -f /etc/apt/sources.list ] && cp /etc/apt/sources.list "${BACKUP_DIR}/apt/"
[ -d /etc/apt/sources.list.d ] && cp -a /etc/apt/sources.list.d "${BACKUP_DIR}/apt/"

#-------------------------------------------------------------------------------
# SSH & Access
#-------------------------------------------------------------------------------
echo "[6/9] Backing up SSH config..."
mkdir -p "${BACKUP_DIR}/ssh"
[ -f /etc/ssh/sshd_config ] && cp /etc/ssh/sshd_config "${BACKUP_DIR}/ssh/"
[ -f /root/.ssh/authorized_keys ] && cp /root/.ssh/authorized_keys "${BACKUP_DIR}/ssh/"

#-------------------------------------------------------------------------------
# Cron Jobs
#-------------------------------------------------------------------------------
echo "[7/9] Backing up cron jobs..."
mkdir -p "${BACKUP_DIR}/cron"
crontab -l > "${BACKUP_DIR}/cron/root-crontab.txt" 2>/dev/null || true
[ -d /etc/cron.d ] && cp -a /etc/cron.d "${BACKUP_DIR}/cron/"

#-------------------------------------------------------------------------------
# Custom Systemd Services
#-------------------------------------------------------------------------------
echo "[8/9] Backing up systemd services..."
mkdir -p "${BACKUP_DIR}/systemd"
cp /etc/systemd/system/*.service "${BACKUP_DIR}/systemd/" 2>/dev/null || true
systemctl list-unit-files --state=enabled > "${BACKUP_DIR}/systemd/enabled.txt"

#-------------------------------------------------------------------------------
# System Info
#-------------------------------------------------------------------------------
echo "[9/9] Capturing system info..."
cat > "${BACKUP_DIR}/SYSTEM-INFO.txt" << EOF
Backup Date: $(date)
Hostname: ${HOSTNAME}
Proxmox: $(pveversion 2>/dev/null)
Kernel: $(uname -r)

=== VMs ===
$(qm list 2>/dev/null || echo "None")

=== LXCs ===
$(pct list 2>/dev/null || echo "None")

=== Storage ===
$(pvesm status 2>/dev/null)

=== Network ===
$(ip -br addr)
EOF

#-------------------------------------------------------------------------------
# Create Archive & Copy to NAS
#-------------------------------------------------------------------------------
echo ""
echo "Creating archive..."
cd /tmp
tar -czf "${BACKUP_FILE}" "proxmox-config-${HOSTNAME}-${TIMESTAMP}"
rm -rf "${BACKUP_DIR}"

# Copy to NAS
if cp "/tmp/${BACKUP_FILE}" "${NAS_BACKUP_PATH}/"; then
    # Cleanup old backups (keep last 5 per host)
    ls -t ${NAS_BACKUP_PATH}/proxmox-config-${HOSTNAME}-*.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm
    rm -f "/tmp/${BACKUP_FILE}"
    echo ""
    echo "=== Backup Complete ==="
    echo "File: ${NAS_BACKUP_PATH}/${BACKUP_FILE}"
else
    echo ""
    echo "=== Copy Failed ==="
    echo "Local file: /tmp/${BACKUP_FILE}"
fi

#===============================================================================
#                         RESTORATION NOTES
#===============================================================================
#
# PREREQUISITES (Fresh Proxmox Install):
# --------------------------------------
# 1. Install Proxmox VE (same or newer version)
# 2. Use SAME HOSTNAME as original
# 3. Basic network to reach backup location
# 4. Install: apt install nfs-common cifs-utils
#
# RESTORE STEPS:
# --------------
# 1. Copy backup: scp proxmox-config-*.tar.gz root@new-proxmox:/tmp/
#
# 2. Extract:
#    cd /tmp && tar -xzf proxmox-config-*.tar.gz && cd proxmox-config-*
#
# 3. Stop services:
#    systemctl stop pvedaemon pveproxy pvestatd
#
# 4. Restore configs:
#    cp -a pve/* /etc/pve/
#    cp network/interfaces /etc/network/interfaces
#    cp network/hosts /etc/hosts
#    cp storage/fstab /etc/fstab
#    cp boot/grub /etc/default/grub && update-grub
#    cp boot/modules /etc/modules
#    cp -a boot/modprobe.d/* /etc/modprobe.d/
#    cp -a boot/sysctl.d/* /etc/sysctl.d/
#    cp -a apt/sources.list* /etc/apt/
#    cp ssh/sshd_config /etc/ssh/
#    cp ssh/authorized_keys /root/.ssh/
#    crontab cron/root-crontab.txt
#    cp systemd/*.service /etc/systemd/system/ && systemctl daemon-reload
#
# 5. Reboot
#
# 6. Restore VM/LXC data from vzdump backups
#
# NOTES:
# - VM/LXC DATA not included - restore from vzdump
# - Storage paths must exist before starting services
# - If hardware changed, update /etc/network/interfaces MAC addresses
# - Review SYSTEM-INFO.txt for original system state
#
#===============================================================================
