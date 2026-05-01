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
| 13 | [TS-PVE-013](13-ups-monitor-cronjob-misconfiguration.md) | 2026-04-07 | UPS monitor cronjob misconfiguration | Wrong cron syntax |
| 14 | [TS-PVE-014](14-worker-vm-crash-unknown-root-cause.md) | 2026-04-11 | Worker VM crash on autostart — 3-part investigation | Remediation pod triggered reboot during boot |
| 15 | [TS-PVE-015](15-vzdump-thermal-shutdown-during-backup.md) | 2026-04-11 | vzdump thermal crash/shutdown during backup (dev+prod) | vzdump zstd compression spikes CPU to 91°C — dev: hard crash (no temp script), prod: graceful shutdown (80°C threshold too aggressive) |
| 16 | [TS-PVE-016](reference/16-proxmox-memory-metrics-misleading.md) | 2026-04-11 | Proxmox shows 97% memory but actual is 54% | Linux cache counted as "used" — normal behavior |
| 17 | [TS-PVE-017](17-proxmox-host-cpu-io-spike-vms-stuck.md) | 2026-04-19 | CPU/IO spike — all VMs hung, 8-hour root cause investigation | Zero IO isolation on shared NVMe + K8s cascade dynamics. Per-VM IO throttling applied via Terraform. |
| 18 | — | — | Merged into TS-PVE-015 | Same root cause (vzdump thermal spike) |
| 19 | [TS-PVE-019](19-worker3-vm-config-drift.md) | 2026-04-24 | Worker3 (1022) config drift — ide2/scsi0 changed between Apr 16-18 | qmrestore on LVM-thin renames cloud-init volume to disk-0 (loses CloudInit Drive type) |
| 20 | [TS-PVE-020](20-vzdump-backup-destabilizes-k8s-cluster.md) | 2026-04-24 | vzdump backup destabilizes k8s cluster — IO 50-70%, control plane crashes | K8s VM disks have dense data (not sparse like IPA's 91% zeros) causing sustained NVMe IO contention |
| 21 | [TS-PVE-021](reference/21-tf-disk-size-below-golden-image.md) | 2026-05-01 | Terraform apply failed — disk resize below golden image base | OS disk 15GB < golden image 20GB. Proxmox can't shrink cloned disk. Left stale tfstate, re-apply fixed it. |

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
- **Case 20:** vzdump crashes k8s → Exclude k8s nodes from backup (dense data = sustained IO), keep IPA + LXCs only

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

### Monitoring & Metrics
- **Case 16:** Memory shows 97% → Linux cache counted as used — use Prometheus `MemAvailable`, NOT Proxmox metrics for CloudWatch integration

### Terraform & Provisioning
- **Case 21:** Disk resize failure → OS disk size must be >= golden image base (20GB). Terraform plan won't catch it — fails at apply after clone.

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

