Proxmox vzdump Backup — Scheduler to NAS Archive (Summary Trace)
=================================================================

pre-trace (one-time setup):
  NAS at 10.0.40.120 (VLAN 40) registered as NFS storage in Proxmox
    → backup job in /etc/pve/jobs.cfg: snapshot mode, ZSTD, repeat-missed=1, keep_last=5
    → dev: explicit VMID list (k8s excluded), prod: all VMs/LXCs

Thursday or Saturday 21:00 → pvescheduler reads jobs.cfg
  → if host was offline: repeat-missed=1 retries on wake (TS-PVE-005)

→ for each VMID sequentially:
    → guest agent fs-freeze (2-5s, writes queued)
      → LVM snapshot created (instant, copy-on-write)
        → fs-thaw → VM fully running again

    → vzdump reads disk blocks from LVM snapshot
      → ZSTD compression: sparse blocks skipped instantly, dense blocks read fully
        → FreeIPA: 50GB → 1.63GB (91% sparse, 1:17)
        → k8s worker: 105GB → 1.06GB (97% sparse, 2:46)
        → IO impact: prod <8% (enterprise NVMe), dev 33-38% (consumer NVMe)
          → dev k8s nodes excluded (TS-PVE-020: dense data → IO storm → etcd heartbeat failure)
        → CPU: idle 65°C → peak 92°C (TS-PVE-015: thermal threshold rewritten to 90°C + backup-aware)

    → .vma.zst written to NAS via NFS
      → Proxmox (VLAN 40) → USB-Ethernet adapter → MikroTik → NAS eth1.40
        → /volume1/{env}-storage/dump/vzdump-qemu-<vmid>-*.vma.zst

    → LVM snapshot removed → next VMID

→ retention pruning: keep_last=5 per VMID → older archives deleted from NAS
→ email notification: per-VM status (OK/ERROR), archive size, duration
  → if interrupted mid-backup: failed VM logged with error (TS-PVE-015: "interrupted by signal")

→ Scenario 2: Veeam backup (PoC v1 VMware, retired)
  → Veeam connects to vCenter → triggers VMware snapshot → VMDK splits:
    base.vmdk (frozen, read-only) + delta.vmdk (active writes)
      → Veeam reads base via VDDK → compresses + dedups → .vbk to repository
        → snapshot removed → delta merged back into base (consolidation IO)

  → incremental via CBT (Changed Block Tracking):
    VMware kernel bitmap tracks changed blocks since last backup
      → Veeam reads only deltas → .vib chained to .vbk
        → massive IO advantage: 200MB-2GB incremental vs vzdump full-disk read every run
          → trade-off: CBT bitmap can corrupt, periodic active full resets chain

  → snapshot chain problem:
    base.vmdk → delta-000001 → delta-000002 (nested if multiple snapshots)
      → reads traverse chain top-down → 3+ layers = latency increase
        → orphaned snapshots = silent chain growth (PoC v1: TS-01, TS-03, TS-07)
    → VMFS locking: SCSI reservations / ATS per-file during snapshot ops
      → lock contention on shared storage = snapshot create pauses VM IO (10-30s)

  → abandoned: 10-VM Community Edition limit, snapshot chain overhead
    → vzdump simpler: full read + ZSTD + LVM snapshot (instant remove, zero chain risk)
