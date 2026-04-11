# TS-K8S-022 | 2026-04-11 | RESOLVED

> **REAL INCIDENT** — This case occurred during an unplanned production failure (worker node crash cascading to pod failures), not planned DR testing. Documented before DR test phase began.

## 1. Context
- System: Kubernetes cluster pod scheduling and recovery
- Environment: Production cluster (prod)
- Related components: k8s-worker2, MariaDB StatefulSet, WordPress Deployment, Vault Agent Injector, CSI-NFS controller

## 2. Issue
- Symptom: When worker2 node went down, multiple cascading failures occurred requiring different recovery approaches for different workload types.
- Error:
```bash
kubectl get pods -A -o wide | grep -E "Unknown|Terminating"
apps            wordpress-85b7f46448-xr7bd    0/2   Terminating   k8s-worker2.lab.local
database        mariadb-0                     0/2   Terminating   k8s-worker2.lab.local
vault           vault-agent-injector-...      0/1   Terminating   k8s-worker2.lab.local
ingress-nginx   ingress-nginx-controller-...  0/1   Terminating   k8s-worker2.lab.local
kube-system     csi-nfs-controller-...        5/5   Terminating   k8s-worker2.lab.local
```

**Impact:** WordPress application down, database unavailable, new pods starting without Vault secrets injection.

## 3. Analysis

### Pods Affected on Worker2

| Namespace | Pod | Type | Recovery Behavior |
|-----------|-----|------|-------------------|
| database | mariadb-0 | StatefulSet | **Stuck** - requires manual delete |
| apps | wordpress-...-xr7bd | Deployment | Auto-reschedules (but stuck Terminating) |
| vault | vault-agent-injector | Deployment | Auto-reschedules |
| ingress-nginx | ingress-nginx-controller | Deployment | Auto-reschedules |
| kube-system | csi-nfs-controller | Deployment | Auto-reschedules |
| monitoring | loki-canary, promtail | DaemonSet | Restarts when node returns |

### Issue 1: StatefulSet Not Auto-Rescheduling

**Observed:**
```bash
kubectl get pods -n database
NAME        READY   STATUS        RESTARTS   AGE
mariadb-0   0/2     Terminating   2          42h
```

**Why:** StatefulSets guarantee stable network identity and persistent storage. Kubernetes does not automatically reschedule StatefulSet pods when a node becomes NotReady because:
1. Pod might still be running (split-brain scenario)
2. PersistentVolume might still be attached
3. Could cause data corruption with two instances

**Evidence - Pod stuck on dead node:**
```bash
kubectl describe pod mariadb-0 -n database
Node:         k8s-worker2.lab.local/10.0.54.11
Status:       Terminating (lasts 18m)
```

### Issue 2: Vault Agent Injector Race Condition

**Timeline:**
1. Worker2 goes down
2. vault-agent-injector pod on worker2 enters Terminating
3. New injector pod scheduled on worker3
4. WordPress deployment creates replacement pod on worker1
5. **Race:** WordPress pod starts BEFORE injector is fully ready
6. Result: WordPress pod has only 1/1 containers (no vault-agent sidecar)

**Evidence:**
```bash
kubectl get pods -n apps
wordpress-85b7f46448-s6l52   1/1   Running   # Missing vault-agent!
wordpress-85b7f46448-5sgdh   2/2   Running   # Normal - has vault-agent
wordpress-85b7f46448-hf785   2/2   Running   # Normal - has vault-agent
```

**Consequence - No Vault secrets:**
```
[Sat Apr 11 09:24:54] PHP Warning: mysqli_real_connect(): (HY000/1045):
Access denied for user 'wordpress'@'10.245.62.16' (using password: YES)
```

The pod without vault-agent had no database credentials injected.

### Issue 3: CSI-NFS Driver Not Found (Transient)

**Observed during mariadb restart:**
```
Warning  FailedMount  MountVolume.MountDevice failed for volume "pvc-ffbc1708-...":
kubernetes.io/csi: attacher.MountDevice failed to create newCsiDriverClient:
driver name nfs.csi.k8s.io not found in the list of registered CSI drivers
```

**Why:** CSI-NFS controller was also rescheduling from worker2. The csi-nfs-node DaemonSet pod on the target node hadn't fully re-registered the driver yet.

**Self-resolved:** After CSI pods stabilized, NFS mounts worked.

## 4. Root Cause
> Worker node failure caused cascading issues:
> 1. StatefulSet pods require manual intervention (by design)
> 2. Vault injector rescheduling created race condition with new pod creation
> 3. CSI driver temporary unavailability during pod rescheduling

## 5. Solution

### Recovery Steps Performed

**Step 1: Force delete StatefulSet pod**
```bash
kubectl delete pod mariadb-0 -n database --grace-period=0 --force
# Warning: Immediate deletion does not wait for confirmation...
# pod "mariadb-0" force deleted
```

**Step 2: Wait for MariaDB to reschedule**
```bash
kubectl get pods -n database -w
# mariadb-0   0/2   PodInitializing   0   5s
# mariadb-0   1/2   Running           0   38s
# mariadb-0   2/2   Running           0   44s
```

**Step 3: Delete defective WordPress pod (missing vault-agent)**
```bash
kubectl delete pod wordpress-85b7f46448-s6l52 -n apps
# Pod recreated with proper 2/2 containers
```

**Step 4: Verify all services restored**
```bash
kubectl get pods -n apps
# All 3 WordPress pods: 2/2 Running

kubectl get pods -n database
# mariadb-0: 2/2 Running
```

## 6. Solution Risk
- Risk level: MEDIUM
- Potential impact: Force deleting StatefulSet pod can cause data issues if pod is actually still running on partitioned node. In this case, safe because VM was confirmed stopped.

## 7. Impact After Fix
- Observed: All services restored
- MariaDB running on worker3 with data intact (NFS PVC)
- WordPress pods all have vault-agent (2/2)
- No data loss

## 8. Notes

### Why StatefulSets Need Manual Intervention

StatefulSets provide guarantees that conflict with automatic rescheduling:
- **Stable network identity:** mariadb-0 must always be mariadb-0
- **Ordered deployment:** Pod N must be running before Pod N+1 starts
- **Persistent storage:** PVC remains bound to specific pod

Kubernetes errs on the side of caution - better to wait for admin than risk split-brain.

### Preventing Vault Injection Race Condition

**Option 1: Move vault-agent-injector to master nodes**
```yaml
# Add nodeSelector or affinity to injector deployment
nodeSelector:
  node-role.kubernetes.io/control-plane: ""
tolerations:
  - key: node-role.kubernetes.io/control-plane
    effect: NoSchedule
```

**Option 2: Increase injector replicas**
```yaml
replicas: 2  # or 3 for HA
```

**Option 3: Add PodDisruptionBudget**
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: vault-agent-injector-pdb
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: vault-agent-injector
```

### Recommendation - IMPLEMENTED

Move vault-agent-injector to masters:
- Masters are more stable (control plane components)
- Injector is cluster-critical infrastructure
- Prevents worker node failures from affecting secret injection

**Fix Applied:**
- `kubernetes/dev/deployments/infrastructure/vault/helm-release.yaml`
- `kubernetes/prod/deployments/infrastructure/vault/helm-release.yaml`

```yaml
injector:
  enabled: true
  priorityClassName: system-cluster-critical
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
  tolerations:
    - key: node-role.kubernetes.io/control-plane
      operator: Exists
      effect: NoSchedule
```

### Why Manual Pod Recovery Instead of Just Starting the VM

**Alternative approach:** Could have simply started VM 1021 manually and waited for node to become Ready. Pods would auto-recover.

**Why the harder path was chosen:**
1. **Learning value:** Understanding how each workload type (StatefulSet, Deployment, DaemonSet) behaves during node failure
2. **Real-world preparation:** In production, you're never sure the node will come back:
   - Hardware failure may be permanent
   - Disk corruption may prevent boot
   - Network partition may persist
   - VM may need rebuild from scratch
3. **Faster recovery:** Force-deleting and rescheduling pods can be faster than waiting for node repair
4. **Validates HA design:** Confirms the cluster can recover workloads without the failed node

**When to use which approach:**

| Scenario | Approach |
|----------|----------|
| VM just crashed, likely recoverable | Start VM, wait for auto-recovery |
| Hardware failure suspected | Force delete pods, reschedule elsewhere |
| Time-critical application | Force delete immediately, investigate later |
| Node will be down for maintenance | Drain node first, then take down |
| Unknown if node recoverable | Assume worst case, reschedule pods |

### Recovery Checklist for Future

When worker node fails:
1. [ ] Check if VM is stopped or just unresponsive
2. [ ] If stopped: start manually (remediation bug - TS-K8S-021)
3. [ ] Check StatefulSet pods - may need force delete
4. [ ] Check pods with sidecars (vault-agent) - may need delete/recreate
5. [ ] Verify CSI drivers registered before expecting mounts
6. [ ] Confirm application connectivity after recovery

### Related Cases
- TS-PVE-014: Worker VM crash (root cause of this cascade)
- TS-K8S-021: Remediation pod API error
- TS-K8S-015: CSI-NFS restart stale mount (similar NFS issues)

## 9. Workaround (if any)
> For StatefulSets on failed nodes: Confirm node/VM is truly down, then force delete the pod. Kubernetes will reschedule to healthy node.

> For pods missing sidecars: Delete the defective pod, let Kubernetes recreate with proper injection.
