#!/bin/bash
# Golden image setup + cleanup for Ubuntu 26.04 LTS templates.
# Run after fresh OS install, before converting to a Proxmox template.

set -e

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
dmesg -n 1

confirm() {
    while read -t 0.1 -n 1 </dev/tty 2>/dev/null; do :; done
    while true; do
        read -p "$1 (y/n): " ans </dev/tty
        case "$ans" in
            y|Y) return 0 ;;
            n|N) return 1 ;;
            *) echo "Enter y or n." ;;
        esac
    done
}

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
sed -i 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 /' /etc/default/grub
update-grub
systemctl enable serial-getty@ttyS0.service

echo "== cleaning up =="
apt-get clean
rm -rf /var/cache/apt/archives/*
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --vacuum-time=1s
rm -rf /tmp/* /var/tmp/*
rm -f /root/.bash_history /home/*/.bash_history
unset HISTFILE
history -c 2>/dev/null || true

echo ""
echo "Package install + config done. Next step wipes SSH keys, network config,"
echo "and machine-id — this will disconnect your session, and the VM shuts down after."
echo ""

confirm "Proceed with cleanup and shutdown?" || { echo "Aborted."; exit 0; }

truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
rm -f /etc/ssh/ssh_host_*
rm -f /root/.ssh/authorized_keys
rm -f /home/*/.ssh/authorized_keys 2>/dev/null || true
rm -f /etc/netplan/*.yaml
rm -f /etc/NetworkManager/system-connections/*.nmconnection
truncate -s 0 /etc/hostname
cloud-init clean --logs --seed 2>/dev/null || true

echo ""
echo "Cleanup done. Before converting to template:"
echo "  - remove CD-ROM (Hardware > CD/DVD > do not use media)"
echo "  - set boot order to disk only"
echo "  - right-click VM > Convert to Template"
echo ""

confirm "Shutdown now?" && shutdown -h now || echo "Skipped — run 'shutdown -h now' when ready."