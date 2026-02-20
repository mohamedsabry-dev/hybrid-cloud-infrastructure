#!/bin/bash
#===============================================================================
# LXC Golden Image Setup Script
# Run on Proxmox host to create a golden LXC template
#
# Creates container, installs packages, cleans up, converts to template
#
# Usage: ./lxc-golden-setup.sh [CTID] [STORAGE]
#   CTID    - Container ID for template (default: 9001)
#   STORAGE - Storage for rootfs (default: local-lvm)
#===============================================================================

set -e

# Configuration
CTID=${1:-9001}
STORAGE=${2:-local-lvm}
TEMPLATE_FILE="/var/lib/vz/template/cache/rockylinux-10-default_20251001_amd64.tar.xz"
HOSTNAME="rocky10-lxc-golden"
MEMORY=2048
CORES=2
ROOTFS_SIZE=8
BRIDGE="vmbr0"
VLAN=65
IP="10.0.65.98/24"
GATEWAY="10.0.65.1"

echo "==============================================================================="
echo "         LXC GOLDEN TEMPLATE SETUP - Rocky Linux 10"
echo "==============================================================================="
echo ""
echo "Configuration:"
echo "  CTID:     $CTID"
echo "  Storage:  $STORAGE"
echo "  Hostname: $HOSTNAME"
echo "  Network:  $IP (VLAN $VLAN)"
echo ""

#-------------------------------------------------------------------------------
# 1. Check Prerequisites
#-------------------------------------------------------------------------------
echo ">>> [1/7] Checking prerequisites..."

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: Template not found: $TEMPLATE_FILE"
    echo "Download it first:"
    echo "  pveam download local rockylinux-10-default_20251001_amd64.tar.xz"
    exit 1
fi

if pct status $CTID &>/dev/null; then
    echo "ERROR: Container $CTID already exists"
    echo "Remove it first: pct destroy $CTID"
    exit 1
fi

echo "Prerequisites OK"

#-------------------------------------------------------------------------------
# 2. Create Container
#-------------------------------------------------------------------------------
echo ""
echo ">>> [2/7] Creating container $CTID..."

pct create $CTID "$TEMPLATE_FILE" \
    --hostname "$HOSTNAME" \
    --storage "$STORAGE" \
    --rootfs "$STORAGE:$ROOTFS_SIZE" \
    --memory "$MEMORY" \
    --cores "$CORES" \
    --net0 "name=eth0,bridge=$BRIDGE,tag=$VLAN,ip=$IP,gw=$GATEWAY" \
    --unprivileged 1 \
    --features nesting=1 \
    --onboot 0 \
    --start 0

echo "Container created"

#-------------------------------------------------------------------------------
# 3. Start Container
#-------------------------------------------------------------------------------
echo ""
echo ">>> [3/7] Starting container..."
pct start $CTID
sleep 5  # Wait for container to fully start

#-------------------------------------------------------------------------------
# 4. Install Packages
#-------------------------------------------------------------------------------
echo ""
echo ">>> [4/7] Installing packages inside container..."

pct exec $CTID -- bash -c '
    echo "Updating system..."
    dnf update -y

    echo "Installing EPEL..."
    dnf install -y epel-release

    echo "Installing essential packages..."
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
        policycoreutils-python-utils \
        openssh-server \
        openssh-clients \
        rsyslog \
        net-tools \
        traceroute \
        bind-utils \
        tcpdump \
        nmap-ncat \
        iputils \
        iproute \
        ipa-client

    echo "Enabling services..."
    systemctl enable sshd
    systemctl enable rsyslog

    # Enable root SSH login
    sed -i "s/^#PermitRootLogin.*/PermitRootLogin yes/" /etc/ssh/sshd_config
    sed -i "s/^PermitRootLogin no/PermitRootLogin yes/" /etc/ssh/sshd_config

    echo "Creating gandalf break-glass user..."
    if ! id "gandalf" &>/dev/null; then
        useradd -m -s /bin/bash -c "Emergency Break-Glass User" gandalf
        usermod -aG wheel gandalf
        passwd -l gandalf
    fi

    # Ensure wheel group has sudo access
    echo "%wheel ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel-nopasswd
    chmod 440 /etc/sudoers.d/wheel-nopasswd

    echo "Package installation complete"
'

#-------------------------------------------------------------------------------
# 5. Cleanup Inside Container
#-------------------------------------------------------------------------------
echo ""
echo ">>> [5/7] Cleaning up container..."

pct exec $CTID -- bash -c '
    dnf clean all
    rm -rf /var/cache/dnf/*
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    find /var/log -type f -exec truncate -s 0 {} \;
    rm -f /etc/machine-id
    truncate -s 0 /etc/machine-id
    rm -f /root/.bash_history
    rm -f /home/*/.bash_history
'

echo "Cleanup complete"

#-------------------------------------------------------------------------------
# 6. Stop Container
#-------------------------------------------------------------------------------
echo ""
echo ">>> [6/7] Stopping container..."
pct stop $CTID
sleep 3

#-------------------------------------------------------------------------------
# 7. Convert to Template
#-------------------------------------------------------------------------------
echo ""
echo ">>> [7/7] Converting to template..."
pct template $CTID

echo ""
echo "==============================================================================="
echo "  LXC GOLDEN TEMPLATE CREATED SUCCESSFULLY"
echo "==============================================================================="
echo ""
echo "Template ID: $CTID"
echo "Hostname:    $HOSTNAME"
echo ""
echo "Installed packages:"
echo "  - curl, wget, vim, htop, git, tree, jq, bash-completion"
echo "  - openssh-server/clients, rsyslog"
echo "  - net-tools, traceroute, bind-utils, tcpdump, nmap-ncat"
echo "  - ipa-client (package only, not configured)"
echo "  - gandalf user (break-glass, in wheel group)"
echo ""
echo "To clone from this template:"
echo "  pct clone $CTID <new-ctid> --hostname <name> --full"
echo ""
echo "Or use Terraform to deploy containers from this template."
echo "==============================================================================="
