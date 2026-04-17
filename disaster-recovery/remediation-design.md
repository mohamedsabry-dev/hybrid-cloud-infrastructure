# Remediation System Design

## Overview

Self-healing system for worker node recovery on on-prem Proxmox infrastructure.

---

## Design Decisions (2026-04-17)

### Decision 1: Scope Separation - Node vs Pod

**Problem:** Original script monitored both node health AND pod health (70% failure threshold).

**Additional context:** The original script was written completely by AI and not fully owned/understood by me. It's better to have a small script that is fully understood first, then add features incrementally, rather than running a complex script without full ownership.

**Analysis:**
| Layer | Who Should Handle | Tools Available |
|-------|-------------------|-----------------|
| Pod issues | Kubernetes | Liveness, Readiness, ReplicaSet, HPA, Descheduler |
| Node issues | Custom remediation | Proxmox API (on-prem specific) |

**Pod problems K8s already solves:**
- Container crash → kubelet restarts
- OOM kill → kubelet restarts
- Liveness fail → kubelet restarts
- Readiness fail → removed from Service endpoints
- Pod dies → ReplicaSet schedules new pod on healthy node

**Node problems K8s CANNOT solve on-prem:**
- Worker VM frozen/crashed
- Worker kernel panic
- Worker not responding to API server

**Decision:** Remove all pod-checking logic. Script monitors NODE Ready status only.

**Rationale:**
- 70% pod failure threshold was too aggressive (bad deploy = VM restore)
- No time-based check meant transient failures triggered restore
- Pod issues don't require VM-level intervention
- Simpler script = easier to understand and maintain

### Decision 2: Single Replica Design

**Current setup:**
```yaml
replicas: 1
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
priorityClassName: self-healing-critical  # 1000000
```

**Why 1 replica is correct:**
- Runs on master node (survives all worker failures)
- High priority class (only system components can preempt)
- 2 replicas without leader election = both try same action = conflict
- Adding leader election adds ~50 lines of complexity

**Decision:** Keep 1 replica. Risk of remediation pod dying is low on master.

### Decision 3: Priority Class Hierarchy

```
system-node-critical      (2000001000) ← etcd, kube-apiserver, calico-node
system-cluster-critical   (2000000000) ← coredns, ingress, flux, csi
self-healing-critical     (1000000)    ← remediation pod
database-critical         (1000000)    ← mariadb
app-standard              (500000)     ← wordpress
```

**Decision:** Current hierarchy is correct. Remediation survives resource pressure from apps.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     MASTER NODES                                │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Remediation Pod (1 replica, self-healing-critical)     │   │
│  │  ├── Monitors: k8s-worker1, k8s-worker2, k8s-worker3    │   │
│  │  ├── Via: Kubernetes API (node Ready status)            │   │
│  │  └── Acts via: Proxmox API (reboot/reset/restore)       │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     WORKER NODES                                │
│  k8s-worker1 (VMID 1020)  ←── Dump: 5020                       │
│  k8s-worker2 (VMID 1021)  ←── Dump: 5021                       │
│  k8s-worker3 (VMID 1022)  ←── Dump: 5022                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PROXMOX (pve-dev)                           │
│  ├── VM management API (port 8006)                             │
│  ├── Backups on NAS (nas-dev-data)                             │
│  └── Restore target: local-lvm                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Remediation Flow

### Health Check (Every 5 minutes)

```python
# Simplified: Node Ready status only
def is_node_healthy(v1, node_name):
    node = v1.read_node(node_name)
    for condition in node.status.conditions:
        if condition.type == "Ready":
            return condition.status == "True"
    return False
```

### Escalating Recovery

| Attempt | Action | Wait After |
|---------|--------|------------|
| 1 | Soft reboot (ACPI) | 4 min |
| 2 | Hard reset | 4 min |
| 3+ | Restore from backup | 4 min |

### Restore Process

```
1. Stop VM
2. Clone to dump VMID (preserve state for investigation)
3. Delete broken VM
4. Restore from latest NAS backup
5. Start restored VM
```

---

## How Script Talks to Kubernetes

```python
from kubernetes import client, config

# Load credentials from ServiceAccount (auto-mounted in pod)
config.load_incluster_config()

# Create API client
v1 = client.CoreV1Api()

# Equivalent to: kubectl get node k8s-worker1
node = v1.read_node("k8s-worker1")

# Check Ready condition
for condition in node.status.conditions:
    if condition.type == "Ready":
        is_ready = (condition.status == "True")
```

**RBAC permissions (remediation-auth-sa.yaml):**
```yaml
rules:
- apiGroups: [""]
  resources: ["nodes", "pods"]
  verbs: ["get", "list", "watch"]   # Read-only
```

---

## Configuration

```python
CHECK_INTERVAL = 300        # 5 minutes between checks
VERIFY_WAIT = 120           # 2 minutes verification before action
REMEDIATION_WAIT = 240      # 4 minutes wait after each action
PROXMOX_NODE = "pve-dev"
NFS_STORAGE = "nas-dev-data"
TARGET_STORAGE = "local-lvm"

NODE_MAP = {
    "k8s-worker1.lab.local": 1020,
    "k8s-worker2.lab.local": 1021,
    "k8s-worker3.lab.local": 1022,
}

DUMP_MAP = {
    "k8s-worker1.lab.local": 5020,
    "k8s-worker2.lab.local": 5021,
    "k8s-worker3.lab.local": 5022,
}
```

**Timeline to action:** 5 min (startup) + 5 min (first check) + 2 min (verify) = **12 min minimum** from pod start to first possible action.

---

## Known Risks & Mitigations

### Risk 1: Clone Overwrite on Second Restore - FIXED

**Problem:** If restore triggers twice, dump VMID gets overwritten with broken state.

**Solution:** Check if dump VMID exists before restore. If exists = restore already attempted = STOP.
```python
def dump_vm_exists(proxmox, dump_vmid):
    """Check if dump VM exists - indicates restore was already attempted."""
    try:
        proxmox.nodes(PROXMOX_NODE).qemu(dump_vmid).status.current.get()
        return True
    except:
        return False

# In restore_vm():
if dump_vm_exists(proxmox, dump_vmid):
    print("SAFETY STOP: Restore already attempted, human intervention required")
    return False
```

**Behavior:** Restore runs maximum 1 time per node. To retry, human must delete dump VM in Proxmox.

### Risk 2: False Trigger During Manual Restart - FIXED

**Problem:** Manual node restart → script sees NotReady → triggers reboot → causes crash.

**Solution:** 2-minute verification before any action.
```python
VERIFY_WAIT = 120  # 2 minutes

# In main loop:
if not healthy:
    print(f"NotReady detected, verifying in {VERIFY_WAIT}s...")
    time.sleep(VERIFY_WAIT)
    healthy_recheck, _ = is_node_healthy(v1, node_name)
    if healthy_recheck:
        print("Recovered during verification, skipping")
        continue
    # Still down → proceed
```

**Timeline:** 5 min (check interval) + 2 min (verify) = 7 min minimum before action.

### Risk 3: Unprotected Restore API Call

**Problem:** Restore POST not wrapped in try/except - crashes monitoring loop if fails.

**Status:** PENDING FIX - Add error handling.

### Risk 4: No Alerting

**Problem:** Remediation happens silently, no notifications.

**Status:** PENDING - Will add Prometheus metrics/alerts later. Consider direct SMTP for critical alerts.

---

## Change Log

| Date | Change | Reason |
|------|--------|--------|
| 2026-04-17 | Remove pod failure threshold (70%) | K8s handles pod issues; threshold too aggressive |
| 2026-04-17 | Remove `are_pods_healthy()` function | Scope limited to node health only |
| 2026-04-17 | Simplify script overall | Original AI-written, need smaller owned version first |
| 2026-04-17 | Document single replica rationale | Confirm design is correct |
| 2026-04-17 | Add 2-min verification before action | Prevent false trigger during manual restarts |
| 2026-04-17 | Add dump VM existence check | Limit restore to max 1 attempt per node |

---

## Related Files

- `kubernetes/dev/deployments/apps/remediation/configmap.yaml` - Main script
- `kubernetes/dev/deployments/apps/remediation/deployment.yaml` - Pod spec
- `kubernetes/dev/deployments/apps/remediation/remediation-auth-sa.yaml` - RBAC
- `kubernetes/dev/deployments/apps/remediation/priorityclass.yaml` - Priority class

---

## Testing

See `disaster-recovery/tmp-partial-worker-loss.md` for DR test procedures.
