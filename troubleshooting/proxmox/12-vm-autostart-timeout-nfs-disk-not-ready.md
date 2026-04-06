# Case 12: VM Autostart Timeout - NFS Disk Not Ready After Reboot

## Status: RESOLVED (Suspected Root Cause)
## Date: 2026-04-06
## Severity: Medium
## Environment: pve-dev (Proxmox VE)
## Affected: VM 1001 (freeipa)

---

## 1. Issue Summary

FreeIPA VM (1001) failed to start during Proxmox autostart sequence after system reboot. The VM has a secondary disk on NFS storage (`nas-dev-data`). Autostart failed with "got timeout" after 38 seconds. Manual start ~15 minutes later succeeded immediately.

**Suspected Root Cause:** NFS storage mount not fully ready when autostart sequence began. QEMU timed out waiting for disk file access.

**Note:** No explicit NFS mount errors found in logs. Root cause is suspected based on behavioral pattern, not confirmed with direct evidence.

**Resolution:** Increased VM startup delay from 60 to 180 seconds in Terraform configuration.

---

## 2. Symptoms

- VM 1001 failed to start during autostart sequence
- Error: "got timeout" after 38 seconds
- Manual start 15 minutes later succeeded immediately
- No explicit NFS mount errors in system logs

---

## 3. Evidence

### 3.1 Failed Autostart Task (Proxmox Web UI)

```
Status:        stopped: start failed: command '/usr/bin/kvm ...' failed: got timeout
Task type:     qmstart
User name:     root@pam
Node:          pve-dev
Start Time:    2026-04-06 23:01:40
End Time:      2026-04-06 23:02:18
Duration:      38s
Unique task ID: UPID:pve-dev:00000540:00000502:69D41F34:qmstart:1001:root@pam:
```

### 3.2 Journal Logs - Failed Start

```bash
Apr 06 23:01:40 pve-dev pvesh[1340]: Starting VM 1001
Apr 06 23:01:40 pve-dev pve-guests[1343]: <root@pam> starting task UPID:pve-dev:00000540:00000502:69D41F34:qmstart:1001:root@pam:
Apr 06 23:01:41 pve-dev systemd[1]: Created slice qemu.slice - Slice /qemu.
Apr 06 23:01:41 pve-dev systemd[1]: Started 1001.scope.
Apr 06 23:02:16 pve-dev pve-guests[1344]: start failed: ... got timeout
Apr 06 23:02:54 pve-dev systemd[1]: 1001.scope: Deactivated successfully.
```

### 3.3 Journal Logs - Successful Manual Start

```bash
Apr 06 23:17:00 pve-dev pvedaemon[11784]: start VM 1001: UPID:pve-dev:00002E08:00016C6D:69D422CC:qmstart:1001:admin_dev@pam:
Apr 06 23:17:01 pve-dev pvedaemon[11784]: VM 1001 started with PID 11818.
Apr 06 23:17:01 pve-dev pvedaemon[1314]: <admin_dev@pam> end task ... OK
```

### 3.4 VM Disk Configuration

```bash
root@pve-dev:~# cat /etc/pve/storage.cfg | grep -A10 nas-dev-data
nfs: nas-dev-data
        export /volume1/dev-storage
        path /mnt/pve/nas-dev-data
        server 10.0.40.120
        content backup,rootdir,images
        nodes pve-dev
        prune-backups keep-last=5
```

VM 1001 has disk on NFS:
- `scsi0`: local-lvm (OS disk)
- `scsi1`: nas-dev-data (data disk at `/mnt/pve/nas-dev-data/images/1001/vm-1001-disk-0.raw`)

### 3.5 NFS Mount Status (After Boot)

```bash
root@pve-dev:~# systemctl status mnt-pve-nas\\x2ddev\\x2ddata.mount
● mnt-pve-nas\x2ddev\x2ddata.mount - /mnt/pve/nas-dev-data
     Loaded: loaded (/proc/self/mountinfo)
     Active: active (mounted) since Mon 2026-04-06 23:01:41 EET; 1h 7min ago
      Where: /mnt/pve/nas-dev-data
       What: 10.0.40.120:/volume1/dev-storage
```

**Note:** Mount shows active at 23:01:41, but autostart began at 23:01:40. The 1-second difference and NFS initialization time may explain the timeout.

---

## 4. Timeline

```
23:01:40  Autostart task begins (root@pam)
23:01:41  qemu.slice created, 1001.scope started
23:01:41  NFS mount shows as active (may not be fully ready)
23:02:16  QEMU timeout (36 seconds trying to access disk)
23:02:18  Task marked as failed
23:02:54  Cleanup - 1001.scope deactivated

    ~15 minutes gap

23:17:00  Manual start by admin_dev@pam
23:17:01  VM started successfully with PID 11818
```

---

## 5. Behavioral Pattern Analysis

| Observation | Implication |
|-------------|-------------|
| Autostart at 23:01:40 failed | Disk inaccessible or slow |
| Manual start at 23:17:00 succeeded instantly | Disk accessible by then |
| VM has disk on NFS storage | Depends on NFS mount |
| NFS mount timestamp 23:01:41 | Mount was initializing |
| No explicit NFS errors in logs | QEMU just timed out silently |

**Conclusion:** Proxmox autostart ran before NFS was fully operational. QEMU attempted to open the NFS-backed disk file, hung waiting for I/O, and timed out after ~36 seconds.

---

## 6. Why No NFS Errors in Logs

QEMU/KVM does not log "file not found" or "mount not ready" errors explicitly. When a blockdev cannot be opened:
1. QEMU attempts to open the file
2. If NFS is not ready, the open() call hangs
3. After timeout, QEMU returns generic "got timeout" error
4. No specific I/O or mount error is logged

This makes diagnosing NFS-related VM start failures challenging.

---

## 7. Resolution

### 7.1 Immediate Fix

Increased VM startup delay from 60 to 180 seconds (3 minutes) to allow NFS mount to fully initialize before VM starts.

### 7.2 Terraform Configuration Changes

**File: `terraform/dev/proxmox/vms/freeipa/variables.tf`**
```hcl
# Before
startup_delay   = 60

# After
startup_delay   = 180
```

**File: `terraform/prod/proxmox/vms/freeipa/variables.tf`**
```hcl
# Before
startup_delay   = 60

# After
startup_delay   = 180
```

### 7.3 Applied to Proxmox

After `terraform apply`, VM startup configuration will be:
```bash
qm config 1001 | grep startup
# startup: order=1,up=180,down=60
```

---

## 8. Alternative Solutions Considered

| Solution | Pros | Cons |
|----------|------|------|
| Increase startup delay (chosen) | Simple, reliable | Delays VM start by 3 min |
| systemd mount dependency | Proper dependency chain | Complex to configure |
| Move disk to local storage | No NFS dependency | Loses NFS benefits |
| Retry script | Auto-recovers | Adds complexity |

---

## 9. Commands Reference

### Check VM Startup Config
```bash
qm config 1001 | grep startup
```

### Manually Set Startup Delay
```bash
qm set 1001 --startup order=1,up=180,down=60
```

### Check NFS Mount Status
```bash
systemctl status mnt-pve-nas\\x2ddev\\x2ddata.mount
mount | grep nas-dev-data
```

### Check VM Task Logs
```bash
grep "1001" /var/log/pve/tasks/active
journalctl | grep -i "1001" | tail -50
```

### View Failed Task Details
```bash
cat /var/log/pve/tasks/active | grep "qmstart:1001"
```

---

## 10. Prevention

For any VM with disks on NFS storage:
1. Set `startup_delay` to at least 120-180 seconds
2. Set `startup_order` to higher number (start later)
3. Consider local disk for OS, NFS only for data

**Terraform pattern for NFS-backed VMs:**
```hcl
startup_delay   = 180  # Wait for NFS
startup_order   = 99   # Start last
```

---

## 11. Related Issues

- Case 9: NFS Shutdown Hang (stor0 hotswap)
- Case 10: VM Restore Hang (concurrent NFS operations)
- Kubernetes Case 13: CSI NFS Restart Stale Mount

All related to NFS storage timing and availability.

---

## 12. Status

**RESOLVED** - Startup delay increased to 180 seconds in Terraform configuration (dev and prod).

**Monitoring:** Will verify fix on next system reboot.
