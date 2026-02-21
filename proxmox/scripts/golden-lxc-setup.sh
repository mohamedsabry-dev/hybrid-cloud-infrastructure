#!/bin/bash
#===============================================================================
# LXC Golden Template Setup & Cleanup Script
# Run INSIDE the LXC container, BEFORE converting to template
# Supports: Rocky Linux 10.x / RHEL-based
# Usage: ./golden-lxc-setup.sh
#===============================================================================
# 1. System Update
# 2. Enable EPEL Repository
# 3. Install Essential Packages
# 4. Install SSH & Security Tools
# 5. Install Network Tools
# 6. Install IPA Client Package
# 7. Create gandalf break-glass user
# 8. Enable Services
# 9. Final Cleanup
#===============================================================================

set -e

echo "==============================================================================="
echo "         LXC GOLDEN TEMPLATE SETUP - Rocky Linux 10.x"
echo "==============================================================================="

#-------------------------------------------------------------------------------
# 1. System Update
#-------------------------------------------------------------------------------
echo ""
echo ">>> [1/9] Updating system packages..."
dnf update -y

#-------------------------------------------------------------------------------
# 2. Enable EPEL Repository
#-------------------------------------------------------------------------------
echo ""
echo ">>> [2/9] Enabling EPEL repository..."
dnf install -y epel-release

#-------------------------------------------------------------------------------
# 3. Install Essential Packages
#-------------------------------------------------------------------------------
echo ""
echo ">>> [3/9] Installing essential packages..."
dnf install -y \
    curl \
    wget \
    vim \
    htop \
    git \
    tree \
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
echo ">>> [4/9] Installing SSH and security tools..."
dnf install -y \
    openssh-server \
    openssh-clients \
    rsyslog

#-------------------------------------------------------------------------------
# 5. Install Network Tools
#-------------------------------------------------------------------------------
echo ""
echo ">>> [5/9] Installing network tools..."
dnf install -y \
    net-tools \
    traceroute \
    bind-utils \
    tcpdump \
    nmap-ncat \
    iputils \
    iproute

#-------------------------------------------------------------------------------
# 6. Install IPA Client (Package Only - Configure via Ansible)
#-------------------------------------------------------------------------------
echo ""
echo ">>> [6/9] Installing IPA client package..."
dnf install -y ipa-client
echo "NOTE: IPA client installed but NOT configured. Use Ansible to enroll containers."

#-------------------------------------------------------------------------------
# 7. Create Gandalf Break-Glass User
#-------------------------------------------------------------------------------
echo ""
echo ">>> [7/9] Creating gandalf break-glass user..."

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
echo ">>> [8/9] Enabling services..."
systemctl enable sshd
systemctl enable rsyslog

# Enable root SSH login (can disable later via Ansible if using gandalf)
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

#-------------------------------------------------------------------------------
# Done with package installation - Prompt before cleanup
#-------------------------------------------------------------------------------
echo ""
echo "==============================================================================="
echo "  PACKAGE INSTALLATION COMPLETE"
echo "==============================================================================="
echo ""
echo "Installed:"
echo "  - curl, wget, vim, htop, git, tree, jq"
echo "  - openssh-server/clients, rsyslog"
echo "  - net-tools, traceroute, bind-utils, tcpdump, nmap-ncat"
echo "  - ipa-client (package only, not configured)"
echo "  - gandalf user (break-glass, in wheel group)"
echo ""
echo "WARNING: Next step will clear logs, cache, and machine-id."
echo ""
read -p "Proceed with cleanup? (y/n): " PROCEED </dev/tty
if [ "$PROCEED" != "y" ]; then
    echo "Aborted. Run script again when ready."
    exit 0
fi

#-------------------------------------------------------------------------------
# 9. Final Cleanup
#-------------------------------------------------------------------------------
echo ""
echo ">>> [9/9] Final cleanup..."

# Clean package cache
dnf clean all
rm -rf /var/cache/dnf/*

# Clear logs
find /var/log -type f -exec truncate -s 0 {} \;

# Clear temp files
rm -rf /tmp/*
rm -rf /var/tmp/*

# Reset machine-id
rm -f /etc/machine-id
truncate -s 0 /etc/machine-id

# Clear history
unset HISTFILE
rm -f /root/.bash_history
rm -f /home/*/.bash_history
history -c 2>/dev/null || true

#-------------------------------------------------------------------------------
# Done
#-------------------------------------------------------------------------------
echo ""
echo "==============================================================================="
echo "  CLEANUP COMPLETE"
echo "==============================================================================="
echo ""
echo "Next steps:"
echo "  1. Exit the container: exit"
echo "  2. Stop the container: pct stop 9001"
echo "  3. Convert to template: pct template 9001"
echo ""
echo "Or from Proxmox UI:"
echo "  Right-click container > Convert to Template"
echo "==============================================================================="
echo ""
