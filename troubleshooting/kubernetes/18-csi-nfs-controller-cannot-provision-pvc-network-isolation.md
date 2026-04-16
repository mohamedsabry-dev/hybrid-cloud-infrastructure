# TS-K8S-018 | 2026-04-08 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / Storage
Sub-techs: CSI NFS driver, PVC provisioning, node affinity, network segmentation,
           StorageClass, NFSv3, Flux HelmRelease
Environment: DEV k8s-dev cluster | CSI NFS controller placement
Re-opened: No

_____________________________________________________________________

[Issue Description]
New PVCs stuck in Pending. Loki StatefulSet could not start because PVC
provisioning failed with mount timeouts. Existing PVCs (Grafana, Prometheus,
MariaDB) remained Bound — only new provisioning failed.

  kubectl get pvc -A:
  monitoring  storage-loki-0   Pending  nfs-retain  35m
  default     test-pvc         Pending  nfs-retain   2m

  CSI controller logs:
  internally mounting 10.0.40.120:/volume1/k8s-dev at /tmp/pvc-xxx
  mount volume 10.0.40.120:/volume1/k8s-dev to /tmp/pvc-xxx timeout after 110s

Related tickets:
  TS-K8S-006 — Complete NFS storage guide (architecture reference)
  TS-K8S-015 — Stale NFS mount on CSI restart (companion case)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked where CSI controller pods were running.

Command:
  kubectl get pods -n kube-system -o wide | grep csi-nfs-controller

Output:
  csi-nfs-controller-xxx  5/5  Running  10.0.61.11  k8s-master2.lab.local
  csi-nfs-controller-xxx  5/5  Running  10.0.61.10  k8s-master1.lab.local

Controllers on masters (10.0.61.x). NFS server at 10.0.40.120.
No network route between master network and storage network.

Tested network from master to NFS:
  ping -c 2 10.0.40.120   → no reply
  nc -zv 10.0.40.120 2049 → connection timeout

Compared with prod cluster:
  kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
  → prod: controllers on workers — provisioning works

Network architecture:
  Masters   10.0.61.x   no storage NIC   no NFS access
  Workers   10.0.64.x   10.0.40.20x (dedicated NIC)   NFS access YES
  NFS server  10.0.40.120

Why existing PVCs were still Bound:
  CSI controller is only needed for CREATE and DELETE operations.
  It temporarily mounts NFS during provisioning to create subdirectories.
  Once a PVC is provisioned and a pod is running, the controller is not
  involved — the mount is managed by csi-nfs-node on each worker node.
  Existing mounts persist independently of controller location.

Why controllers landed on masters:
  CSI NFS Helm chart includes default tolerations for control-plane.
  Without explicit node affinity, scheduler placed them on masters.
  No explicit affinity was configured.


# Suspected Root Cause
CSI NFS controller pods scheduled on master nodes which have no network route
to the NFS storage server (10.0.40.120). Controller temporarily mounts NFS
during PVC provisioning to create subdirectories — mount timed out after 110s.


# More Checks Notes:
N/A — network test from master confirmed no route to NFS.


# Suspected Solution
Add nodeAffinity to CSI controller to force scheduling on worker nodes only.
Workers have dedicated storage NICs with access to 10.0.40.x network.


# Test
Applied nodeAffinity (DoesNotExist on control-plane label), reconciled HelmRelease.
Verified controller placement, tested new PVC provisioning.

Command:
  kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
  kubectl apply -f test-pvc.yaml && kubectl get pvc test-pvc -w

Result: PASS — controllers on worker nodes (10.0.64.x), test-pvc Bound,
Loki StatefulSet started successfully.

_____________________________________________________________________

[Final Root Cause]
CSI NFS Helm chart includes default tolerations for control-plane — without
explicit node affinity, controllers scheduled on master nodes. Masters have
no network route to NFS storage server (10.0.40.120). Controller mount attempt
during PVC provisioning timed out after 110s. Existing PVCs were unaffected
because mounts are managed by csi-nfs-node on workers, not the controller.

_____________________________________________________________________

[Final Solution]
Added nodeAffinity to CSI controller HelmRelease values to force workers only:

  controller:
    replicas: 2
    priorityClassName: system-cluster-critical
    affinity:
      nodeAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          nodeSelectorTerms:
            - matchExpressions:
                - key: node-role.kubernetes.io/control-plane
                  operator: DoesNotExist   ← nodes WITHOUT this label = workers only

⚠ CRITICAL: DoesNotExist vs Exists:
  DoesNotExist on control-plane label → schedule on nodes WITHOUT label → workers
  Exists on control-plane label       → schedule on nodes WITH label    → masters
  Easy to invert. Always verify placement after applying:
    kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
    → must show worker IPs (10.0.64.x), not master IPs (10.0.61.x)

Additional fixes applied:
  StorageClass mountOptions updated to NFSv3 with nolock:
    mountOptions:
      - nfsvers=3
      - nolock
      - soft
      - timeo=30
      - retrans=3

  ASUSTOR NFS recovery directory created:
    mkdir -p /var/lib/nfs/v4recovery && chmod 755 /var/lib/nfs/v4recovery

Apply and verify:
  flux reconcile helmrelease csi-driver-nfs -n kube-system --with-source
  kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
  kubectl apply -f test-pvc.yaml && kubectl get pvc test-pvc -w

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Brief provisioning unavailability during controller rollout from masters
to workers. NFSv3 downgrade avoids NFSv4 state recovery issues on ASUSTOR NAS.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Architecture decision — controllers on workers vs masters:

  Controllers on workers (chosen):
    Pros: matches network — workers have NFS access, no firewall changes
    Cons: controllers share resources with workloads

  Controllers on masters:
    Pros: dedicated resources, isolated from workload noise
    Cons: requires routing masters to storage network — expanded attack surface

  Decision: workers. No network changes needed.

Known limitation: if all workers are simultaneously down, CSI controller cannot
provision or delete PVCs. Existing pod mounts also down if workers are down.
Acceptable tradeoff for network isolation design.

Key lessons:
  1. CSI controller needs network access to NFS — it mounts NFS during provisioning
  2. Default Helm chart tolerations cause unexpected placement in segmented networks
  3. Existing PVCs working ≠ new provisioning works — different code paths
  4. Verify controller placement after every CSI update — Flux can reschedule if
     affinity is not set
  5. DoesNotExist ≠ Exists — always verify with kubectl get pods -o wide after
  6. Test PVC provisioning after any infrastructure change

Commands reference:
  kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
  ping -c 2 10.0.40.120
  nc -zv 10.0.40.120 2049
  kubectl get storageclass nfs-retain -o yaml | grep -A10 mountOptions
  kubectl describe pvc <name> -n <namespace> | tail -20
  kubectl logs -n kube-system <csi-nfs-controller-pod> -c nfs

Workaround if controllers stuck on masters — manual static PV (temporary):
  Create NAS directory manually.
  Create PersistentVolume with spec.nfs.server and spec.nfs.path.
  Create PVC with spec.volumeName pointing to the manual PV.
  Fix controller placement for proper dynamic provisioning afterward.