# TS-PVE-019 | 2026-04-24 | RESOLVED | CONFIG DRIFT
_____________________________________________________________________

[Info]
Domain: Proxmox VE / VM Configuration Integrity
Sub-techs: VM 1022 (k8s-worker3), cloud-init, LVM-thin, qmrestore, vzdump,
           remediation controller
Environment: DEV Proxmox server (pve-dev)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Worker3 (VM 1022) had config drift compared to worker1 (1020) and worker2 (1021).
Discovered during TS-PVE-017 IO throttle remediation session while comparing VM
configs across all 6 K8s nodes in the Proxmox GUI.

Drift items:

| Setting | Correct (worker1/2) | Drifted (worker3) |
|---------|--------------------|--------------------|
| ide2 | `CloudInit Drive: local-lvm:vm-10XX-cloudinit,size=4M` | `Hard Disk: local-lvm:vm-1022-disk-0,size=4M` |
| scsi0 ssd flag | `ssd=1` present | `ssd=1` missing |
| scsi0 size | `size=25G` present | `size=25G` missing |

The ide2 change was the most concerning — cloud-init disk type was lost entirely,
replaced with a generic hard disk that Proxmox doesn't recognize as cloud-init.

_____________________________________________________________________

[Analysis]

# Step 1: When did the drift happen?

Compared Proxmox backup configs:
- **April 16 backup**: correct — `ide2: local-lvm:vm-1022-cloudinit,size=4M`
- **April 18 backup**: drifted — `ide2: local-lvm:vm-1022-disk-0,size=4M`

Drift window: between 2026-04-16 and 2026-04-18. This overlaps exactly with the
first IO storm (TS-PVE-017, April 17).

# Step 2: Is Terraform the source?

No. Checked `terraform/dev/proxmox/vms/k8s_workers/`:
- `main.tf` defines all 3 workers identically (same disk block, same structure)
- `variables.tf`: `size = 25`, `ssd = true`, `discard = "on"`, `interface = "scsi0"`
- `initialization {}` block creates the cloud-init disk (ide2) implicitly
- All 3 workers share the same `disks.os_disk` variable — no worker3-specific override
- Terraform is correct and consistent — drift happened at the Proxmox layer

# Step 3: Journal evidence — the exact sequence

`journalctl -u pvedaemon --since "2026-04-16" --until "2026-04-19" | grep 1022`

Full timeline of operations on VM 1022 during the drift window:

## Phase 1: DR testing (Apr 17 22:30 - 23:19)
Multiple shutdown/start/VNC cycles — me (`admin_dev@pam`) manually testing while
the remediation controller kept detecting worker3 as unhealthy and restarting it.

## Phase 2: Remediation controller failed clone (Apr 17 23:23 - 23:26)
```
23:23:33  qmstop 1022     (remediation force-stopped)
23:24:03  qmclone 1022    (remediation cloning → target VM 5022)
23:25:04  qmdestroy 1022  (remediation DESTROYING while clone still running!)
23:25:14  FAILED: "can't lock file lock-1022.conf - got timeout"
23:26:39  CLONE FAILED: "qemu-img convert -p -n -f raw -O raw
          /dev/pve/vm-1022-disk-0 zeroinit:/dev/pve/vm-5022-disk-0
          ... interrupted by signal"
```

Race condition in the remediation controller: it fired stop → clone → destroy
without waiting for the clone to finish. The destroy killed the qemu-img process
mid-copy.

## Phase 3: My manual clone retry (Apr 17 23:35 - 23:41)
```
23:35:05  qmclone 1022  (admin_dev@pam — I manually retried)
23:41:50  Clone OK
```

## Phase 4: THE DRIFT EVENT — remediation destroy + restore (Apr 18 00:06)
```
00:06:14  qmstop 1022      (remediation)
00:06:45  qmdestroy 1022   (remediation) → ended OK but logged:
                           "disk image .../vm-1022-disk-1.raw does not exist"
                           "disk image .../vm-1022-disk-0.raw does not exist"
00:06:55  qmrestore 1022   (remediation) ← THIS IS THE DRIFT EVENT
00:10:21  qmstart 1022     (remediation) → OK
```

The remediation controller ran a full destroy-and-restore cycle. The `qmrestore`
at 00:06:55 recreated VM 1022 from a vzdump backup. This is when the cloud-init
disk type and scsi0 flags were lost.

# Step 4: Why qmrestore loses cloud-init

This is a Proxmox vzdump/qmrestore behavior on LVM-thin storage. Here's the
mechanism:

**How cloud-init is created (by Terraform or GUI):**
When Terraform creates a VM with an `initialization {}` block, or when I add
a CloudInit Drive through the Proxmox GUI, Proxmox creates a special LVM volume
named `vm-1022-cloudinit`. The naming convention is what makes Proxmox recognize
it as a CloudInit Drive — the volume name must end in `-cloudinit`.

The config file stores: `ide2: local-lvm:vm-1022-cloudinit,size=4M`

**How vzdump backs it up:**
vzdump saves the raw disk data and the config file into the `.vma.zst` archive.
The config inside the backup correctly says `ide2: local-lvm:vm-1022-cloudinit`.
The backup is correct.

**How qmrestore breaks it:**
When restoring to LVM-thin, qmrestore needs to create NEW LVM logical volumes
(it can't reuse old names because LVM allocates fresh volumes). It names them
sequentially: `vm-1022-disk-0`, `vm-1022-disk-1`, etc. — regardless of what
the original volume was called.

The cloud-init volume `vm-1022-cloudinit` becomes `vm-1022-disk-0`. Proxmox
no longer recognizes it as a CloudInit Drive because the volume name doesn't
end in `-cloudinit`. It shows up as a regular "Hard Disk" in the GUI.

The config gets rewritten: `ide2: local-lvm:vm-1022-disk-0,size=4M`

The DATA is identical — the cloud-init ISO is correctly restored. But the
VOLUME NAME is wrong, so Proxmox treats it as a normal disk.

Same mechanism lost `ssd=1` and `size=25G` from scsi0 — qmrestore rewrites
disk config lines with its own defaults and doesn't carry forward all flags.

**Why I haven't seen this before:**
I've restored VMs before and cloud-init was fine. The difference might be that
those were Proxmox GUI-initiated restores which handle cloud-init specially, or
restores to directory storage (where filenames are preserved), or VMs where I
didn't check closely enough. The remediation controller does automated API-level
restores which may skip the cloud-init handling that the GUI restore adds.

This needs more testing to confirm whether it's specific to API-level restores
or all LVM-thin restores. For now, the practical fix is documented below.

# Step 5: Fix attempts

## Attempt 1: Restore over existing VM (FAILED)
Restored from April 16 backup directly over the existing drifted VM.
```
VM 1022 add unreferenced volume 'local-lvm:vm-1022-disk-1' as 'unused0' to config
VM 1022 add unreferenced volume 'local-lvm:vm-1022-disk-2' as 'unused1' to config
TASK OK
```
Result: ide2 still showed as `Hard Disk (vm-1022-disk-0)` — not CloudInit Drive.
The restore found conflicting volumes from the previous state and added them as
unreferenced instead of cleanly replacing. Restoring over an existing VM with
leftover volumes doesn't produce a clean config.

## Attempt 2: `qm set --ide2 local-lvm:cloudinit` (WRONG FORMAT)
Tried manually creating a new cloud-init drive:
```bash
qm set 1022 --ide2 local-lvm:cloudinit
```
Result: Proxmox created the cloud-init volume correctly (`vm-1022-cloudinit`) and
the GUI showed "CloudInit Drive (ide2)" — but with `media=cdrom` instead of
`size=4M`. The correct format (matching worker1/worker2) is `size=4M`.
This is because `qm set --ide2 local-lvm:cloudinit` uses Proxmox's default
cloud-init format which is cdrom media type.

## Attempt 3: Clean destroy + restore from April 16 backup (PARTIAL)
Full clean slate:
```bash
qm stop 1022
qm destroy 1022 --purge
qmrestore <vzdump-qemu-1022-2026_04_16.vma.zst> 1022
```
Result: scsi0 was restored correctly this time (`ssd=1`, `size=25G` present).
But ide2 STILL came back as `Hard Disk (vm-1022-disk-0)` — not CloudInit Drive.

This confirmed it's a fundamental qmrestore behavior, not related to degraded
system state or leftover volumes. Even a clean destroy+restore from a known-good
backup loses the cloud-init volume naming on LVM-thin.

## Attempt 4: Manual qm set commands (SUCCESS)
After the clean restore fixed scsi0, manually fixed ide2:
```bash
# Step 1: Delete the wrongly-typed regular disk from ide2
qm set 1022 --delete ide2

# Step 2: Create a proper cloud-init drive (creates vm-1022-cloudinit volume)
qm set 1022 --ide2 local-lvm:cloudinit
# → This created it with media=cdrom (wrong format)

# Step 3: Override to match worker1/worker2 format
qm set 1022 --ide2 local-lvm:vm-1022-cloudinit,size=4M
# → This changed the config reference to size=4M (correct format)
```

Then applied IO throttle values to scsi0:
```bash
qm set 1022 -scsi0 local-lvm:vm-1022-disk-1,aio=io_uring,cache=none,discard=on,iops_rd=500,iops_rd_max=1500,iops_wr=300,iops_wr_max=800,mbps_rd=30,mbps_rd_max=80,mbps_wr=20,mbps_wr_max=40,size=25G,ssd=1
```

Final config matches worker1 exactly:
- `ide2`: CloudInit Drive → `local-lvm:vm-1022-cloudinit,size=4M`
- `scsi0`: Hard Disk → `local-lvm:vm-1022-disk-1,...,size=25G,ssd=1` + IO throttle

Verified: Yes — GUI shows CloudInit Drive with correct format.

_____________________________________________________________________

[Impact]

**Functional impact**: Low. Cloud-init only runs on first boot, so the drifted
config didn't affect the running VM. The missing `ssd=1` flag meant the guest OS
used the wrong IO scheduler (not SSD-optimized), which could have contributed to
slightly worse IO performance on worker3 during the 6 days the drift existed.

**Integrity impact**: MEDIUM. The drift was caused by a logged operation
(remediation controller's qmrestore), not silent corruption. Journal confirms
this only happened to VM 1022. Other VMs are not affected.

**Remediation controller risk**: HIGH. Two separate issues:
1. Race condition: clone and destroy ran concurrently (lock timeout, interrupted
   qemu-img). The controller needs to wait for clone completion before destroying.
2. qmrestore loses cloud-init: any VM restored by the controller will have its
   cloud-init disk type silently converted to a regular disk. The controller should
   run post-restore validation or use `qm set` to re-create the cloud-init drive
   after every restore.

_____________________________________________________________________

[Final Solution]

Clean destroy + restore from April 16 backup recovered scsi0 config (`ssd=1`,
`size=25G`). Manual `qm set` commands fixed the cloud-init ide2 drive that
qmrestore cannot restore correctly on LVM-thin storage.

Full command sequence:
```bash
# 1. Clean restore (fixes scsi0, does NOT fix ide2)
qm stop 1022
qm destroy 1022 --purge
qmrestore <vzdump-qemu-1022-2026_04_16.vma.zst> 1022

# 2. Fix ide2 cloud-init (qmrestore can't do this)
qm set 1022 --delete ide2
qm set 1022 --ide2 local-lvm:cloudinit
qm set 1022 --ide2 local-lvm:vm-1022-cloudinit,size=4M

# 3. Apply IO throttle values from TS-PVE-017 remediation
qm set 1022 -scsi0 local-lvm:vm-1022-disk-1,aio=io_uring,cache=none,discard=on,iops_rd=500,iops_rd_max=1500,iops_wr=300,iops_wr_max=800,mbps_rd=30,mbps_rd_max=80,mbps_wr=20,mbps_wr_max=40,size=25G,ssd=1

# 4. Start VM
qm start 1022
```

Verified: config matches worker1/worker2 exactly.

_____________________________________________________________________

[Key Lesson — qmrestore and cloud-init on LVM-thin]

vzdump correctly backs up the config saying `ide2: local-lvm:vm-1022-cloudinit`.
But qmrestore creates NEW LVM volumes with sequential names (`disk-0`, `disk-1`)
and never re-creates the `-cloudinit` naming convention. Proxmox identifies
CloudInit Drives by volume name — no `-cloudinit` suffix = regular Hard Disk.

This means: **any VM restored via qmrestore on LVM-thin will lose its cloud-init
drive type**. The data is preserved (the ISO content is intact), but Proxmox no
longer recognizes it as cloud-init. The fix after every LVM-thin restore is:
```bash
qm set <vmid> --delete ide2
qm set <vmid> --ide2 local-lvm:cloudinit
qm set <vmid> --ide2 local-lvm:vm-<vmid>-cloudinit,size=4M
```

This should be added as a post-restore step in any restore procedure, and the
remediation controller should do this automatically after every qmrestore.

_____________________________________________________________________

[Risk Level] LOW (resolved)

Config drift fixed and verified. Root cause understood. Remaining risk is the
remediation controller doing future restores without post-restore cloud-init fix.

_____________________________________________________________________

[References]
- TS-PVE-017 — IO storm that preceded the drift (remediation controller activated
  during this incident)
- TS-PVE-020 — vzdump backup destabilizes k8s cluster (suspect amplifier — see update below)
- TS-K8S-030 — Worker3 OOM crashes on April 13-14 (prior instability, same VM)
- TS-PVE-014 — Worker VM crash/restart via remediation pod (same controller)
- Terraform source: `terraform/dev/proxmox/vms/k8s_workers/` (confirmed correct)

_____________________________________________________________________

[Update — 2026-04-24]

The drift window (April 16-18) overlaps with the Thursday April 17 scheduled backup
(thu,sat 21:00). TS-PVE-020 confirmed that vzdump backup of k8s nodes on the dev server
causes sustained IO saturation and cluster instability — dense data on the shared consumer
NVMe starves all other VMs. If the Thursday backup triggered enough instability for the
remediation controller to see worker3 as NotReady, that would explain why the controller
activated and did the qmrestore that caused the drift. The backup IO didn't cause the
config drift directly (qmrestore's volume rename behavior did), but it's a suspect trigger
for the remediation chain that led to it.

K8s nodes have since been excluded from the dev backup job (TS-PVE-020 solution), which
removes this trigger path entirely.
