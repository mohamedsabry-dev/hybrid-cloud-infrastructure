# Proxmox Troubleshooting Cases

Documentation of issues encountered with Proxmox VE, including LXC containers, VMs, storage, networking, and backup operations.

---

## Cases

| # | Ticket ID | Date | Issue | Root Cause |
|---|-----------|------|-------|------------|
| 1 | [TS-PVE-001](1-proxmox-node-rename.md) | 2026-02-04 | Node rename broke cluster filesystem | Changed hostname before stopping pve-cluster |
| 2 | [TS-PVE-002](2-proxmox-ssl-certificate.md) | 2026-02-20 | SSL certificate has wrong IP in SAN | /etc/hosts not updated after IP change |
| 3 | [TS-PVE-003](3-vm-ssh-permission-denied-cloud-init.md) | 2026-03-05 | FreeIPA users can't SSH to VMs | Cloud-init disables password authentication |
| 4 | [TS-PVE-004](4-proxmox-lxc-snapshot-nfs-mount.md) | 2026-03-08 | LXC snapshot fails with NFS mount point | NFS storage doesn't support snapshots |
| 5 | [TS-PVE-005](5-proxmox-backup-missed-not-retried.md) | 2026-03-20 | Backup not running when expected | Missing `repeat-missed` flag on laptop node |
| 6 | [TS-PVE-006](6-lxc-mount-point-backup-disabled.md) | 2026-03-20 | LXC mount point not included in backups | Terraform provider defaults backup=false |
| 7 | [TS-PVE-007](7-crontab-overwrite-recovery.md) | 2026-03-22 | Cron jobs disappeared after adding new one | `crontab -` replaces instead of appends |
| 8 | [TS-PVE-008](8-lvm-thin-pool-resize-overcommit.md) | 2026-03-23 | LVM thin pool warnings and 97% assigned | No auto-extend, pool oversized for actual usage |
| 9 | [TS-PVE-009](9-nfs-shutdown-hang-stor0-hotswap.md) | 2026-03-23 | System hangs on shutdown during USB adapter hot-swap | NFS hard mounts wait indefinitely |
| 10 | [TS-PVE-010](10-vm-restore-hang-concurrent-nfs-operations.md) | 2026-03-26 | VM restore stuck at 100% | Too many concurrent NFS operations |
| 11 | [TS-PVE-011](11-vmbr1-storage-network-for-k8s-workers.md) | 2026-03-27 | VMs can't reach storage VLAN | No bridge for VLAN 40, GUI can't do atomic changes |
| 12 | [TS-PVE-012](12-vm-autostart-timeout-nfs-disk-not-ready.md) | 2026-04-06 | VM autostart timeout after reboot | NFS mount not ready when autostart begins |

---

## Quick Reference

### Node & Certificate
- **Case 1:** Node rename → Stop pve-cluster BEFORE changing hostname
- **Case 2:** Wrong SSL IP → Update /etc/hosts, run `pvecm updatecerts --force`

### LXC Containers
- **Case 3:** SSH denied → Enable password auth or use `kinit` for GSSAPI
- **Case 4:** Snapshot fails → Move mount points from NFS to local-lvm
- **Case 6:** Mount not backed up → Set `backup = true` in Terraform

### Backup Operations
- **Case 5:** Backup missed → Enable `repeat-missed` flag
- **Case 6:** Mount excluded → Check backup job details for "No - Disabled"

### System Administration
- **Case 7:** Cron jobs lost → Use `(crontab -l; echo "job") | crontab -` to append

### Storage & LVM
- **Case 8:** LVM warnings → Enable auto-extend, resize thin pool if needed
- **Case 10:** Restore stuck → Limit concurrent NFS operations to 2-3 VMs

### NFS Storage Chain (Cases 9 → 10 → 12)
Related cases covering NFS timing issues:
1. **Case 9:** Shutdown hang → Lazy unmount before hot-swap
2. **Case 10:** Restore hang → Sequential restore, not concurrent
3. **Case 12:** Autostart timeout → Increase startup delay to 180s

### Networking
- **Case 11:** VMs can't reach VLAN → Create VLAN-aware bridge, edit /etc/network/interfaces directly

---

## Related Cases in Other Folders

| Case | Folder | Topic |
|------|--------|-------|
| TS-TF-003 | terraform/ | LXC clone SSH key issue (vzdump template solution) |
| TS-TF-009 | terraform/ | Cloud-init update behavior (requires VM stop) |
| TS-TF-010 | terraform/ | SSH host key regeneration (cloud-init consequence) |

---

## Environment

- **Proxmox VE:** 8.x
- **Nodes:** pve-dev (laptop), pve-prod (laptop)
- **Storage:** local-lvm (thin), NFS (NAS via USB-Ethernet)
- **Network:** vmbr0 (management), vmbr1 (storage VLAN 40)

---

## Best Practices (from lessons learned)

1. **Stop pve-cluster before hostname changes** - Cluster filesystem requires hostname match
2. **Update /etc/hosts before certificate regeneration** - Certificate reads IP from hosts file
3. **Use local-lvm for volumes needing snapshots** - NFS doesn't support snapshots
4. **Enable `repeat-missed` on laptop nodes** - Backups run when node comes online
5. **Set `backup = true` explicitly in Terraform** - Provider defaults to false
6. **Enable LVM auto-extend** - Prevents thin pool exhaustion
7. **Lazy unmount before NFS adapter hot-swap** - Prevents shutdown hang
8. **Restore VMs sequentially from NFS** - Max 2-3 concurrent operations
9. **Use `crontab -e` or append syntax** - `crontab -` replaces entire file
10. **Increase startup delay for NFS-backed VMs** - Allow mount to initialize
