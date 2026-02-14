#!/bin/bash
#===============================================================================
# Golden Image Setup & Cleanup Script
# Run AFTER manual OS installation, BEFORE converting to template
# Supports: Rocky Linux 10.x / RHEL-based
#
# Usage: curl -sL <url> | bash  OR  ./golden-image-setup.sh
#===============================================================================

set -e

echo "==============================================================================="
echo "         GOLDEN IMAGE SETUP - Rocky Linux 10.x"
echo "==============================================================================="

#-------------------------------------------------------------------------------
# 1. System Update
#-------------------------------------------------------------------------------
echo ""
echo ">>> [1/9] Updating system packages..."
dnf update -y

#-------------------------------------------------------------------------------
# 2. Install Essential Packages
#-------------------------------------------------------------------------------
echo ""
echo ">>> [2/9] Installing essential packages..."
dnf install -y \
    qemu-guest-agent \
    cloud-init \
    curl \
    wget \
    vim \
    htop \
    git \
    ca-certificates \
    sudo \
    bash-completion \
    tar \
    unzip \
    openssh-server \
    openssh-clients \
    net-tools \
    traceroute \
    bind-utils \
    tcpdump \
    nmap-ncat \
    iputils \
    iproute

#-------------------------------------------------------------------------------
# 3. Enable Services
#-------------------------------------------------------------------------------
echo ""
echo ">>> [3/9] Enabling services..."
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
systemctl enable sshd
systemctl enable cloud-init

# Enable root SSH login
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd

#-------------------------------------------------------------------------------
# 4. Clean Package Cache
#-------------------------------------------------------------------------------
echo ""
echo ">>> [4/9] Cleaning package cache..."
dnf clean all
rm -rf /var/cache/dnf/*

#-------------------------------------------------------------------------------
# 5. Clear Logs
#-------------------------------------------------------------------------------
echo ""
echo ">>> [5/9] Clearing logs..."
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --vacuum-time=1s

#-------------------------------------------------------------------------------
# 6. Clear Temp Files and History
#-------------------------------------------------------------------------------
echo ""
echo ">>> [6/9] Clearing temp files and history..."
rm -rf /tmp/*
rm -rf /var/tmp/*
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history
history -c 2>/dev/null || true

#-------------------------------------------------------------------------------
# 7. Reset Machine ID (regenerates on first boot)
#-------------------------------------------------------------------------------
echo ""
echo ">>> [7/9] Resetting machine-id..."
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

#-------------------------------------------------------------------------------
# 8. Remove SSH Host Keys (regenerates on first boot)
#-------------------------------------------------------------------------------
echo ""
echo ">>> [8/9] Removing SSH host keys..."
rm -f /etc/ssh/ssh_host_*

#-------------------------------------------------------------------------------
# 9. Clear Network Config & Cloud-Init State
#-------------------------------------------------------------------------------
echo ""
echo ">>> [9/9] Clearing network and cloud-init state..."
rm -f /etc/NetworkManager/system-connections/*.nmconnection
rm -f /etc/sysconfig/network-scripts/ifcfg-*
truncate -s 0 /etc/hostname
cloud-init clean --logs --seed 2>/dev/null || true

#-------------------------------------------------------------------------------
# Done - Ready for Template
#-------------------------------------------------------------------------------
echo ""
echo "==============================================================================="
echo "  SETUP COMPLETE - Ready for template conversion"
echo "==============================================================================="
echo ""
echo "Installed packages:"
echo "  - qemu-guest-agent, cloud-init"
echo "  - curl, wget, vim, htop, git"
echo "  - net-tools, traceroute, bind-utils, tcpdump, nmap-ncat"
echo "  - openssh-server/clients, bash-completion, tar, unzip"
echo ""
echo "Next steps:"
echo "  1. Verify everything looks good"
echo "  2. Shutdown: shutdown -h now"
echo "  3. Remove CD-ROM in Proxmox (Hardware > CD/DVD > Do not use any media)"
echo "  4. Change boot order to disk only (Options > Boot Order)"
echo "  5. Convert to template: Right-click VM > Convert to Template"
echo "==============================================================================="
echo ""

read -p "Shutdown now? (y/n): " SHUTDOWN
if [ "$SHUTDOWN" = "y" ]; then
    shutdown -h now
fi
