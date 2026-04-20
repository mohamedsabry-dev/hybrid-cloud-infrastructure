# TS-K8S-048 | 2026-04-20 | RESOLVED
_____________________________________________________________________

[Info]
Author: Sabry
Domain: Kubernetes / Storage / NFS
Sub-techs: CSI NFS driver, StorageClass mountOptions, PV immutability,
           NFS version auto-negotiation, NFSv3 vs NFSv4.2, Prometheus TSDB,
           Git history as audit trail
Environment: DEV k8s-dev cluster | k8s-worker2 | Synology NAS 10.0.40.120
Re-opened: No
Triggered by: TS-K8S-047 — post-rollout NFS health check revealed mixed versions

_____________________________________________________________________

[Issue Description]
During the CSI NFS rollout investigation (TS-K8S-047), I ran `nfsstat -m` across
all workers to verify NFS health. Worker2 showed the Prometheus PVC mounted on
NFSv4.2 while every other PVC across all 3 workers was on NFSv3.

```
Worker1 mounts:  vers=3  (all PVCs)
Worker2 mounts:  vers=3  (most PVCs)
                 vers=4.2 ← ANOMALY (Prometheus PVC only)
Worker3 mounts:  vers=3  (all PVCs)
```

The StorageClass `nfs-retain` explicitly defines `nfsvers=3` in its mountOptions.
The Prometheus PVC uses the same StorageClass as everything else.

Scope:
  PVC: prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0
  PV:  pvc-5e8d9355-ec58-4781-bf03-fc630111d7b5
  StorageClass: nfs-retain
  Node: k8s-worker2

_____________________________________________________________________

[Analysis]

# Suspects

```
Suspect A — StorageClass mountOptions were not set when this PVC was provisioned
Suspect B — CSI driver bug that silently dropped mountOptions
Suspect C — Prometheus StatefulSet defines custom mountOptions overriding StorageClass
Suspect D — NAS auto-negotiated higher version (consequence of A or B)
```

# Step 1 — Confirm the anomaly

Command: nfsstat -m | grep -A2 pvc-5e8d9355  (on k8s-worker2)

Output:
```
Flags: rw,relatime,vers=4.2,rsize=524288,wsize=524288,namlen=255,
       soft,fatal_neterrors=none,proto=tcp,timeo=30,retrans=3,
       sec=sys,clientaddr=10.0.40.202,local_lock=none,addr=10.0.40.120
```

Confirmed: vers=4.2, local_lock=none (NFSv4 default — nolock is meaningless in v4).

# Step 2 — Eliminate Suspect C (StatefulSet override)

Command: kubectl get statefulset -n monitoring prometheus-kube-prometheus-stack-prometheus -o yaml | grep -A5 mountOptions

Output: (no output — field not present)

StatefulSet defines no mountOptions. Relies entirely on StorageClass. Suspect C eliminated.

# Step 3 — Inspect PV mountOptions (the smoking gun)

Command: kubectl get pv pvc-5e8d9355-ec58-4781-bf03-fc630111d7b5 -o jsonpath='{.spec.mountOptions}'

Output:
```
["soft","timeo=30","retrans=3"]
```

PV has only 3 options. Current StorageClass has 5:
```
nfsvers=3   ← MISSING from PV
nolock      ← MISSING from PV
soft        ← present
timeo=30    ← present
retrans=3   ← present
```

The PV was frozen with only 3 options at provisioning time. Without nfsvers=3,
kernel auto-negotiated NFSv4.2.

# Step 4 — PV creation timestamp

Command: kubectl get pv pvc-5e8d9355-ec58-4781-bf03-fc630111d7b5 -o jsonpath='{.metadata.creationTimestamp}'

Output:
```
2026-04-05T18:21:43Z
```

# Step 5 — Current StorageClass state

Command: kubectl get storageclass nfs-retain -o yaml

Output:
```
mountOptions:
  - nfsvers=3
  - nolock
  - soft
  - timeo=30
  - retrans=3
creationTimestamp: "2026-04-02T11:04:44Z"
```

Current state has nfsvers=3. But current ≠ what it looked like on Apr 5.

# Step 6 — Git history confirms root cause (Suspect A proven)

Commit 9de364d (~Apr 02):
  Message: "started config without the nfsvers flag"
  StorageClass had: soft, timeo=30, retrans=3 — only 3 options.
  No nfsvers. No nolock.

Commit 77c1b87 (~Apr 08):
  Message: "Add nfs-database StorageClass and troubleshooting cases 13-14"
  Added nfsvers=3 and nolock to nfs-retain.

Timeline:
```
Apr 02 — Commit 9de364d: nfs-retain has 3 options (no version pin)
Apr 05 — Prometheus PVC provisioned at 18:21 UTC
           → CSI driver read StorageClass at this moment
           → StorageClass had: soft, timeo=30, retrans=3
           → PV frozen with exactly these 3 options
           → Kernel auto-negotiated NFSv4.2
Apr 08 — Commit 77c1b87: nfsvers=3 + nolock added
           → All NEW PVCs from this point get NFSv3
           → Prometheus PV already exists — Kubernetes never re-provisions
             or updates existing PVs when StorageClass changes
Apr 20 — Investigation: Prometheus still on NFSv4.2 (expected)
```

Suspect A confirmed. CSI driver didn't drop options — they never existed.

_____________________________________________________________________

[Final Root Cause]
The Prometheus PVC was provisioned on 2026-04-05 when the nfs-retain StorageClass
contained only 3 mountOptions (soft, timeo=30, retrans=3), per commit 9de364d.
The nfsvers=3 and nolock options were not added until 2026-04-08 in commit 77c1b87.

Without nfsvers=3, the Linux NFS client auto-negotiated NFSv4.2 with the Synology
NAS. The PV spec was frozen at provisioning time. Kubernetes does not retroactively
update existing PVs when their StorageClass changes — this is by design.

Not a bug. Expected behavior of Kubernetes storage provisioning combined with
GitOps iterative configuration.

_____________________________________________________________________

[Final Solution]
Chose not to fix — marked as accepted deviation.

NFSv4.2 is functionally suitable for Prometheus TSDB. nfsstat -c shows retrans=0.
No data integrity risk (v4.2 is a superset of v3 with stronger locking).

Documented as known deviation. Only revisit if strict version uniformity becomes
a hard requirement (would need PV delete + recreate with data migration).

Verified: Yes — root cause confirmed via Git commit history evidence chain

_____________________________________________________________________

[Risk Level] LOW

Functional impact: NONE. Prometheus reads/writes correctly on NFSv4.2.
The only concern is cosmetic inconsistency across the cluster's NFS versions.

DR note: NFSv4.2 `hard` mount on worker2 means if the NAS goes down, Prometheus
would hang in uninterruptible D state while soft-mount pods get I/O errors and
recover. This is a behavioral asymmetry worth testing in DR scenarios.

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml
- TS-K8S-047 — CSI podLabels silent accept (where this was discovered)
- Git commit 9de364d — original StorageClass without nfsvers
- Git commit 77c1b87 — nfsvers=3 added to StorageClass

_____________________________________________________________________

[Draft Notes]
Lesson 1: StorageClass changes do not affect existing PVs. PV is a snapshot of
the StorageClass at provisioning time. Future changes only affect new PVCs.

Lesson 2: GitOps makes root cause analysis possible. Without commit history,
couldn't prove whether CSI dropped options or they never existed. The commit
message "started config without the nfsvers flag" directly confirmed the state.

Lesson 3: NFS version auto-negotiation defaults to highest supported. Without
explicit nfsvers=N, Linux NFS client tries highest version the server supports.

Lesson 4: nolock is NFSv3-specific. Passing nolock to NFSv4 mount is silently
ignored — NFSv4 has mandatory integrated locking.

Lesson 5: Pin NFS version explicitly from day one. Retrofitting after PVCs exist
requires reprovision with data migration risk.
