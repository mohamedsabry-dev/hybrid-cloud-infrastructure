# Backup Performance Test — Network Isolation (2026-03-15)

> **Scope note:** This test was run early in the build (March 2026) before
> the k8s cluster had real workloads. It only checked **network isolation**
> — whether backup traffic stays on VLAN 40 and doesn't leak to management
> or service networks. It passed.
>
> What it did NOT test was **NVMe IO contention** — the real problem that
> surfaced in April 2026 once k8s nodes had dense data. That investigation
> is in [`../../../troubleshooting/proxmox/20-vzdump-backup-destabilizes-k8s-cluster.md`](../../../troubleshooting/proxmox/20-vzdump-backup-destabilizes-k8s-cluster.md)
> and changed the backup config significantly (k8s nodes excluded on dev).

---

## Test Setup

- **Date:** 2026-03-15
- **Target:** VMID 1022 (k8s-worker3, 105 GB total: 25G local-lvm + 80G NAS)
- **Mode:** Snapshot, ZSTD compression
- Monitored NAS (eth1.40 storage + eth0 mgmt), Proxmox (stor0.40 + wlp1s0), K8s worker disk IO
- Baseline (60s no backup) then backup run (120s)

## Results

**Archive:** 1.08 GB (97% sparse) in 2:58

| Target | Baseline | During Backup | Verdict |
|--------|----------|---------------|---------|
| NAS eth1.40 (storage VLAN 40) | 0-5 KB/s | 130 KB/s → 115 MB/s peak | Backup traffic here |
| NAS eth0 (management VLAN 5) | 0-17 KB/s | 0 KB/s | No leak |
| Proxmox stor0.40 | 8-15 Kb/s | 1.04 Mb/s avg | Correct path |
| Proxmox wlp1s0 (management) | ~80 Kb/s | ~78 Kb/s | No leak |
| NAS CPU/iowait | 99.25% idle | 98.75% idle | Minimal load |
| K8s worker sdb I/O | 0% util | 0% util | No impact |

### What this proved

1. **Network isolation works** — all backup traffic on VLAN 40, zero leakage to management or service networks
2. **NAS handles it fine** — NVMe storage barely stressed during backup
3. **Worker disk unaffected** — 0% utilization during backup

### What this missed

This test ran on a k8s worker that was 97% sparse (empty disk, no real workloads yet).
The "no impact" conclusion was correct for sparse VMs but didn't hold once k8s nodes
had dense data (container images, overlay fs, etcd WAL). The full IO investigation
came later — see TS-PVE-020.

## Related

- [`../../../troubleshooting/proxmox/20-vzdump-backup-destabilizes-k8s-cluster.md`](../../../troubleshooting/proxmox/20-vzdump-backup-destabilizes-k8s-cluster.md) — the April 2026 IO investigation that supersedes this test's "no impact" conclusion
- [`../DESIGN.md`](../DESIGN.md) — backup frequency rationale (this test supported the 2/week → 3-4/week change)
