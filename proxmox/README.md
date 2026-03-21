# Proxmox Documentation

## Backup Script

### File
`backup-proxmox-config.sh`

### Deployed To
| Host | Path |
|------|------|
| pve-prod | `/backup-proxmox-config.sh` |
| pve-dev | `/backup-proxmox-config.sh` |

### Usage
```bash
ssh root@pve-prod   # or pve-dev
chmod +x /backup-proxmox-config.sh
/backup-proxmox-config.sh
```

### What It Backs Up
- `/etc/pve` - VM/LXC configs, storage, users, permissions
- `/etc/network/interfaces` - Network/VLAN config
- `/etc/fstab` - Mount points
- `/etc/lvm` - LVM configuration
- Cron jobs
- Custom systemd services
- System info snapshot

### Output
```
/tmp/proxmox-config-<hostname>-<timestamp>.tar.gz
```

### Copy to NAS
```bash
scp /tmp/proxmox-config-*.tar.gz admin@10.0.5.120:/volume1/Backups/
```

### Restore Notes
See end of script for full restoration procedure.

**Prerequisites for fresh Proxmox:**
1. Install Proxmox VE (same or newer version)
2. Use SAME HOSTNAME as original
3. Basic network connectivity
4. Install: `apt install nfs-common cifs-utils`

**Quick restore:**
```bash
# On new Proxmox
cd /tmp && tar -xzf proxmox-config-*.tar.gz && cd proxmox-config-*
systemctl stop pvedaemon pveproxy pvestatd
cp -a pve/* /etc/pve/
cp network/interfaces /etc/network/interfaces
cp storage/fstab /etc/fstab
reboot
```

> **Note:** VM/LXC DATA not included - restore from vzdump backups on NAS.

---

## Related Files

| File | Description |
|------|-------------|
| storage/nas-storage-config.md | NAS shares and NFS config |
| vms/ | VM documentation |
| lxc/ | LXC container documentation |
