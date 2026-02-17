#!/bin/bash
#===============================================================================
# Golden Image Setup & Cleanup Script
# Run AFTER manual OS installation, BEFORE converting to template
# Supports: Rocky Linux 10.x / RHEL-based
#
# Installs: Basic tools, network utilities, qemu-guest-agent, cloud-init,
#           IPA client (package only), gandalf break-glass user
#
# Usage: ./golden-image-setup.sh
#===============================================================================

set -e

# Suppress kernel messages on console
dmesg -n 1

echo "==============================================================================="
echo "         GOLDEN IMAGE SETUP - Rocky Linux 10.x"
echo "==============================================================================="

#-------------------------------------------------------------------------------
# 1. System Update
#-------------------------------------------------------------------------------
echo ""
echo ">>> [1/12] Updating system packages..."
dnf update -y

#-------------------------------------------------------------------------------
# 2. Enable EPEL Repository
#-------------------------------------------------------------------------------
echo ""
echo ">>> [2/12] Enabling EPEL repository..."
dnf install -y epel-release

#-------------------------------------------------------------------------------
# 3. Install Essential Packages
#-------------------------------------------------------------------------------
echo ""
echo ">>> [3/12] Installing essential packages..."
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
    jq \
    yum-utils \
    policycoreutils-python-utils

#-------------------------------------------------------------------------------
# 4. Install SSH & Security Tools
#-------------------------------------------------------------------------------
echo ""
echo ">>> [4/12] Installing SSH and security tools..."
dnf install -y \
    openssh-server \
    openssh-clients \
    audit \
    rsyslog

#-------------------------------------------------------------------------------
# 5. Install Network Tools
#-------------------------------------------------------------------------------
echo ""
echo ">>> [5/12] Installing network tools..."
dnf install -y \
    net-tools \
    traceroute \
    bind-utils \
    tcpdump \
    nmap-ncat \
    iputils \
    iproute \
    NetworkManager \
    NetworkManager-tui

#-------------------------------------------------------------------------------
# 6. Install IPA Client (Package Only - Configure via Ansible)
#-------------------------------------------------------------------------------
echo ""
echo ">>> [6/12] Installing IPA client package..."
dnf install -y ipa-client
echo "NOTE: IPA client installed but NOT configured. Use Ansible to enroll VMs."

#-------------------------------------------------------------------------------
# 7. Create Gandalf Break-Glass User
#-------------------------------------------------------------------------------
echo ""
echo ">>> [7/12] Creating gandalf break-glass user..."

if id "gandalf" &>/dev/null; then
    echo "User gandalf already exists"
else
    useradd -m -s /bin/bash -c "Emergency Break-Glass User" gandalf

    # Add to wheel group for sudo
    usermod -aG wheel gandalf

    # Lock account until password is set via Ansible
    passwd -l gandalf

    echo "NOTE: gandalf user created but locked. Set password via Ansible from AWS Secrets Manager."
fi

# Ensure wheel group has sudo access
if ! grep -q "^%wheel.*NOPASSWD" /etc/sudoers.d/wheel-nopasswd 2>/dev/null; then
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
    chmod 440 /etc/sudoers.d/wheel-nopasswd
fi

#-------------------------------------------------------------------------------
# 8. Enable Services
#-------------------------------------------------------------------------------
echo ""
echo ">>> [8/12] Enabling services..."
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
systemctl enable sshd
systemctl enable cloud-init
systemctl enable rsyslog
systemctl enable auditd

# Enable root SSH login (can disable later via Ansible if using gandalf)
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart sshd

#-------------------------------------------------------------------------------
# 9. Clean Package Cache
#-------------------------------------------------------------------------------
echo ""
echo ">>> [9/12] Cleaning package cache..."
dnf clean all
rm -rf /var/cache/dnf/*

#-------------------------------------------------------------------------------
# 10. Clear Logs
#-------------------------------------------------------------------------------
echo ""
echo ">>> [10/12] Clearing logs..."
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --vacuum-time=1s

#-------------------------------------------------------------------------------
# 11. Clear Temp Files and History
#-------------------------------------------------------------------------------
echo ""
echo ">>> [11/12] Clearing temp files and history..."
rm -rf /tmp/*
rm -rf /var/tmp/*
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history
history -c 2>/dev/null || true

#-------------------------------------------------------------------------------
# Done with package installation - Prompt before cleanup
#-------------------------------------------------------------------------------
echo ""
echo "==============================================================================="
echo "  PACKAGE INSTALLATION COMPLETE"
echo "==============================================================================="
echo ""
echo "Installed:"
echo "  - qemu-guest-agent, cloud-init"
echo "  - curl, wget, vim, htop, git, jq"
echo "  - net-tools, traceroute, bind-utils, tcpdump, nmap-ncat, nmcli"
echo "  - openssh-server/clients, audit, rsyslog"
echo "  - ipa-client (package only, not configured)"
echo "  - gandalf user (break-glass, in wheel group)"
echo ""
echo "WARNING: Next step will clear network config, SSH keys, and machine-id."
echo "         This will DISCONNECT your SSH session!"
echo ""
echo "The VM will automatically shutdown after cleanup."
echo ""
read -p "Proceed with cleanup and shutdown? (y/n): " PROCEED </dev/tty
if [ "$PROCEED" != "y" ]; then
    echo "Aborted. Run script again when ready."
    exit 0
fi

#-------------------------------------------------------------------------------
# 12. Final Cleanup (WILL DISCONNECT SSH)
#-------------------------------------------------------------------------------
echo ""
echo ">>> [12/12] Final cleanup and shutdown..."

# Reset machine-id
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Remove SSH host keys (regenerate on first boot)
rm -f /etc/ssh/ssh_host_*

# Clear network config
rm -f /etc/NetworkManager/system-connections/*.nmconnection
rm -f /etc/sysconfig/network-scripts/ifcfg-*
truncate -s 0 /etc/hostname

# Reset cloud-init
cloud-init clean --logs --seed 2>/dev/null || true

#-------------------------------------------------------------------------------
# Shutdown
#-------------------------------------------------------------------------------
echo ""
echo "==============================================================================="
echo "  CLEANUP COMPLETE"
echo "==============================================================================="
echo ""
echo "Next steps:"
echo "  1. Test anything you need"
echo "  2. Shutdown the VM"
echo "  3. Approve the workflow in GitHub (or manually in Proxmox UI):"
echo "     - Remove CD-ROM (Hardware > CD/DVD > Do not use any media)"
echo "     - Change boot order to disk only (Options > Boot Order)"
echo "     - Convert to template: Right-click VM > Convert to Template"
echo "==============================================================================="
echo ""

read -p "Shutdown now? (y/n): " SHUTDOWN </dev/tty
if [ "$SHUTDOWN" = "y" ]; then
    echo "Shutting down..."
    shutdown -h now
else
    echo "Skipped shutdown. Run 'shutdown -h now' when ready."
fi
