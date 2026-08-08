#!/bin/bash
# Golden image CLEANUP for Ubuntu 26.04 LTS.
# DESTRUCTIVE — wipes SSH host keys, network config, and machine-id, then
# shuts the VM down. Run this ONLY on a disposable clone that is about to
# become a Proxmox template. NEVER run this on the living source VM —
# you will lose the ability to SSH back into it.

set -e

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

echo ""
echo "This will wipe SSH keys, network config, and machine-id on THIS VM,"
echo "then shut it down. Confirm this is the disposable clone, not the source."
echo ""

confirm "Proceed with cleanup and shutdown?" || { echo "Aborted."; exit 0; }

apt-get clean
rm -rf /var/cache/apt/archives/*
find /var/log -type f -exec truncate -s 0 {} \;
journalctl --vacuum-time=1s
rm -rf /tmp/* /var/tmp/*
rm -f /root/.bash_history /home/*/.bash_history
unset HISTFILE
history -c 2>/dev/null || true

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