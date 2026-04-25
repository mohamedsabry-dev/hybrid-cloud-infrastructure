# TS-PVE-012 | 2026-04-06 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Proxmox VE autostart / NFS storage
Sub-techs: VM 1001 (freeipa), NFS storage (nas-dev-data), QEMU autostart, Terraform startup config
Environment: pve-dev
Re-opened: Yes -- April 12 follow-up discovered original fix was ineffective

_____________________________________________________________________

[Issue Description]
REAL INCIDENT -- occurred during unplanned power outage recovery, not planned DR testing.

FreeIPA VM (1001) failed to start during Proxmox autostart sequence after system reboot. Manual start ~15 minutes later succeeded immediately.

```
Status:        stopped: start failed: command '/usr/bin/kvm ...' failed: got timeout
Task type:     qmstart
Duration:      38s
```

No explicit NFS mount errors found in logs. Root cause is suspected based on behavioral pattern.

_____________________________________________________________________

[Analysis]
# Step 1: Timeline
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

# Step 2: Check VM disk configuration
VM 1001 has disk on NFS:
- `scsi0`: local-lvm (OS disk)
- `scsi1`: nas-dev-data (data disk at `/mnt/pve/nas-dev-data/images/1001/vm-1001-disk-0.raw`)

# Step 3: Behavioral pattern analysis

| Observation | Implication |
|-------------|-------------|
| Autostart at 23:01:40 failed | Disk inaccessible or slow |
| Manual start at 23:17:00 succeeded instantly | Disk accessible by then |
| VM has disk on NFS storage | Depends on NFS mount |
| NFS mount timestamp 23:01:41 | Mount was initializing |
| No explicit NFS errors in logs | QEMU just timed out silently |

# Step 4: Why no NFS errors
QEMU/KVM does not log "file not found" or "mount not ready" errors explicitly. When a blockdev cannot be opened, the open() call hangs, and after timeout QEMU returns a generic "got timeout" error.

_____________________________________________________________________

[Final Root Cause]
Proxmox autostart ran before NFS storage was fully operational. QEMU attempted to open the NFS-backed disk file, hung waiting for I/O, and timed out after ~36 seconds.

_____________________________________________________________________

[Final Solution]
Initial fix (April 6): Increased `startup_delay` from 60 to 180 seconds in Terraform for VM 1001.

```hcl
# terraform/dev/proxmox/vms/freeipa/variables.tf
# terraform/prod/proxmox/vms/freeipa/variables.tf
startup_delay   = 180
```

CRITICAL DISCOVERY (April 12): The April 6 fix was wrong. The `startup_delay` (Proxmox `up_delay`) delays the NEXT VM, not the current one.

From Terraform Proxmox Provider docs:
```
up_delay - A non-negative number defining the delay in seconds
           before the NEXT VM is started.
```

Old config (broken):
```terraform
# VM 1001 (FreeIPA) - order=1, startup_delay=180
# CT 2001 (Ansible) - order=2, startup_delay=60
```

What actually happened:
```
T+0:00   FreeIPA starts IMMEDIATELY (no delay - it's first!)
         | 180s wait (FreeIPA's up_delay delays Ansible)
T+3:00   Ansible starts (delayed by FreeIPA's setting)
```

FreeIPA was still starting before NFS was ready.

Correct fix (April 13): Swapped the order -- Ansible boots first and its delay holds FreeIPA:

```terraform
# CT 2001 (Ansible) - boots FIRST, delays FreeIPA
startup_order = 1
startup_delay = 300     # 5 min delay for NAS to be ready

# VM 1001 (FreeIPA) - boots SECOND, after delay
startup_order = 2
startup_delay = 60      # Delay next containers
```

New boot sequence:
```
T+0:00   Ansible starts (order 1, local-lvm only - no NFS needed)
         | 300s wait (5 min for NAS to fully initialize)
T+5:00   FreeIPA starts (order 2, NAS now ready for data disk)
         | 60s wait
T+6:00   Next containers...
```

Files changed:
| File | Change |
|------|--------|
| `terraform/dev/proxmox/lxc/ansible/variables.tf` | order: 2->1, delay: 60->300 |
| `terraform/dev/proxmox/vms/freeipa/variables.tf` | order: 1->2, delay: 180->60 |
| `terraform/prod/proxmox/lxc/ansible/variables.tf` | order: 2->1, delay: 60->300 |
| `terraform/prod/proxmox/vms/freeipa/variables.tf` | order: 1->2, delay: 180->60 |

Boot sequence log (April 12, before fix):
```
Apr 12 23:59:29  VM 1001 (FreeIPA) - Start  <- IMMEDIATE, no delay!
         | 180s wait
Apr 13 00:02:30  CT 2001 (Ansible) - Start  <- 3 min later
```

Verified: Yes -- correct fix applied April 13. Ansible boots first with 300s delay, FreeIPA boots second after NAS is ready.

_____________________________________________________________________

[Risk Level] LOW

_____________________________________________________________________

[References]
- Terraform Proxmox Provider: https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm
- Related: TS-PVE-009 (NFS shutdown hang), TS-PVE-010 (VM restore hang) -- NFS storage timing
- Related: TS-PVE-014 -- where `up_delay` behavior was discovered
