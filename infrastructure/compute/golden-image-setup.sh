#!/bin/bash
#===============================================================================
# Golden Image Cleanup Script
# Run AFTER cloud-init completes, BEFORE converting to template
# Supports: Rocky Linux 10.x / RHEL-based
#
# Usage: ./golden-image-setup.sh
#===============================================================================

set -e

echo "==============================================================================="
echo "         GOLDEN IMAGE CLEANUP - Preparing for Template"
echo "==============================================================================="

# Wait for cloud-init to complete
echo ">>> Checking cloud-init status..."
cloud-init status --wait || true

#-------------------------------------------------------------------------------
# 1. Clean Package Cache
#-------------------------------------------------------------------------------
echo ">>> Cleaning package cache..."
dnf clean all
rm -rf /var/cache/dnf/*

#-------------------------------------------------------------------------------
# 2. Clear Logs
#-------------------------------------------------------------------------------
echo ">>> Clearing logs..."
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --vacuum-time=1s

#-------------------------------------------------------------------------------
# 3. Clear Temp Files
#-------------------------------------------------------------------------------
echo ">>> Clearing temp files..."
rm -rf /tmp/*
rm -rf /var/tmp/*

#-------------------------------------------------------------------------------
# 4. Clear Shell History
#-------------------------------------------------------------------------------
echo ">>> Clearing shell history..."
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history
history -c

#-------------------------------------------------------------------------------
# 5. Reset Machine ID (regenerates on first boot)
#-------------------------------------------------------------------------------
echo ">>> Resetting machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

#-------------------------------------------------------------------------------
# 6. Remove SSH Host Keys (regenerates on first boot)
#-------------------------------------------------------------------------------
echo ">>> Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

#-------------------------------------------------------------------------------
# 7. Clear Network Config (configure per-clone)
#-------------------------------------------------------------------------------
echo ">>> Clearing network configuration..."
rm -f /etc/NetworkManager/system-connections/*.nmconnection
rm -f /etc/sysconfig/network-scripts/ifcfg-*
truncate -s 0 /etc/hostname

#-------------------------------------------------------------------------------
# 8. Reset Cloud-Init (runs fresh on clone)
#-------------------------------------------------------------------------------
echo ">>> Resetting cloud-init..."
cloud-init clean --logs --seed

#-------------------------------------------------------------------------------
# Done - Shutdown
#-------------------------------------------------------------------------------
echo "==============================================================================="
echo "Cleanup complete! Ready for template conversion."
echo ""
echo "Next steps:"
echo "  1. Shutdown: shutdown -h now"
echo "  2. In Proxmox: Right-click VM > Convert to Template"
echo "==============================================================================="

read -p "Shutdown now? (y/n): " SHUTDOWN
if [ "$SHUTDOWN" = "y" ]; then
    shutdown -h now
fi
