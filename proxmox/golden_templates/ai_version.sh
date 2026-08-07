#!/bin/bash
#===============================================================================
# Golden Image Setup & Cleanup Script
# Run AFTER manual OS installation, BEFORE converting to template
# Supports: Ubuntu 26.04 LTS
# Usage: ./golden-vm-setup-ubuntu.sh
#===============================================================================
# 1.  System Update
# 2.  Enable Universe/Multiverse Repositories
# 3.  Install Essential Packages
# 4.  Install SSH & Security Tools
# 5.  Install Network Tools
# 6.  Install FreeIPA Client Package
# 7.  Create gandalf break-glass user
# 8.  Enable Services
# 9.  Clean Package Cache
# 10. Clear Logs
# 11. Clear Temp Files & History
# 12. Final Cleanup & Shutdown
#===============================================================================

set -e

# Prevent apt from blocking on interactive prompts (config conflicts,
# needrestart service-restart dialogs) during unattended provisioning
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# Suppress kernel messages on console
dmesg -n 1

echo "==============================================================================="
echo "         GOLDEN IMAGE SETUP - Ubuntu 26.04 LTS"
echo "==============================================================================="

#-------------------------------------------------------------------------------
# 1. System Update
#-------------------------------------------------------------------------------
echo ""
echo ">>> [1/12] Updating system packages..."
apt-get update
apt-get upgrade -y

#-------------------------------------------------------------------------------
# 2. Enable Universe/Multiverse Repositories
#-------------------------------------------------------------------------------
# RHEL's EPEL adds a third-party repo. Ubuntu's equivalent is simply making
# sure the in-box universe/multiverse repos (where most of these tools live)
# are enabled - no external repo needed.
echo ""
echo ">>> [2/12] Enabling universe/multiverse repositories..."
apt-get install -y software-properties-common
add-apt-repository -y universe
add-apt-repository -y multiverse
apt-get update

#-------------------------------------------------------------------------------
# 3. Install Essential Packages
#-------------------------------------------------------------------------------
echo ""
echo ">>> [3/12] Installing essential packages..."
apt-get install -y \
    qemu-guest-agent \
    cloud-init \
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
    jq

# NOTE: yum-utils and policycoreutils-python-utils have no direct Ubuntu
# equivalent in this context - repo management is handled above via
# software-properties-common, and Ubuntu uses AppArmor (not SELinux), so
# there's nothing to install for that.

#-------------------------------------------------------------------------------
# 4. Install SSH & Security Tools
#-------------------------------------------------------------------------------
echo ""
echo ">>> [4/12] Installing SSH and security tools..."
apt-get install -y \
    openssh-server \
    openssh-client \
    auditd \
    rsyslog

#-------------------------------------------------------------------------------
# 5. Install Network Tools
#-------------------------------------------------------------------------------
echo ""
echo ">>> [5/12] Installing network tools..."
apt-get install -y \
    net-tools \
    traceroute \
    dnsutils \
    tcpdump \
    ncat \
    iputils-ping \
    iproute2 \
    network-manager

# NOTE: nmtui ships inside the network-manager package on Ubuntu -
# no separate "-tui" package needed.

#-------------------------------------------------------------------------------
# 6. Install FreeIPA Client (Package Only - Configure via Ansible)
#-------------------------------------------------------------------------------
echo ""
echo ">>> [6/12] Installing FreeIPA client package..."
apt-get install -y freeipa-client
echo "NOTE: FreeIPA client installed but NOT configured. Use Ansible to enroll VMs."

#-------------------------------------------------------------------------------
# 7. Create Gandalf Break-Glass User
#-------------------------------------------------------------------------------
echo ""
echo ">>> [7/12] Creating gandalf break-glass user..."

if id "gandalf" &>/dev/null; then
    echo "User gandalf already exists"
else
    useradd -m -s /bin/bash -c "Emergency Break-Glass User" gandalf

    # Ubuntu's sudo-capable group is "sudo", not "wheel"
    usermod -aG sudo gandalf

    # Lock account until password is set via Ansible
    passwd -l gandalf

    echo "NOTE: gandalf user created but locked. Set password via Ansible from AWS Secrets Manager."
fi

# Ensure sudo group has passwordless sudo access
if ! grep -q "^%sudo.*NOPASSWD" /etc/sudoers.d/sudo-nopasswd 2>/dev/null; then
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/sudo-nopasswd
    chmod 440 /etc/sudoers.d/sudo-nopasswd
fi

#-------------------------------------------------------------------------------
# 8. Enable Services
#-------------------------------------------------------------------------------
echo ""
echo ">>> [8/12] Enabling services..."
systemctl enable qemu-guest-agent
systemctl start qemu-guest-agent
systemctl enable ssh
systemctl enable rsyslog
systemctl enable auditd

# Ubuntu 26 split cloud-init into staged systemd units (local/network/config/final).
# A single "systemctl enable cloud-init" can silently miss stages that no
# longer share that unit name, so enable each stage defensively and only
# warn (don't hard-fail) on units that don't exist on this build.
for unit in cloud-init-local.service cloud-init-network.service cloud-config.service cloud-final.service; do
    if systemctl list-unit-files | grep -q "^${unit}"; then
        systemctl enable "$unit"
    else
        echo "WARNING: unit $unit not found, skipping"
    fi
done

# Configure cloud-init to preserve SSH host keys after first generation
# This prevents cloud-init from regenerating keys when config changes (e.g., Terraform updates)
cat > /etc/cloud/cloud.cfg.d/99-preserve-ssh.cfg << EOF
ssh_deletekeys: false
ssh_genkeytypes: []
EOF
echo "NOTE: Cloud-init configured to preserve SSH host keys after first boot."

# ufw: disable (Ubuntu's equivalent of firewalld; not enabled by default on
# Server anyway, but disable explicitly for idempotency - enable via Ansible if needed)
systemctl disable ufw 2>/dev/null || true
ufw disable 2>/dev/null || true
echo "NOTE: ufw disabled. Enable via Ansible if needed."

# SSH: Allow root login with keys only (no password)
# Keys will be injected via Terraform cloud-init initialization
sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^PermitRootLogin no/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl restart ssh

# Enable serial console for Proxmox qm terminal access (emergency)
sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 /' /etc/default/grub
update-grub
systemctl enable serial-getty@ttyS0.service

#-------------------------------------------------------------------------------
# 9. Clean Package Cache
#-------------------------------------------------------------------------------
echo ""
echo ">>> [9/12] Cleaning package cache..."
apt-get clean
rm -rf /var/cache/apt/archives/*

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
echo "  - curl, wget, vim, htop, git, tree, jq"
echo "  - net-tools, traceroute, dnsutils, tcpdump, ncat, nmtui (via network-manager)"
echo "  - openssh-server/client, auditd, rsyslog, ufw (disabled)"
echo "  - freeipa-client (package only, not configured)"
echo "  - gandalf user (break-glass, in sudo group)"
echo ""
echo "WARNING: Next step will clear network config, SSH keys, and machine-id."
echo "         This will DISCONNECT your SSH session!"
echo ""
echo "The VM will automatically shutdown after cleanup."
echo ""

# Flush any buffered input (from accidental Enter presses during install)
while read -t 0.1 -n 1 </dev/tty 2>/dev/null; do :; done

# Prompt with validation loop - only accept y or n
while true; do
    read -p "Proceed with cleanup and shutdown? (y/n): " PROCEED </dev/tty
    case "$PROCEED" in
        y|Y)
            break
            ;;
        n|N)
            echo "Aborted. Run script again when ready."
            exit 0
            ;;
        *)
            echo "Invalid input. Please enter 'y' or 'n'."
            ;;
    esac
done

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

# Clear authorized_keys (cloud-init will inject new keys per VM)
rm -f /root/.ssh/authorized_keys
rm -f /home/*/.ssh/authorized_keys 2>/dev/null || true

# Clear network config
# Ubuntu Server typically renders networking via netplan (systemd-networkd
# or NetworkManager backend) rather than RHEL-style ifcfg files, so clear
# both netplan configs and NM connection profiles to cover either renderer.
rm -f /etc/netplan/*.yaml
rm -f /etc/NetworkManager/system-connections/*.nmconnection
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

# Flush any buffered input
while read -t 0.1 -n 1 </dev/tty 2>/dev/null; do :; done

# Prompt with validation loop - only accept y or n
while true; do
    read -p "Shutdown now? (y/n): " SHUTDOWN </dev/tty
    case "$SHUTDOWN" in
        y|Y)
            echo "Shutting down..."
            shutdown -h now
            ;;
        n|N)
            echo "Skipped shutdown. Run 'shutdown -h now' when ready."
            break
            ;;
        *)
            echo "Invalid input. Please enter 'y' or 'n'."
            ;;
    esac
done