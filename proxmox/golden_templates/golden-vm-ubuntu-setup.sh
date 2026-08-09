#!/bin/bash
# Golden image SETUP for Ubuntu 26.04 LTS.
# Run on the living source VM (e.g. 8000). Non-destructive — safe to re-run
# any time you need to add/update packages. Does NOT touch SSH keys, network
# config, or machine-id. Once done, clone this VM and run golden-vm-cleanup.sh
# on the CLONE, not on this VM.

set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
dmesg -n 1

echo "== updating base system =="
apt-get update
apt-get upgrade -y

echo "== enabling universe/multiverse =="
apt-get install -y software-properties-common
add-apt-repository -y universe
add-apt-repository -y multiverse
apt-get update

echo "== installing packages =="
apt-get install -y \
    qemu-guest-agent cloud-init curl wget vim htop git tree \
    ca-certificates sudo bash-completion tar unzip jq \
    openssh-server openssh-client auditd rsyslog \
    net-tools traceroute dnsutils tcpdump ncat iputils-ping iproute2 network-manager \
    freeipa-client

echo "== gandalf break-glass user =="
if ! id gandalf &>/dev/null; then
    useradd -m -s /bin/bash -c "Emergency Break-Glass User" gandalf
    usermod -aG sudo gandalf
    passwd -l gandalf
fi

if ! grep -q "^%sudo.*NOPASSWD" /etc/sudoers.d/sudo-nopasswd 2>/dev/null; then
    echo "%sudo ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/sudo-nopasswd
    chmod 440 /etc/sudoers.d/sudo-nopasswd
fi

echo "== enabling services =="
systemctl enable --now qemu-guest-agent
systemctl enable ssh rsyslog auditd

# Ubuntu 26 split cloud-init into staged units; enable what exists, skip what doesn't.
for unit in cloud-init-local.service cloud-init-network.service cloud-config.service cloud-final.service; do
    systemctl list-unit-files | grep -q "^${unit}" && systemctl enable "$unit"
done

# Preserve host keys across cloud-init re-runs (config changes shouldn't wipe them),
# but still generate them on a genuine first boot / fresh clone.
# See TS Case 01 / TS-TF-010 — genkeytypes must list real types, not [].
cat > /etc/cloud/cloud.cfg.d/99-preserve-ssh.cfg << EOF
ssh_deletekeys: false
ssh_genkeytypes: ['rsa', 'ecdsa', 'ed25519']
EOF

systemctl disable ufw 2>/dev/null || true
ufw disable 2>/dev/null || true

sed -i \
    -e 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' \
    -e 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' \
    -e 's/^PermitRootLogin no/PermitRootLogin prohibit-password/' \
    /etc/ssh/sshd_config
systemctl restart ssh

# Serial console for Proxmox qm terminal
if ! grep -q "console=ttyS0" /etc/default/grub; then
    sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 /' /etc/default/grub
fi
update-grub
systemctl enable serial-getty@ttyS0.service

echo ""
echo "Setup complete. This VM is still fully accessible (SSH, network, hostname intact)."
echo ""
echo "MANUAL CHECK — netplan interface match:"
echo "  cat /etc/netplan/00-installer-config.yaml"
echo "  If it matches by MAC ('match:'/'macaddress:'), replace the top-level"
echo "  key with the real interface name (ip a / ls /sys/class/net) and remove"
echo "  the match block — keep addresses/routes/nameservers as-is. Then:"
echo "    netplan apply"
echo ""
echo "Next steps:"
echo "  1. Shut this VM down: shutdown -h now"
echo "  2. On the Proxmox host: qm clone <this-vmid> <new-vmid> --full --name ubuntu-golden-template"
echo "  3. Start the CLONE, SSH in, run golden-vm-cleanup.sh ON THE CLONE"
echo "  4. Shut the clone down and convert it: qm template <new-vmid>"
echo "  5. Keep this VM around — boot it again next time you need to add packages,"
echo "     then repeat steps 1-4 for a new template version."