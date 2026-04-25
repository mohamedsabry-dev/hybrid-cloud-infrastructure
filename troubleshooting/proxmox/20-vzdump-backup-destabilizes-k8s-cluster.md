# TS-PVE-020 | 2026-04-24 | RESOLVED | INVESTIGATION
_____________________________________________________________________

[Info]
Domain: Proxmox VE / Backup / K8s Stability
Sub-techs: vzdump, ZSTD, NVMe IO, NFS, etcd
Environment: DEV Proxmox server (pve-dev)
Related: TS-PVE-017 (IO storm), TS-PVE-015 (thermal shutdown during backup)
Re-opened: No

_____________________________________________________________________

[Issue Description]

During scheduled vzdump backups (Thu/Sat 21:00), host IO spikes to 50-70% and the entire
k8s cluster becomes unstable. Control plane pods crash-loop across all masters, CSI NFS
controllers fail, Flux controllers go down. The cluster self-heals after the backup
finishes, but during the run the environment is unusable.

Backup config at time of issue:
- Mode: Snapshot
- Compression: ZSTD
- Storage: nas-dev-data (NFS)
- Schedule: thu,sat 21:00
- Selection: All VMs
- Bandwidth limit: none

Hardware: single consumer NVMe carrying 7 VMs, 6 LXCs, and the Proxmox OS.

_____________________________________________________________________

[Investigation]

I went through a bunch of theories on this one. Most of them were wrong, and the process
of ruling them out is what made the final answer clear.


# Theory 1: Wrong backup mode — try Suspend

Proxmox has three backup modes:
- **Snapshot** — VM stays running, copy-on-write dirty block tracking. Most IO-heavy.
- **Suspend** — briefly pauses VM, backs up, resumes. Less IO overhead.
- **Stop** — graceful ACPI shutdown, backup stopped VM, start it again.

Tested Suspend mode on FreeIPA first. Result: still pinging during suspend, fast, no IO
spike. Looked promising.

But then checked the cluster — master2 and master3 were already crashing with IO at 50%,
even though the backup was only on FreeIPA (VM 1001) and hadn't reached any k8s node yet.

```
kube-scheduler-k8s-master3    0/1  Error       108
csi-nfs-controller (worker1)  3/5  Error        78
csi-nfs-controller (worker2)  4/5  Error       159
kube-controller-manager-m1    0/1  Error        49
```

**Verdict:** mode didn't matter — the cluster was crashing from the backup write to NAS,
not from reading the VM.


# Theory 2: NAS write saturation — use bwlimit

The backup writes the archive to `nas-dev-data` over NFS. Maybe that's saturating the NAS
and starving all NFS PVCs (Prometheus, Grafana, Loki, MariaDB storage classes).

vzdump supports bandwidth throttling via the Advanced tab in the backup job GUI.

### Test: bwlimit = 50 MiB/s

```
INFO:   0% (160.0 MiB of 50.0 GiB) in 3s, read: 53.3 MiB/s, write: 0 B/s
INFO:   1% (552.0 MiB of 50.0 GiB) in 11s, read: 49.0 MiB/s, write: 0 B/s
INFO:   2% (1.0 GiB of 50.0 GiB) in 21s, read: 49.6 MiB/s, write: 0 B/s
```

Way too slow — a single 50 GiB VM would take ~17 minutes. With all VMs that's hours.

### Test: bwlimit = 150 MiB/s

```
INFO:   1% (355.9 MiB of 25.0 GiB) in 3s, read: 118.6 MiB/s, write: 95.6 MiB/s
INFO:   4% (1.1 GiB of 25.0 GiB) in 9s, read: 148.8 MiB/s, write: 5.5 MiB/s
...
INFO:  13% (3.3 GiB of 25.0 GiB) in 33s, read: 23.6 MiB/s, write: 23.6 MiB/s
INFO:  14% (3.5 GiB of 25.0 GiB) in 47s, read: 17.1 MiB/s, write: 17.0 MiB/s
```

IO still spiked to 40-50%, cluster still crashed. Speed started at 150 MiB/s then collapsed
to 17-24 MiB/s as IO contention took over.

### Baseline: no bwlimit

```
INFO:   3% (2.0 GiB of 50.0 GiB) in 3s, read: 670.6 MiB/s, write: 0 B/s
INFO:   7% (3.9 GiB of 50.0 GiB) in 7s, read: 500.2 MiB/s, write: 26.0 KiB/s
INFO:  33% (16.6 GiB of 50.0 GiB) in 32s, read: 490.9 MiB/s, write: 45.7 KiB/s
```

Full speed: 500-670 MiB/s reads. This is what floods the system.

**Verdict:** bwlimit helped control the speed but didn't prevent the cluster instability,
even at 150 MiB/s. Not the full answer.


# Theory 3: NVMe contention — backup to local storage instead

Maybe the NAS write is the issue. If I backup to local-lvm instead of NAS, the write stays
on local disk and NAS stays clean.

Tested: backed up master1 to local storage.

**Same result.** IO spiked to 50%+ immediately, cluster crashed within 2 minutes.

**Verdict:** it's not about the NAS being the write target. The NVMe itself can't handle
vzdump reading a VM disk while 13 other guests are running on the same physical drive.


# Theory 4: Stop mode — clean member departure

Maybe the issue with Snapshot/Suspend is that etcd stays running but gets slow from
copy-on-write overhead. A slow etcd member is worse than a dead one — it causes heartbeat
timeouts and leader election storms across all members.

Stop mode does a graceful ACPI shutdown first, so etcd leaves cleanly.

### Test: Stop mode on master1 (FreeIPA first)

FreeIPA scsi0 (local-lvm, 25G) backed up at ~1 GiB/s with zero IO impact. But scsi1
(nas-dev-data, 25G) caused read+write on the same NAS pipe — speed dropped to 16 MiB/s.

### Test: Stop mode on master1 (k8s node)

Shut down master1 with Stop mode. First disk (local, 25G):

```
INFO:   7% (3.8 GiB of 50.0 GiB) in 4s, read: 984.2 MiB/s, write: 0 B/s
INFO:  14% (7.5 GiB of 50.0 GiB) in 7s, read: 1.2 GiB/s, write: 0 B/s
INFO:  46% (23.3 GiB of 50.0 GiB) in 24s, read: 999.3 MiB/s, write: 0 B/s
```

Local disk: blazing fast, no IO issue. But once the NAS write phase started:

```
INFO:  12% (3.1 GiB of 25.0 GiB) in 12s, read: 21.3 MiB/s, write: 19.3 MiB/s
INFO:  14% (3.5 GiB of 25.0 GiB) in 36s, read: 16.5 MiB/s, write: 16.5 MiB/s
```

IO drained everything. Masters and workers crashed again.

**Side note on Stop mode and remediation:** if a worker gets stopped for backup, the k8s
remediation pod would see it as NotReady and try to "fix" it via Proxmox API — potentially
conflicting with the backup. Would need vzdump awareness in the remediation script, same
pattern as the temperature monitor.


# Theory 5: k8s amplification feedback loop

Maybe it's not the NVMe or NAS at all. Maybe k8s amplifies the disruption:
1. vzdump slightly disrupts a node's IO
2. kubelet or etcd hiccups → heartbeat delays
3. k8s reacts with pod rescheduling, etcd writes, controller reconciliation
4. That reaction creates MORE IO across ALL nodes
5. Feedback loop

### Test: manual shutdown of master1, wait for NotReady, then backup

If k8s amplification was the cause, a node going NotReady should trigger the same IO storm
regardless of vzdump.

```
kubectl get nodes
k8s-master1.lab.local   NotReady   control-plane   28d   v1.35.3
k8s-master2.lab.local   Ready      control-plane   28d   v1.35.3
k8s-master3.lab.local   Ready      control-plane   28d   v1.35.3
```

Cluster was completely smooth. No IO spike, no pod crashes, nothing. Master1 went NotReady
and nobody cared.

**BUT** — then I started the backup on the already-stopped master1, and IO immediately
spiked to 50% again, crashing master2/3.

This disproved the k8s cascade theory. A node going down is fine — it's specifically the
vzdump disk read that causes the IO contention.


# Theory 6: data density (sparse vs dense disks)

At this point I was stuck. Every mode, every storage target, every speed — k8s node backups
always crash the cluster. But FreeIPA and LXCs never cause issues.

Then I ran a clean IPA backup with Snapshot mode, no bwlimit, full speed:

```
INFO: backup mode: snapshot
INFO: include disk 'scsi0' 'local-lvm:vm-1001-disk-0' 25G
INFO: include disk 'scsi1' 'nas-dev-data:1001/vm-1001-disk-0.raw' 25G
INFO:   4% (2.4 GiB of 50.0 GiB) in 4s, read: 614.4 MiB/s, write: 48.0 KiB/s
INFO:  22% (11.1 GiB of 50.0 GiB) in 21s, read: 495.9 MiB/s, write: 5.6 KiB/s
INFO:  50% (25.0 GiB of 50.0 GiB) in 48s, read: 609.5 MiB/s, write: 0 B/s
INFO:  99% (49.8 GiB of 50.0 GiB) in 1m 9s, read: 2.8 GiB/s, write: 50.2 MiB/s
INFO: 100% (50.0 GiB of 50.0 GiB) in 1m 10s, read: 205.5 MiB/s, write: 0 B/s
INFO: backup is sparse: 45.84 GiB (91%) total zero data
INFO: transferred 50.00 GiB in 70 seconds (731.4 MiB/s)
INFO: archive file size: 1.50GB
INFO: Finished Backup of VM 1001 (00:01:15)
INFO: Backup job finished successfully
```

**91% zero data. Archive: 1.50 GB from 50 GiB.** Zero IO impact on the cluster.

IPA's disk is mostly empty — ZSTD skips zeros almost instantly, vzdump barely touches
actual disk blocks, and the archive is tiny. The NVMe handles it without breaking a sweat.

K8s nodes are the opposite: container images, overlay filesystem layers, etcd WAL, kubelet
data, pod logs — dense written data on every block. vzdump has to actually read and compress
real data, which means sustained heavy IO on the shared NVMe for minutes.

**This is the real root cause.** Not the backup mode, not the NAS, not the NVMe bandwidth,
not k8s cascading. The k8s VM disks have dense data that produces sustained heavy IO reads.
IPA and LXC disks are mostly zeros that vzdump skips in seconds.

_____________________________________________________________________

[Root Cause]

vzdump backup of k8s VM disks causes sustained IO saturation on the shared consumer NVMe
because the disks contain dense written data (container images, overlay fs, etcd WAL, logs).
ZSTD can't skip these blocks like it does with IPA's 91% zero data. The sustained reads
(60-100+ seconds per VM) compete with all other VMs' IO on the same physical drive, causing
etcd heartbeat failures and control plane pod crashes across the cluster.

The issue is hardware-bound: a single consumer NVMe serving 7 VMs + 6 LXCs + the
hypervisor OS cannot handle vzdump reads alongside normal k8s workload IO.

This happens regardless of:
- Backup mode (Snapshot, Suspend, Stop)
- Storage target (NAS, local)
- Bandwidth limit (50, 150, unlimited MiB/s)

_____________________________________________________________________

[Wrong Theories — Why They Failed]

| Theory | Prediction | Actual Result |
|--------|-----------|---------------|
| Mode matters (Snapshot → Suspend) | Less copy-on-write overhead → less IO | Same IO spike |
| NAS write saturation | bwlimit or local target → stable | Same IO spike at any speed |
| k8s cascade amplification | Node NotReady triggers feedback loop | Manual shutdown = smooth, vzdump = crash |
| Slow etcd member (Snapshot) vs dead (Stop) | Stop mode = clean member departure → stable | Stop mode = same IO spike |
| Data density (IPA = small, k8s = large) | IPA finishes faster → shorter burst | IPA takes same time but 91% zeros |

_____________________________________________________________________

[Solution]

Excluded all k8s nodes (masters + workers) from the vzdump backup job. Only FreeIPA and
LXC containers remain in the scheduled backup.

K8s nodes don't need vzdump — they're fully reproducible:
- **Masters:** Ansible playbook + `kubeadm init/join` + etcd-backup CronJob (snapshots to S3)
- **Workers:** Ansible playbook + `kubeadm join` + Flux GitOps resyncs all workloads

The IO storm watchdog (TS-PVE-017) is safe — it triggers on CPU, not IO, so the backup
IO won't cause false positives.

The temperature monitor (TS-PVE-015) is also safe — it skips shutdown when vzdump or
qmrestore is running.

_____________________________________________________________________

[Validation — 2026-04-25]

Ran the backup job with k8s nodes excluded. Full run, zero cluster impact:

```
VM 1001 (freeipa/qemu):          1m17s   1.50GB   91% sparse   ← zero IO impact
VM 2001 (ansible/lxc):           19s     427MB
VM 2002 (local-runner/lxc):      36s     1.17GB
VM 2003 (ex-nginx/lxc):          16s     290MB
VM 2004 (vault1/lxc):            18s     459MB
VM 2005 (vault2/lxc):            ~18s    ~459MB
VM 9001 (rocky-golden/qemu):     24s     1.38GB   86% sparse
VM 9010 (rocky-lxc-golden/lxc):  ~10s    small
```

Proxmox host IO never exceeded 2%. K8s cluster completely untouched — all pods stable, no
restarts, no errors. Confirms the fix.

Note: prod server (pve-prod) doesn't have this issue — better hardware, IO during backup
window stays under 8%. This is a dev-only problem due to the consumer NVMe.

_____________________________________________________________________

[Config Changes]

Proxmox backup job on pve-dev:
- Removed: all k8s VMs (1010-1012 masters, 1020-1022 workers)
- Kept: FreeIPA (1001), all LXC containers, golden templates
- Mode: Snapshot (fine for IPA/LXC — no IO impact)
- Compression: ZSTD
- Schedule: thu,sat 21:00 (unchanged)
- bwlimit: 150 MiB/s (kept as safety margin, not strictly needed for remaining VMs)
- K8s nodes: manual backup only, during quiet hours when needed

_____________________________________________________________________

[Lessons]

1. Not all VMs are equal for backup — data density determines IO impact, not disk size
2. On shared consumer hardware, the right answer is often "don't backup what you can rebuild"
3. IaC (Ansible + Flux + etcd snapshots) makes k8s nodes cattle, not pets — vzdump is redundant
4. Wrong theories (5 of them) weren't wasted time — each one narrowed the problem space
   and the elimination process is what made the root cause obvious
