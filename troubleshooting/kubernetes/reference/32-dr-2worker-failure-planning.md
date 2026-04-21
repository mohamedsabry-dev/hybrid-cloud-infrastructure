# TS-K8S-032 | 2026-04-15 | IN PROGRESS

> **DR PLANNING CASE** — Gaps identified during 2-worker failure DR test planning.
> Not a reactive incident — proactive architectural review before DR test execution.
> Validation section to be completed after DR test.

---

## 1. Context

- **System:** Kubernetes Scheduling, Priority Classes, Anti-Affinity, Self-Healing Architecture
- **Environment:** DEV + PROD clusters
- **Related Components:** Priority Classes, PodAntiAffinity, Remediation, Vault Injector, Ingress-NGINX, MariaDB, WordPress, Monitoring stack
- **Discovered During:** DR test planning session — 2-worker failure scenario
- **Related Cases:**
  - TS-K8S-019 — Flux prune mass deletion (dependency ordering importance)
  - TS-K8S-022 — Worker node failure cascading pod failures
  - TS-K8S-015 — Stale NFS mount on CSI restart

---

## 2. DR Objectives

Before listing gaps, it is important to define what success looks like during a disaster.

### Two Non-Negotiable Targets

**Target 1 — Keep the application running (degraded but alive):**
```
Even with 2 of 3 workers down:
  → WordPress must serve traffic (1 replica minimum)
  → MariaDB must be accessible (1 replica — StatefulSet)
  → Ingress-nginx must route external traffic (1 replica minimum)
  → Vault-injector must serve secret injection (1 replica minimum)
```

**Target 2 — Keep the self-healing path alive:**
```
  → Remediation pod must start and authenticate to Vault
  → Remediation must be able to call Proxmox API
  → Remediation must detect missing workers and restore them
    Options: restart VM, recreate from backup, provision new node
```

### Acceptable Downtime Targets

```
Phase 1 — Pod rescheduling (automatic, no human intervention):
  Time: ~5 minutes
  Trigger: node NotReady timeout (kube-controller-manager default)
  Result: critical pods reschedule on surviving worker
  Application impact: partial degradation during rescheduling

Phase 2 — Self-healing via remediation (automatic):
  Time: 5–15 minutes after remediation starts
  Actions:
    → remediation detects worker nodes missing
    → calls Proxmox API with Vault-injected credentials
    → restarts stopped VMs OR recreates from backup OR provisions new nodes
  Result: workers restored → full capacity returns → all pods reschedule

Total acceptable business impact: ~10–20 minutes
  → 5 min pod eviction + rescheduling
  → 5–15 min remediation restore worker nodes
  → brief reconnect time for MariaDB hard mount recovery
```

---

## 3. What Existed Before DR Planning (Already Correct)

These were already in place and correctly designed:

| Component | Config | Reason |
|---|---|---|
| MariaDB | `database-critical` (1,000,000) | Must schedule before apps |
| WordPress | `app-standard` (500,000) | Lower than database |
| Ingress-nginx | `system-cluster-critical` (2,000,000,000) | Built-in class, highest custom |
| Vault-injector | `system-cluster-critical` (2,000,000,000) | Critical dependency for all pods |
| Remediation | `self-healing-critical` (1,000,000) | Must survive to restore cluster |
| Vault-injector | Hard anti-affinity across masters, 2 replicas | Survives single master failure |
| WordPress | `wait-for-mariadb` init container | Runtime dependency ordering |
| MariaDB | `nfs-database` StorageClass (hard mount) | Data integrity on NFS |

### Vault-Injector Survival Guarantee

Vault-injector runs on masters with hard anti-affinity:
```
injector-1 → master1
injector-2 → master3

Scenario: 2 workers down + 1 master down
  → 1 injector replica still running on remaining master ✅
  → remediation can still authenticate to Vault ✅
  → self-healing path intact ✅
```

This is the foundation that makes the entire self-healing design possible.
Vault-injector on masters means worker failures cannot kill the secret injection path.

---

## 4. Gaps Identified During DR Planning

### Gap 1 — Ingress-nginx soft anti-affinity (preferred)

**Current config:**
```yaml
affinity:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:  # ← SOFT
      - weight: 100
```

**Problem:**
```
2 workers down → all 3 ingress-nginx replicas try to reschedule on worker3
  → 3 × (100m CPU + 256Mi memory) consumed by ingress alone
  → plus 3 × WordPress replicas competing
  → MariaDB and remediation may not get scheduled
  → self-healing path blocked
  → application fully down
```

**Risk:** High — core failure scenario where self-healing cannot start.

---

### Gap 2 — Remediation same priority as MariaDB

**Current:**
```
self-healing-critical: 1,000,000
database-critical:     1,000,000
```

**Problem:**
```
Both compete equally for resources on worker3
Scheduler picks arbitrarily between them
If MariaDB schedules first and fills worker3 → remediation stays Pending
Remediation is what restores the cluster
No remediation → no worker restoration → extended outage
```

**Risk:** High — remediation is more important than MariaDB during a disaster.
MariaDB is useless if the cluster never heals. Remediation must come first.

---

### Gap 3 — Monitoring pods have no resource requests

**Current:**
Monitoring HelmRelease deployed with default values — no explicit resource requests.

**Problem:**
```
Preemption calculation requires resource requests
Without requests → scheduler cannot determine how much space monitoring uses
→ preemption may not fire correctly
→ monitoring pods hold resources that critical pods need
→ higher priority pods stay Pending despite preemption policy
```

**Risk:** Medium — preemption correctness depends on defined requests.

---

### Gap 4 — Monitoring priority class not explicitly set

**Current:**
Monitoring pods use default priority (0) — not intentional, just never set.

**Problem:**
Not a functional issue but an architectural clarity issue.
Default 0 means monitoring is lowest priority — correct intention but undocumented.
In a resource-constrained disaster, explicit is better than accidental.

**Risk:** Low — but should be documented as a deliberate decision.

---

### Gap 5 — No wait-for-vault-injector in remediation

**Current:**
Remediation starts and immediately tries to authenticate to Vault.
No check whether vault-injector webhook is ready.

**Problem:**
```
2 workers down → vault-injector rescheduling on worker3 (takes ~30-60s)
remediation also rescheduling → starts before injector ready
→ vault-agent-init tries to authenticate → injector not ready
→ mutation webhook unavailable → pod starts without vault sidecar
→ /vault/secrets/proxmox-creds not injected
→ remediation crashes with FileNotFoundError
→ self-healing path dead
```

This is the exact same failure pattern as TS-K8S-019 Phase 2 (remediation in wrong folder).

**Risk:** High — breaks the self-healing path at the most critical moment.

---

## 5. Changes Applied

### Change 1 — Ingress-nginx: required anti-affinity + 2 replicas

**File:** `kubernetes/dev/deployments/infrastructure/ingress/helm-release.yaml`

```yaml
controller:
  replicaCount: 2   # reduced from 3
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:  # ← HARD
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: ingress-nginx
          topologyKey: kubernetes.io/hostname
```

**Result:**
```
Normal operation:
  ingress-1 → worker1
  ingress-2 → worker2
  worker3 → FREE for critical recovery path

2 workers down:
  ingress-1 dies, ingress-2 dies
  ingress-1 reschedules on worker3 ✅ (no other ingress there)
  ingress-2 tries worker3 → anti-affinity blocks → stays Pending
  worker3 has only 1 ingress → resources available for remediation + MariaDB
```

**Why 2 replicas not 3:**
With required anti-affinity, 3 replicas on 3 workers is the only valid placement.
During 2-worker outage only 1 can reschedule anyway.
2 replicas is honest about the actual HA capability.

---

### Change 2 — Raise self-healing-critical above database-critical

**File:** `kubernetes/dev/deployments/infrastructure/priority-classes.yaml`

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: self-healing-critical
value: 1500000   # raised from 1,000,000
globalDefault: false
description: "Critical self-healing infrastructure. Must schedule before databases to enable cluster restoration."
```

**Priority hierarchy after change:**
```
system-node-critical      2,000,001,000  ← kube-proxy, CSI node (built-in)
system-cluster-critical   2,000,000,000  ← ingress-nginx, vault-injector (built-in)
self-healing-critical     1,500,000      ← remediation ← RAISED
database-critical         1,000,000      ← MariaDB
app-standard              500,000        ← WordPress
monitoring-standard       100,000        ← monitoring stack (new explicit class)
```

**Reasoning:**
Remediation restores the workers that host MariaDB.
A running remediation with no MariaDB is recoverable.
A running MariaDB with no remediation means extended manual outage.
Self-healing must come before data availability.

---

### Change 3 — Add resource requests to monitoring stack

**File:** `kubernetes/dev/deployments/apps/monitoring/helm-release.yaml`

```yaml
prometheus:
  prometheusSpec:
    resources:
      requests:
        memory: "512Mi"
        cpu: "200m"
      limits:
        memory: "2Gi"
        cpu: "1000m"

grafana:
  resources:
    requests:
      memory: "128Mi"
      cpu: "100m"
    limits:
      memory: "512Mi"
      cpu: "500m"

loki:
  resources:
    requests:
      memory: "256Mi"
      cpu: "100m"
    limits:
      memory: "1Gi"
      cpu: "500m"

alertmanager:
  alertmanagerSpec:
    resources:
      requests:
        memory: "64Mi"
        cpu: "50m"
      limits:
        memory: "256Mi"
        cpu: "200m"
```

**Result:** Scheduler can now correctly calculate preemption.
When MariaDB needs space, monitoring pods are evicted cleanly based on known resource usage.

---

### Change 4 — Add explicit monitoring priority class

**File:** `kubernetes/dev/deployments/infrastructure/priority-classes.yaml`

```yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: monitoring-standard
value: 100000
globalDefault: false
description: "Monitoring workloads. Intentionally lowest custom priority — last to schedule, first to be preempted in resource-constrained scenarios."
```

Applied to: Prometheus, Grafana, Loki, Alertmanager HelmRelease values.

**This is a deliberate architectural decision:**
Monitoring being down during a disaster is acceptable.
Monitoring pods should never prevent critical workloads from scheduling.
Explicit priority documents this intention clearly.

---

### Change 5 — Add wait-for-vault-injector to remediation

**File:** `kubernetes/dev/deployments/apps/remediation/deployment.yaml`

```yaml
initContainers:
  - name: wait-for-vault-injector
    image: busybox:1.36
    command:
      - sh
      - -c
      - |
        until wget -qO- http://vault-agent-injector.vault.svc.cluster.local:8080/healthz 2>/dev/null | grep -q "ok"; do
          echo "Waiting for vault-agent-injector..."
          sleep 3
        done
        echo "Vault injector ready!"
    resources:
      requests:
        memory: "16Mi"
        cpu: "10m"
      limits:
        memory: "32Mi"
        cpu: "50m"
```

**Dependency chain now explicit:**
```
vault-agent-injector ready
  └─► wait-for-vault-injector init exits 0
        └─► vault-agent-init runs → authenticates to Vault
              └─► /vault/secrets/proxmox-creds injected
                    └─► remediation container starts with credentials
                          └─► remediation can call Proxmox API ✅
```

---

## 6. Complete Priority + Scheduling Architecture

### Final Priority Hierarchy

```
system-node-critical      2,000,001,000
  └─► kube-proxy, CSI-node DaemonSet (built-in)

system-cluster-critical   2,000,000,000
  └─► vault-agent-injector (2 replicas, masters, hard anti-affinity)
  └─► ingress-nginx (2 replicas, workers, hard anti-affinity)
  └─► Flux controllers (kube-system managed)
  └─► CSI-nfs-controller (workers only)

self-healing-critical     1,500,000
  └─► remediation (depends on vault-injector via init container)

database-critical         1,000,000
  └─► MariaDB StatefulSet

app-standard              500,000
  └─► WordPress Deployment

monitoring-standard       100,000
  └─► Prometheus, Grafana, Loki, Alertmanager
```

### Anti-Affinity Summary

| Component | Type | Topology | Replicas | Reason |
|---|---|---|---|---|
| vault-injector | Required | hostname (masters) | 2 | Survives master failure |
| ingress-nginx | Required | hostname (workers) | 2 | Frees worker3 for recovery |
| WordPress | Preferred | hostname | 3 | Best effort spread |
| MariaDB | N/A (StatefulSet) | N/A | 1 | Single instance |
| Remediation | Preferred | hostname | 1 | Single instance sufficient |
| Grafana | Required | hostname | 3 | HA for monitoring (RWX PVC) |

---

## 7. 2-Worker Failure Scenario — Expected Behavior

### Timeline

```
T+0:00  — worker1 + worker2 go down simultaneously
T+0:00  — all pods on worker1 and worker2 enter Terminating/Unknown state
T+0:00  — worker3 still running with its existing pods

T+5:00  — kube-controller-manager pod-eviction timeout expires
           pods marked for rescheduling on available nodes

T+5:01  — scheduler processes pending pods in priority order:

  system-cluster-critical (vault-injector, ingress-nginx, Flux):
    → already on masters/worker3 or rescheduling there
    → vault-injector: 1 replica on remaining master ✅
    → ingress-nginx: 1 replica on worker3 (other stays Pending) ✅
    → Flux: reschedules on worker3 ✅

  self-healing-critical (remediation):
    → wait-for-vault-injector init container starts
    → waits for injector ready (~30-60s)
    → vault-agent-init authenticates
    → /vault/secrets/proxmox-creds injected
    → remediation starts ✅

  database-critical (MariaDB):
    → hard mount NFS — waits for connection
    → schedules on worker3 ✅
    → NFS reconnects → MariaDB resumes

  app-standard (WordPress):
    → 1 replica schedules on worker3 (if space)
    → other replicas Pending until workers restored

  monitoring-standard:
    → stays Pending — last priority
    → preempted if needed for critical pods

T+5:00 to T+20:00 — remediation active:
  → detects worker1 and worker2 not in cluster
  → calls Proxmox API
  → restarts VMs or recreates from backup
  → workers come back online
  → all pending pods reschedule
  → full capacity restored

T+20:00 — cluster fully recovered (estimated)
```

### Application Impact Summary

| Phase | Duration | WordPress | MariaDB | Self-healing |
|---|---|---|---|---|
| Node down to eviction | 0–5 min | Degraded (1/3 pods) | Down | Starting |
| Rescheduling + DB recovery | 5–8 min | 1 replica serving | Reconnecting | Running |
| Remediation restoring nodes | 8–20 min | 1 replica serving | Running | Active |
| Full recovery | 20 min | 3 replicas | Running | Standby |

**Minimum viable state (target):** 8 minutes from failure to WordPress + MariaDB both running.

---

## 8. Dependency Chain — Critical Path

```
Masters running (at least 1)
  └─► vault-injector alive (system-cluster-critical on masters)
        └─► remediation init passes (wait-for-vault-injector)
              └─► remediation gets Proxmox creds from Vault
                    └─► remediation calls Proxmox API
                          └─► workers restored
                                └─► MariaDB reschedules (hard mount recovers)
                                      └─► WordPress reschedules
                                            └─► full cluster restored

Parallel path:
  worker3 running
    └─► 1 ingress-nginx replica (system-cluster-critical)
          └─► external traffic still accepted
                └─► routed to 1 WordPress replica on worker3
                      └─► site degraded but alive during recovery
```

**Single point of failure:** All 3 masters down simultaneously.
This would kill vault-injector and remediation — full manual recovery required.
Acceptable risk — 3 master failures simultaneously is extremely unlikely.

---

## 9. Validation — DR Test Results

**Test date:** TBD (scheduled 2026-04-15 night)
**Test method:** Cordon + drain worker1 and worker2 simultaneously

### Expected vs Actual

| Check | Expected | Actual | Result |
|---|---|---|---|
| vault-injector survives | 1 replica on master | TBD | TBD |
| ingress-nginx on worker3 | 1 replica (other Pending) | TBD | TBD |
| remediation schedules before MariaDB | Yes | TBD | TBD |
| remediation authenticates to Vault | Yes | TBD | TBD |
| MariaDB reschedules on worker3 | Yes | TBD | TBD |
| WordPress serves traffic (degraded) | Yes (1 replica) | TBD | TBD |
| monitoring stays Pending | Yes | TBD | TBD |
| preemption events fired | Yes | TBD | TBD |
| time to minimum viable state | ~8 minutes | TBD | TBD |
| workers restored by remediation | Yes | TBD | TBD |

### Commands to Run During Test

```bash
# Watch scheduling decisions
kubectl get pods -A -w

# Watch preemption events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i preempt

# Watch node resources
kubectl describe node k8s-worker3.lab.local | grep -A 15 "Allocated resources"

# Check which pods Pending
kubectl get pods -A | grep Pending

# Verify remediation authenticated
kubectl logs -n remediation -l app=remediation -c remediation | grep -i proxmox

# Check ingress serving
curl -I https://wordpress-dev.lab.local

# Time to recovery
date && kubectl cordon k8s-worker1 k8s-worker2
# record time → monitor until WordPress accessible
```

---

## 10. Lessons Learned

| Lesson | Detail |
|---|---|
| Priority class serves two purposes | Scheduling order AND preemption — both matter |
| Preemption requires resource requests | Without requests scheduler cannot calculate what to evict |
| Soft anti-affinity insufficient for DR | Preferred rules ignored under resource pressure — use required for critical components |
| Self-healing priority > database priority | Remediation must start before MariaDB — it is what restores MariaDB's node |
| Init containers apply to any dependency | Not just databases — vault-injector dependency needs explicit wait logic |
| Monitoring should be explicitly lowest | Default 0 is correct behavior but should be a documented decision not an accident |
| 2 replicas with required anti-affinity > 3 with preferred | Honest HA — documents actual capability during disaster |
| Vault-injector on masters is the foundation | Worker failures cannot break the secret injection path — this is non-negotiable |
