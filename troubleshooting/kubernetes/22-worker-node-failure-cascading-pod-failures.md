# TS-K8S-022 | 2026-04-11 | RESOLVED | INCIDENT
# Unplanned production failure — worker node crash cascading to pod failures.
_____________________________________________________________________

[Info]
Domain: Kubernetes
Sub-techs: Worker node failure, StatefulSet recovery, Vault Agent Injector race condition,
           CSI-NFS transient failure, force delete, PodDisruptionBudget, nodeSelector
Environment: PROD production cluster | k8s-worker2 (VM 1021) failure
Re-opened: No

_____________________________________________________________________

[Issue Description]
When worker2 node went down, multiple cascading failures occurred requiring
different recovery approaches for different workload types.

  kubectl get pods -A -o wide | grep -E "Unknown|Terminating":
  apps          wordpress-85b7f46448-xr7bd   0/2  Terminating  k8s-worker2
  database      mariadb-0                    0/2  Terminating  k8s-worker2
  vault         vault-agent-injector-...     0/1  Terminating  k8s-worker2
  ingress-nginx ingress-nginx-controller-... 0/1  Terminating  k8s-worker2
  kube-system   csi-nfs-controller-...       5/5  Terminating  k8s-worker2

Impact: WordPress down, database unavailable, new pods starting without
Vault secrets injection.

Related tickets:
  TS-PVE-014   — worker VM crash (root cause)
  TS-K8S-021   — remediation pod API error (bug exposed by this incident)
  TS-K8S-015   — CSI-NFS restart stale mount (similar NFS issues)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Pods affected on worker2 and their recovery behaviour:
  database      mariadb-0              StatefulSet  STUCK — requires manual delete
  apps          wordpress              Deployment   auto-reschedules (stuck Terminating)
  vault         vault-agent-injector   Deployment   auto-reschedules
  ingress-nginx ingress-nginx          Deployment   auto-reschedules
  kube-system   csi-nfs-controller     Deployment   auto-reschedules
  monitoring    loki-canary, promtail  DaemonSet    restarts when node returns


Issue 1 — StatefulSet not auto-rescheduling:

  kubectl get pods -n database:
  mariadb-0  0/2  Terminating  2  42h  (stuck 18+ minutes)

  kubectl describe pod mariadb-0 -n database:
  Node:   k8s-worker2.lab.local/10.0.54.11
  Status: Terminating (lasts 18m)

  Why StatefulSets do not auto-reschedule:
    Kubernetes does not automatically reschedule StatefulSet pods when a node
    becomes NotReady because:
    1. Pod might still be running (split-brain risk)
    2. PersistentVolume might still be attached
    3. Two instances could cause data corruption

    StatefulSet guarantees conflict with auto-rescheduling:
    Stable network identity → mariadb-0 must always be mariadb-0
    Ordered deployment → Pod N must run before Pod N+1
    Persistent storage → PVC remains bound to specific pod
    Kubernetes errs on side of caution — better to wait for admin than risk split-brain.


Issue 2 — Vault Agent Injector race condition:

  Timeline:
    1. Worker2 goes down
    2. vault-agent-injector pod on worker2 enters Terminating
    3. New injector pod scheduled on worker3
    4. WordPress deployment creates replacement pod on worker1
    5. Race: WordPress pod starts BEFORE injector is fully ready
    6. Result: WordPress pod has only 1/1 containers (no vault-agent sidecar)

  Evidence:
    kubectl get pods -n apps:
    wordpress-85b7f46448-s6l52  1/1  Running  ← MISSING vault-agent
    wordpress-85b7f46448-5sgdh  2/2  Running  ← normal
    wordpress-85b7f46448-hf785  2/2  Running  ← normal

  Consequence:
    PHP Warning: mysqli_real_connect(): (HY000/1045):
    Access denied for user 'wordpress' (using password: YES)
    Pod without vault-agent had no database credentials injected.


Issue 3 — CSI-NFS driver not found (transient):

  Warning FailedMount: MountVolume.MountDevice failed:
  driver name nfs.csi.k8s.io not found in the list of registered CSI drivers

  Why: CSI-NFS controller was also rescheduling from worker2. The csi-nfs-node
  DaemonSet pod on the target node had not fully re-registered the driver yet.
  Self-resolved after CSI pods stabilized.


# Suspected Root Cause
Worker node failure caused three cascading issues:
  1. StatefulSet pods require manual intervention (by design — split-brain safety)
  2. Vault injector rescheduling created race condition with new pod creation
  3. CSI driver temporarily unavailable during pod rescheduling (transient)


# More Checks Notes:
The Vault race condition is not a Kubernetes bug — it is expected behaviour.
dependsOn in Flux only controls reconciliation order, not runtime pod scheduling.
Kubernetes scheduler reschedules pods immediately regardless of Flux. The correct
fix is to keep the injector always available via HA (replicas: 2 on separate nodes).


# Suspected Solution
Immediate: force delete StatefulSet pod, delete defective WordPress pod.
Permanent: move vault-agent-injector to master nodes with replicas: 2 +
podAntiAffinity to prevent single point of failure.


# Test
Force-deleted mariadb-0, waited for reschedule to worker3, deleted defective
WordPress pod, verified all services restored.

Command:
  kubectl get pods -n apps
  kubectl get pods -n database

Result: PASS — mariadb-0 Running 2/2, all 3 WordPress pods Running 2/2.
No data loss. WordPress database connectivity restored.

_____________________________________________________________________

[Final Root Cause]
Worker2 node failure cascaded into three issues: StatefulSet pods do not
auto-reschedule by design (split-brain safety); Vault injector rescheduling
created a timing gap where WordPress pods were created without the sidecar;
CSI driver re-registration caused transient mount failures during rescheduling.

_____________________________________________________________________

[Final Solution]

Recovery steps performed:

  Step 1 — Force delete StatefulSet pod:
    kubectl delete pod mariadb-0 -n database --grace-period=0 --force
    kubectl get pods -n database -w
    → mariadb-0  2/2  Running on k8s-worker3

  Step 2 — Delete defective WordPress pod (missing vault-agent):
    kubectl delete pod wordpress-85b7f46448-s6l52 -n apps
    → pod recreated with proper 2/2 containers

  Step 3 — Verify all services restored:
    kubectl get pods -n apps     → all 3 WordPress pods: 2/2 Running
    kubectl get pods -n database → mariadb-0: 2/2 Running

Permanent fix — move vault-agent-injector to master nodes (IMPLEMENTED):
  kubernetes/dev/deployments/infrastructure/vault/helm-release.yaml
  kubernetes/prod/deployments/infrastructure/vault/helm-release.yaml

  injector:
    enabled: true
    priorityClassName: system-cluster-critical
    replicas: 2
    nodeSelector:
      node-role.kubernetes.io/control-plane: ""
    tolerations:
      - key: node-role.kubernetes.io/control-plane
        operator: Exists
        effect: NoSchedule
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: vault-agent-injector
            topologyKey: kubernetes.io/hostname

  Result with 2 replicas on separate masters:
    Replica A → master1
    Replica B → master2
    master1 crashes → Replica B still serving webhook immediately
    → WordPress pods always get sidecar injected even during worker node failures

Two different problems, two different fixes:
  Apps deploy before vault ready on cluster start   → dependsOn + healthCheck in Flux
  Apps restart without vault sidecar at runtime     → replicas: 2 + podAntiAffinity on injector

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM
Note: Force deleting StatefulSet pod can cause data issues if pod is actually
still running on a partitioned node. Safe here because VM was confirmed stopped.
Always confirm node/VM is truly down before force-deleting StatefulSet pods.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Why manual pod recovery instead of just restarting the VM:
  1. Learning value — understand how StatefulSet/Deployment/DaemonSet each behave
  2. Real-world preparation — in production the node may not come back:
     hardware failure may be permanent, disk corruption, network partition,
     VM may need rebuild from scratch
  3. Faster recovery — rescheduling is faster than waiting for node repair
  4. Validates HA design — confirms cluster recovers without the failed node

When to use which recovery approach:
  VM just crashed, likely recoverable        → start VM, wait for auto-recovery
  Hardware failure suspected                 → force delete pods, reschedule elsewhere
  Time-critical application                  → force delete immediately, investigate later
  Node down for maintenance                  → drain node first, then take down
  Unknown if node recoverable                → assume worst case, reschedule pods

Recovery checklist for future worker node failures:
  [ ] Check if VM is stopped or just unresponsive
  [ ] If stopped: start manually (see TS-K8S-021 for remediation bug)
  [ ] Check StatefulSet pods — may need force delete
  [ ] Check pods with sidecars (vault-agent) — may need delete/recreate
  [ ] Verify CSI drivers registered before expecting mounts
  [ ] Confirm application connectivity after recovery

StatefulSet vs Deployment recovery summary:
  StatefulSet  requires manual force delete  split-brain safety by design
  Deployment   auto-reschedules              Kubernetes handles automatically
  DaemonSet    restarts when node returns    no action needed