# TS-K8S-015 | 2026-04-06 | RESOLVED | INCIDENT
_____________________________________________________________________

[Info]
Domain: Kubernetes / Storage
Sub-techs: CSI NFS driver, MariaDB, InnoDB, NFS stale handle, soft/hard mount,
           StatefulSet, DaemonSet rollout, Flux GitOps, StorageClass
Environment: DEV k8s-dev cluster | bare-metal kubeadm | 3 masters, 3 workers |
             Calico CNI | NFS CSI storage | Synology 10.0.40.120 | Vault sidecar
Re-opened: No

_____________________________________________________________________

[Issue Description]
MariaDB entered CrashLoopBackOff with InnoDB I/O errors after Flux reconciled
CSI NFS driver configuration changes (priorityClassName + replicas=2), which
caused all csi-nfs-node DaemonSet pods to restart.

  MariaDB container logs:
  InnoDB: Operating system error number 5 in a file operation.
  InnoDB: Error number 5 means 'Input/output error'
  InnoDB: File (unknown): 'close' returned OS error 205. Cannot continue operation
  mysqld got signal 6  ← abort()

Timeline:
  ~19:30  Flux applied CSI NFS driver changes
  ~19:30  All csi-nfs-node DaemonSet pods restarted on all nodes
  ~19:35  MariaDB on worker1 started failing with I/O errors
  ~19:40  MariaDB entered CrashLoopBackOff
  ~19:50  Diagnosed as stale NFS mount
  ~19:55  Cordoned worker1, moved MariaDB to worker2 — WORKING
  ~20:05  Rebooted worker1 to clear stale handles
  ~20:10  Moved MariaDB back to worker1 — WORKING

Related tickets:
  TS-K8S-003 — NFS hard mount pod hangs (introduced soft mount that caused this crash)
  TS-K8S-006 — Complete NFS storage guide
  TS-K8S-007 — InnoDB O_DIRECT NFS incompatibility (same DB + NFS fragility)
  TS-K8S-018 — CSI controller network placement (companion case)
  TS-K8S-026 — Released PV cleanup (cordon/move in this case created Released PVs)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Step 1 — Check PVC status:
  kubectl get pvc -n database
  → mariadb-data-mariadb-0  Bound  50Gi  nfs-retain
  PVC bound and healthy. Not a provisioning issue.

Step 2 — Check CSI NFS pods:
  kubectl get pods -n kube-system | grep csi-nfs
  → All csi-nfs-node pods showing ~8 minutes age, 0 restarts
  All freshly rolled out by the Flux change.

Step 3 — Check MariaDB pod location:
  kubectl get pods -n database -o wide
  → mariadb-0  CrashLoopBackOff  k8s-worker1.lab.local
  MariaDB on worker1 — the same node where csi-nfs-node just restarted.

Step 4 — Verify data intact on NAS:
  ibdata1, ib_logfile0, ibtmp1 all present and recently modified.
  wordpress/ directory present.
  Data is intact. Issue is mount connectivity, not data corruption.

Step 5 — Tried kubelet restart (failed to help):
  systemctl restart kubelet  → still failing
  Kubelet does not manage CSI mounts directly. The csi-nfs-node DaemonSet pod
  manages NFS mounts. Restarting kubelet has no effect on stale CSI mount state.

Chain of events:
  Flux applies CSI NFS driver changes (priorityClassName + replicas)
    → Kubernetes rolls all csi-nfs-node DaemonSet pods on all nodes
    → csi-nfs-node on worker1 restarts — existing NFS mount becomes stale
    → MariaDB tries to access InnoDB files through stale mount
    → soft mount (from TS-K8S-003 fix) returns I/O error after timeout
    → InnoDB receives error 5 (EIO) and error 205 (NFS stale handle)
    → InnoDB cannot continue → calls abort() → MariaDB crashes → CrashLoopBackOff

The soft mount contribution:
  The soft mount option introduced in TS-K8S-003 was correct for nginx (stateless,
  replicated). For MariaDB it is wrong.

  Mount    Behaviour on stale NFS           Result for MariaDB
  soft     returns I/O error after timeout  InnoDB crash → CrashLoopBackOff
  hard     waits indefinitely for NFS       MariaDB hangs but resumes on recovery
  hard+intr waits but can be interrupted    hang + manual recovery via SIGKILL

  The same mount option that saved nginx was what crashed MariaDB.
  Rule: soft mount = stateless apps. hard mount = databases.

Why only worker1 was affected:
  worker1  had MariaDB active mount + CSI restarted → stale mount → crash
  worker2  no active mount + CSI restarted → no issue
  worker3  no active mount + CSI restarted → no issue


# Suspected Root Cause
CSI NFS DaemonSet rollout caused csi-nfs-node pod on worker1 to restart,
making the existing NFS mount for MariaDB PVC stale. The soft mount option
(inherited from TS-K8S-003 fix) returned I/O errors instead of waiting,
causing InnoDB to crash rather than hang.


# More Checks Notes:
N/A — chain of events confirmed from CSI pod ages and MariaDB logs.


# Suspected Solution
Immediate: cordon worker1, force-delete MariaDB pod (StatefulSet reschedules to worker2).
Node fix: restart CSI node pod or reboot worker1 to clear stale mount state.
Permanent: create nfs-database StorageClass with hard mount for database workloads.


# Test
Cordoned worker1, force-deleted mariadb-0, watched it reschedule to worker2.

Command:
  kubectl cordon k8s-worker1.lab.local
  kubectl delete pod mariadb-0 -n database --grace-period=0 --force
  kubectl get pods -n database -o wide -w

Result: PASS — MariaDB Running 2/2 on worker2. Data intact, no corruption.
Rebooted worker1, uncordoned, moved MariaDB back — also working.

_____________________________________________________________________

[Final Root Cause]
CSI NFS DaemonSet rollout restarted csi-nfs-node on worker1, making MariaDB's
active NFS mount stale. The soft mount option (from TS-K8S-003) caused the
stale mount to return I/O errors instead of waiting — InnoDB received EIO
(error 5) and NFS stale handle (error 205), could not continue, called abort().
MariaDB entered CrashLoopBackOff. No data corruption — data was intact on NAS
throughout.

_____________________________________________________________________

[Final Solution]

Immediate recovery — move pod to different node:
  kubectl cordon k8s-worker1.lab.local
  kubectl delete pod mariadb-0 -n database --grace-period=0 --force
  kubectl get pods -n database -o wide -w   # watch reschedule to worker2

Fix the affected node:

  Option A — restart CSI node pod (faster, ~15 seconds):
    kubectl get pods -n kube-system -o wide | grep csi-nfs-node | grep k8s-worker1
    kubectl delete pod <csi-nfs-node-pod> -n kube-system
    # Wait ~10s, then reschedule app pod for fresh mount
    kubectl delete pod mariadb-0 -n database

  Option B — reboot node (thorough, ~2-3 minutes):
    ssh k8s-worker1 'reboot'
    # Wait for node Ready
    kubectl uncordon k8s-worker1.lab.local

Recovery method comparison:
  Move pod to different node   ~30s   fast     immediate recovery needed
  Restart CSI node pod         ~15s   fastest  fix specific node, minimal impact
  Node reboot                  ~2-3m  slow     multiple issues or thorough reset

Permanent fix — nfs-database StorageClass with hard mount:
  apiVersion: storage.k8s.io/v1
  kind: StorageClass
  metadata:
    name: nfs-database
  provisioner: nfs.csi.k8s.io
  parameters:
    server: "10.0.40.120"
    share: "/volume1/k8s-dev"
  reclaimPolicy: Retain
  volumeBindingMode: Immediate
  mountOptions:
    - nfsvers=3
    - nolock
    - hard        ← waits for NFS instead of erroring
    - timeo=600   ← 60s timeout per retry
    - retrans=5   ← 5 retries before giving up
    - intr        ← allows SIGKILL interrupt if stuck indefinitely

  With hard + intr:
    Brief NFS disruption → MariaDB waits → resumes when NFS recovers
    Prolonged outage → MariaDB hangs → can be force-killed if needed
    No I/O errors → no InnoDB crash → no data corruption risk

⚠ PENDING — migrate MariaDB PVC to nfs-database:
  Current MariaDB PVC still uses nfs-retain (soft mount).
  Until migration, same crash can occur if csi-nfs-node restarts again.

  Migration steps:
    1. Backup MariaDB data
    2. Delete MariaDB StatefulSet and PVC
    3. Update StatefulSet volumeClaimTemplate to storageClassName: nfs-database
    4. Redeploy — CSI creates new PVC with hard mount
    5. Restore data

Before CSI driver updates — prevention checklist:
  1. Identify nodes with stateful database workloads
  2. Drain those nodes first or accept pod reschedule
  3. Have recovery procedure ready before applying

Verified: Yes (workaround and immediate fix verified; migration pending)

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Moving pod to different node and restarting CSI pod are LOW risk.
Node reboot causes temporary loss of all workloads on that node.
New StorageClass does not affect existing PVCs — LOW risk for future deployments.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Mount options by workload — final decision:
  Nginx, WordPress, static     nfs-retain     soft          crash+restart > hang
  Prometheus, Grafana, Loki    nfs-retain     soft          can rescrape, should not hang
  MariaDB, PostgreSQL          nfs-database   hard + intr   data integrity > availability

Notes:
  1. CSI DaemonSet restarts break active mounts — any update to CSI node pods
     can affect pods with active NFS mounts on that node
  2. Soft mount crashes databases — TS-K8S-003 fix was correct for nginx, wrong for MariaDB
  3. Kubelet restart does NOT fix CSI mount issues — CSI driver manages mounts
  4. Restarting CSI node pod clears stale mounts — faster than full reboot
  5. Moving pod to different node is fastest recovery — works immediately
  6. Running status does not mean healthy — pod accepts connections, I/O can be stuck

Commands reference:
  kubectl get pods -n kube-system -o wide | grep csi-nfs
  kubectl cordon <node-name>
  kubectl uncordon <node-name>
  kubectl delete pod <pod> -n <ns> --grace-period=0 --force
  kubectl get pods -n kube-system -o wide | grep csi-nfs-node | grep <worker>
  kubectl delete pod <csi-nfs-node-pod> -n kube-system
  ssh <worker-node> 'mount | grep nfs'