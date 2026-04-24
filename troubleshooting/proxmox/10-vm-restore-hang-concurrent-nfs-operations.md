# TS-PVE-010 | 2026-03-26 | RESOLVED | INCIDENT
_____________________________________________________________________

[Info]
Domain: Proxmox VE / NFS backup storage
Sub-techs: vzdump, qmrestore, NFS storage (stor0), LVM thin pool
Environment: pve-dev -- multiple VM restores from NFS backup storage
Re-opened: No

_____________________________________________________________________

[Issue Description]
VM restore operations stuck at 100% for 10+ minutes. I started 6 VM restore operations simultaneously, and they all stalled. Cancelling stuck tasks left orphaned LVM volumes, blocking subsequent restore attempts.

```
Logical Volume "vm-1012-cloudinit" already exists in volume group "pve"
```

Additional symptoms:
- Proxmox Web UI shows restore task "running" but no progress
- Subsequent restore attempts failed with LVM errors

_____________________________________________________________________

[Analysis]
# Step 1: Reconstruct what happened
When I started 6 VM restore operations simultaneously:
1. NFS storage (stor0) became I/O bottleneck
2. Restore processes competed for NFS bandwidth
3. Operations stalled waiting for NFS responses
4. I cancelled stuck tasks mid-operation
5. LVM volumes created but not cleaned up (orphaned)

# Step 2: Evidence from task logs
```
6 concurrent qmrestore operations started
4 failed with "unexpected status" (cancelled)
2 qmstart failed with "received interrupt"
```

_____________________________________________________________________

[Final Root Cause]
Too many concurrent restore operations overwhelmed NFS storage. Cancelling stuck tasks mid-operation left orphaned LVM volumes that blocked subsequent restore attempts.

_____________________________________________________________________

[Final Solution]
I cancelled stuck tasks, removed orphaned LVM volumes, and retried restores sequentially.

Step 1: Cancel stuck tasks from Proxmox Web UI (Task View -> Select stuck task -> Stop) or CLI:
```bash
pvesh get /cluster/tasks
pvesh delete /nodes/<node>/tasks/<upid>
```

Step 2: Identify orphaned LVM volumes
```bash
lvs | grep vm-1012
```
```
vm-1012-cloudinit  pve  -wi-a-----   4.00m
vm-1012-disk-0     pve  -wi-a-----  32.00g
```

Step 3: Remove orphaned volumes
```bash
# VM 1012
lvremove -f pve/vm-1012-cloudinit
lvremove -f pve/vm-1012-disk-0

# VM 1022
lvremove -f pve/vm-1022-cloudinit
lvremove -f pve/vm-1022-disk-0

# Repeat for other affected VMs
```

Step 4: Retry restore sequentially
```bash
qmrestore /mnt/pve/stor0/dump/vzdump-qemu-1012-*.vma.zst 1012
# Wait for completion, then next
qmrestore /mnt/pve/stor0/dump/vzdump-qemu-1022-*.vma.zst 1022
```

If restore hangs in the future:
- Wait 5 minutes (may be slow, not stuck)
- Check NFS connectivity: `ping <nfs-server>`
- Check NFS I/O: `nfsiostat 1`
- If truly stuck, cancel task from UI
- List orphaned LVM: `lvs | grep vm-<VMID>`
- Remove orphaned LVM: `lvremove -f pve/vm-<VMID>-*`
- Retry restore individually

Verified: Yes -- VMs restored successfully with sequential approach.

_____________________________________________________________________

[Risk Level] LOW -- data loss possible if wrong LVM volumes removed. Always verify VMID before `lvremove`.

_____________________________________________________________________

[References]
- Related: TS-PVE-009 (NFS shutdown hang) -- NFS storage hang during shutdown
