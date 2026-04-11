# TS-PVE-012 | 2026-04-06 | RESOLVED

> **REAL INCIDENT** — This case occurred during an unplanned production failure (power outage recovery), not planned DR testing. Documented before DR test phase began.

## 1. Context
- System: Proxmox VE autostart with NFS storage
- Environment: pve-dev
- Related components: VM 1001 (freeipa), NFS storage (nas-dev-data), QEMU autostart

## 2. Issue
- Symptom: FreeIPA VM (1001) failed to start during Proxmox autostart sequence after system reboot. Manual start ~15 minutes later succeeded immediately.
- Error:
```
Status:        stopped: start failed: command '/usr/bin/kvm ...' failed: got timeout
Task type:     qmstart
Duration:      38s
```

**Note:** No explicit NFS mount errors found in logs. Root cause is suspected based on behavioral pattern, not confirmed with direct evidence.

## 3. Analysis

### Timeline

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

### VM Disk Configuration

VM 1001 has disk on NFS:
- `scsi0`: local-lvm (OS disk)
- `scsi1`: nas-dev-data (data disk at `/mnt/pve/nas-dev-data/images/1001/vm-1001-disk-0.raw`)

### Behavioral Pattern Analysis

| Observation | Implication |
|-------------|-------------|
| Autostart at 23:01:40 failed | Disk inaccessible or slow |
| Manual start at 23:17:00 succeeded instantly | Disk accessible by then |
| VM has disk on NFS storage | Depends on NFS mount |
| NFS mount timestamp 23:01:41 | Mount was initializing |
| No explicit NFS errors in logs | QEMU just timed out silently |

### Why No NFS Errors in Logs

QEMU/KVM does not log "file not found" or "mount not ready" errors explicitly. When a blockdev cannot be opened:
1. QEMU attempts to open the file
2. If NFS is not ready, the open() call hangs
3. After timeout, QEMU returns generic "got timeout" error
4. No specific I/O or mount error is logged

## 4. Root Cause
> Proxmox autostart ran before NFS storage was fully operational. QEMU attempted to open the NFS-backed disk file, hung waiting for I/O, and timed out after ~36 seconds.

## 5. Solution
> Increase VM startup delay to allow NFS mount to fully initialize before VM starts.

### Terraform Configuration Changes

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

### Applied to Proxmox

After `terraform apply`, VM startup configuration will be:
```bash
qm config 1001 | grep startup
# startup: order=1,up=180,down=60
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: VM start delayed by 3 minutes after host boot. Acceptable trade-off for reliability.

## 7. Impact After Fix
- Observed: Startup delay increased to 180 seconds
- VM will wait for NFS to be fully ready before starting
- No more timeout failures on autostart

## 8. Notes

### Alternative Solutions Considered

| Solution | Pros | Cons |
|----------|------|------|
| Increase startup delay (chosen) | Simple, reliable | Delays VM start by 3 min |
| systemd mount dependency | Proper dependency chain | Complex to configure |
| Move disk to local storage | No NFS dependency | Loses NFS benefits |
| Retry script | Auto-recovers | Adds complexity |

### Prevention for NFS-backed VMs

For any VM with disks on NFS storage:
1. Set `startup_delay` to at least 120-180 seconds
2. Set `startup_order` to higher number (start later)
3. Consider local disk for OS, NFS only for data

**Terraform pattern for NFS-backed VMs:**
```hcl
startup_delay   = 180  # Wait for NFS
startup_order   = 99   # Start last
```

### Investigation Commands

```bash
# Check Proxmox task logs
grep -r "1001" /var/log/pve/tasks/

# Check journal logs for VM
journalctl -u pvedaemon --since "1 hour ago" | grep 1001

# Check NFS mount status
systemctl status mnt-pve-nas\\x2ddev\\x2ddata.mount

# Check storage configuration
cat /etc/pve/storage.cfg | grep -A10 nas-dev-data

# Check VM startup configuration
qm config 1001 | grep startup
```

**Related:** TS-PVE-009 (NFS shutdown hang), TS-PVE-010 (VM restore hang) - all related to NFS storage timing

## 9. Workaround (if any)
> If VM fails to autostart: Manually start after 2-3 minutes with `qm start <VMID>`. NFS will be ready by then.
