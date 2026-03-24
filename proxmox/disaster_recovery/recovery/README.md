# Full System Recovery

Guide for complete Proxmox reinstall and restoration from backups.

## When to Use

- Complete hardware failure requiring new machine
- Corrupted Proxmox installation
- Disk failure requiring full reinstall

## Prerequisites

Before disaster strikes, ensure you have:

- [ ] Config backup from `backup-proxmox-config.sh` on NAS
- [ ] VM/CT backups (vzdump) on NAS
- [ ] Proxmox ISO on USB drive
- [ ] Network documentation (IPs, VLANs)
- [ ] This guide accessible offline

## Recovery Steps

### 1. Fresh Proxmox Install

```bash
# Boot from Proxmox ISO
# Use SAME hostname as original (pve-dev or pve-prod)
# Configure basic network to reach backup location
```

### 2. Run Bootstrap

```bash
# Copy bootstrap script
scp proxmox/bootstrap_proxmox/bootstrap.sh root@<new-proxmox>:/tmp/

# Run bootstrap
ssh root@<new-proxmox>
chmod +x /tmp/bootstrap.sh
/tmp/bootstrap.sh dev  # or prod
```

### 3. Restore Config Backup

```bash
# Mount NAS or copy backup
scp nas:/backups/proxmox-config-*.tar.gz /tmp/

# Extract
cd /tmp && tar -xzf proxmox-config-*.tar.gz
cd proxmox-config-*

# Stop services
systemctl stop pvedaemon pveproxy pvestatd

# Restore configs
cp -a pve/* /etc/pve/
cp network/interfaces /etc/network/interfaces
cp network/hosts /etc/hosts
cp storage/fstab /etc/fstab
cp boot/grub /etc/default/grub && update-grub
cp boot/modules /etc/modules
cp -a boot/modprobe.d/* /etc/modprobe.d/
cp -a boot/sysctl.d/* /etc/sysctl.d/
cp -a apt/sources.list* /etc/apt/
cp ssh/sshd_config /etc/ssh/
cp ssh/authorized_keys /root/.ssh/
crontab cron/root-crontab.txt
cp systemd/*.service /etc/systemd/system/ && systemctl daemon-reload

# Reboot
reboot
```

### 4. Run Network Setup

```bash
/tmp/network-setup.sh dev  # or prod
reboot
```

### 5. Restore Storage Configuration

```bash
# Verify storage mounts
cat /etc/fstab
mount -a

# Check Proxmox storage
pvesm status
```

### 6. Restore VMs/CTs from Backup

```bash
# List available backups
ls /mnt/pve/nas-backups/dump/

# Restore VM
qmrestore /mnt/pve/nas-backups/dump/vzdump-qemu-<vmid>-*.vma <new-vmid>

# Restore CT
pct restore <new-ctid> /mnt/pve/nas-backups/dump/vzdump-lxc-<ctid>-*.tar.gz
```

### 7. Verify

- [ ] Web UI accessible
- [ ] VMs/CTs start correctly
- [ ] Network connectivity (ping gateway, NAS)
- [ ] Storage accessible
- [ ] Backups configured

## Notes

- VM/CT IDs may need adjustment if conflicts exist
- MAC addresses regenerate - DHCP reservations may need update
- Check SYSTEM-INFO.txt in backup for original state reference
- Re-run mail-config.sh if email notifications needed

## Related

- Config backup script: `proxmox/backup/backup-proxmox-config.sh`
- Bootstrap scripts: `proxmox/bootstrap_proxmox/`
- Network setup: `proxmox/bootstrap_proxmox/network-setup.sh`
