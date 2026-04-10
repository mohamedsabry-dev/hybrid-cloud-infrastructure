# TS-K8S-001 | 2026-03-25 | RESOLVED

## 1. Context
- System: Kubernetes / Pod Scheduling / Taint-based Eviction
- Environment: Prod & Dev K8s clusters
- Related components: ER605 Router (Inter-VLAN routing), bare nginx pods, TaintManager
- Discovered during: Routine check after router reboot
- Duration: ~2 hours troubleshooting

**Cluster Details:**
- Kubernetes v1.31.14 (kubeadm)
- CNI: Calico v3.27.0
- Pod CIDR: 10.245.0.0/16
- HA API: 10.0.51.100:16443 (HAProxy + Keepalived)

**Network Topology:**
```
┌─────────────────────────────────────────────────────────────────┐
│                        ER605 Router                             │
│                    (Inter-VLAN Routing)                         │
│                         ▲                                       │
│                         │ REBOOTED (~5-10 min)                  │
│                         ▼                                       │
├─────────────────────────┬───────────────────────────────────────┤
│      VLAN 51            │           VLAN 54                     │
│   K8s Masters           │        K8s Workers                    │
│                         │                                       │
│  ┌─────────────┐        │  ┌─────────────┐                      │
│  │ master1     │        │  │ worker1     │ ← nginx2 (SURVIVED)  │
│  │ 10.0.51.10  │        │  │ 10.0.54.10  │                      │
│  └─────────────┘        │  └─────────────┘                      │
│  ┌─────────────┐        │  ┌─────────────┐                      │
│  │ master2     │        │  │ worker2     │ ← nginx (EVICTED)    │
│  │ 10.0.51.11  │        │  │ 10.0.54.11  │                      │
│  └─────────────┘        │  └─────────────┘                      │
│  ┌─────────────┐        │  ┌─────────────┐                      │
│  │ master3     │        │  │ worker3     │ ← nginx3 (EVICTED)   │
│  │ 10.0.51.12  │        │  │ 10.0.54.12  │                      │
│  └─────────────┘        │  └─────────────┘                      │
└─────────────────────────┴───────────────────────────────────────┘
```

## 2. Issue
- Symptom: Bare pods inconsistently evicted after router outage - some survived, some deleted
- Error: `TaintManagerEviction - Marking for deletion Pod default/nginx`
- Impact: Unpredictable pod survival during network outages; race condition behavior

Router reboot caused ~5-10 minute network outage between K8s masters (VLAN 51) and workers (VLAN 54). This triggered pod eviction due to the default 300-second (5 min) tolerance. Due to race condition timing, some pods were evicted while others survived - inconsistent behavior across identical nodes.

**Initial observation:**
- Yesterday: Created 3 bare nginx pods, one on each worker
- Today: Only nginx2 running; nginx and nginx3 disappeared
- Same pattern in Dev environment (1 survivor, 2 evicted)

**Pod status before outage:**
```bash
NAME     READY   STATUS    NODE
nginx    1/1     Running   k8s-worker2.lab.local
nginx2   1/1     Running   k8s-worker1.lab.local
nginx3   1/1     Running   k8s-worker3.lab.local
```

**Pod status after outage:**
```bash
NAME     READY   STATUS    RESTARTS   NODE
nginx2   1/1     Running   1          k8s-worker1.lab.local
nginx3   1/1     Running   1          k8s-worker3.lab.local
# nginx - GONE (evicted and deleted)
```

## 3. Analysis

### Step 1: Check Node Status

**Command:**
```bash
kubectl get nodes -o wide
```

**Result:** All nodes Ready (recovered after outage)
```
k8s-master1.lab.local   Ready    control-plane   15h   v1.31.14
k8s-master2.lab.local   Ready    control-plane   15h   v1.31.14
k8s-master3.lab.local   Ready    control-plane   15h   v1.31.14
k8s-worker1.lab.local   Ready    <none>          15h   v1.31.14
k8s-worker2.lab.local   Ready    <none>          15h   v1.31.14
k8s-worker3.lab.local   Ready    <none>          15h   v1.31.14
```

---

### Step 2: Check Node Conditions

**Command:**
```bash
kubectl describe node k8s-worker2.lab.local | grep -A 15 Conditions
```

**Result - worker2 (where nginx died):**
```
Events:
  Normal   NodeNotReady             37m (x2 over 63m)  node-controller  Node k8s-worker2.lab.local status is now: NodeNotReady
  Normal   NodeReady                32m                kubelet          Node k8s-worker2.lab.local status is now: NodeReady
```

**Analysis:** Node went NotReady during outage, then recovered.

---

### Step 3: Check NodeNotReady Events (All Nodes)

**Command:**
```bash
kubectl get events -A --field-selector reason=NodeNotReady
```

**Result:**
```
NAMESPACE   LAST SEEN   TYPE      REASON         OBJECT                       MESSAGE
default     40m         Normal    NodeNotReady   node/k8s-worker1.lab.local   Node status is now: NodeNotReady
default     40m         Normal    NodeNotReady   node/k8s-worker2.lab.local   Node status is now: NodeNotReady
default     40m         Normal    NodeNotReady   node/k8s-worker3.lab.local   Node status is now: NodeNotReady
default     40m         Warning   NodeNotReady   pod/nginx                    Node is not ready
default     40m         Warning   NodeNotReady   pod/nginx2                   Node is not ready
default     40m         Warning   NodeNotReady   pod/nginx3                   Node is not ready
```

**Key Finding:** ALL 3 nodes went NotReady at the SAME time. ALL 3 pods received NodeNotReady warning.

---

### Step 4: Check NodeReady Recovery Events

**Command:**
```bash
kubectl get events -A --field-selector reason=NodeReady
```

**Result:**
```
NAMESPACE   LAST SEEN   TYPE     REASON      OBJECT                       MESSAGE
default     35m         Normal   NodeReady   node/k8s-worker1.lab.local   Node status is now: NodeReady
default     36m         Normal   NodeReady   node/k8s-worker2.lab.local   Node status is now: NodeReady
default     36m         Normal   NodeReady   node/k8s-worker3.lab.local   Node status is now: NodeReady
```

**Timeline:**
| Event | Time Ago | Duration NotReady |
|-------|----------|-------------------|
| All nodes NotReady | 40m | - |
| worker2 Ready | 36m | ~4 min |
| worker3 Ready | 36m | ~4 min |
| worker1 Ready | 35m | ~5 min |

**Analysis:** All nodes down ~4-5 minutes - RIGHT AT the 5-minute eviction threshold.

---

### Step 5: Check TaintManagerEviction Events (Critical)

**Command:**
```bash
kubectl get events -A | grep nginx
```

**Result - THE SMOKING GUN:**
```
default   57m   Normal   TaintManagerEviction   pod/nginx    Marking for deletion Pod default/nginx
default   57m   Normal   Killing                pod/nginx    Stopping container nginx
default   57m   Normal   TaintManagerEviction   pod/nginx2   Cancelling deletion of Pod default/nginx2
default   57m   Normal   TaintManagerEviction   pod/nginx3   Cancelling deletion of Pod default/nginx3
```

**Key Finding:**
| Pod | TaintManagerEviction Event | Result |
|-----|----------------------------|--------|
| nginx | `Marking for deletion` → `Killing` | **EVICTED** |
| nginx2 | `Cancelling deletion` | **SURVIVED** |
| nginx3 | `Cancelling deletion` | **SURVIVED** |

---

### Step 6: Check Pod Tolerations

**Command:**
```bash
kubectl get pods nginx2 -o jsonpath='{.spec.tolerations}'
```

**Result:**
```json
[
  {"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},
  {"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}
]
```

**Analysis:** Default tolerance is 300 seconds (5 minutes). Router outage was ~5-10 minutes - right at the edge.

---

### Step 7: Worker Node Investigation (kubelet logs)

**SSH to worker2:**
```bash
ssh root@10.0.54.11
journalctl -u kubelet --since "2 hours ago" | grep -i "nginx\|evict\|kill"
```

**Result:**
```
Mar 25 14:22:36 kubelet[1432]: I0325 14:22:36.319017 eviction_manager.go:189] "Eviction manager: starting control loop"
Mar 25 14:23:07 kubelet[1432]: E0325 14:23:07.658397 "killPodWithSyncResult failed" err="...dial tcp 10.96.0.1:443: i/o timeout" pod="default/nginx"
Mar 25 14:51:39 kubelet[1432]: I0325 14:51:39.923022 "DeleteContainer returned error" containerID="0656b8833e90b21d0fd1521b96ed41d370dae3c3a20094ae5c123b53d62f9b8e"
```

**Analysis:**
- 14:22:36 - Kubelet started
- 14:23:07 - Tried to kill pod but FAILED (network still down - i/o timeout)
- 14:51:39 - Pod finally deleted

---

### Step 8: Containerd Logs (Container Lifecycle)

**Command:**
```bash
journalctl -u containerd --since "2 hours ago" | grep -i nginx
```

**Key Events:**
```
Mar 25 14:23:21 containerd: RunPodSandbox for name:"nginx" uid:"2d3ae868-739b-4e66-9518-acf045658018" attempt:1
Mar 25 14:23:21 containerd: Calico CNI IPAM assigned addresses IPv4=[10.245.207.66/26]
Mar 25 14:23:35 containerd: Pulled image "nginx:latest"
Mar 25 14:23:35 containerd: CreateContainer within sandbox for container name:"nginx"
Mar 25 14:51:39 containerd: Releasing address using handleID ContainerID="fd4cd39522e83d7aebf934d05c3f6d453c754c6e30b31ce9545ee9bf235f730a"
```

**Complete Timeline:**
| Time | Event |
|------|-------|
| 14:22:36 | Kubelet started, eviction manager started |
| 14:23:07 | Kill FAILED - couldn't reach API (i/o timeout) |
| 14:23:21 | Pod RECREATED - network restored, new sandbox |
| 14:23:35 | Container created, nginx pulled |
| 14:51:39 | Pod DELETED - eviction finally processed |

## 4. Root Cause

### Primary Cause: Race Condition at Eviction Threshold

1. **Router rebooted** (~14:51) - 5-10 minute outage
2. **Inter-VLAN routing broken** - Masters (VLAN 51) couldn't reach Workers (VLAN 54)
3. **All nodes marked NotReady** - Same time for all 3 workers
4. **5-minute tolerance timer started** - Default `tolerationSeconds: 300`
5. **Outage duration ~5-10 min** - Right at the edge of threshold
6. **TaintManager queued evictions** - All 3 pods marked for deletion

### Why Different Outcomes?

The TaintManager processes evictions in a queue. When nodes started recovering:

- **nginx (worker2)**: Eviction **completed** before node fully Ready
- **nginx2 (worker1)**: Node Ready **just in time** → deletion **cancelled**
- **nginx3 (worker3)**: Initially evicted, but in Prod eventually cancelled

**It's a millisecond-level race condition** - whichever pod's node reconnected first got saved.

### Timeline Diagram

```
14:51:00  Router reboot started
    │
    │     ┌──────────────────────────────────────────────┐
    │     │  ALL NODES: NotReady taint applied           │
    │     │  ALL PODS: 300s tolerance timer starts       │
    │     └──────────────────────────────────────────────┘
    │
14:56:00  5-minute tolerance EXPIRES
    │     TaintManager starts eviction process
    │
    │     ┌───────────────────────────────────────────────────────┐
    │     │ RACE CONDITION WINDOW                                 │
    │     │                                                       │
    │     │  nginx:  Eviction processed → DELETED                 │
    │     │  nginx2: Node Ready first → Deletion CANCELLED        │
    │     │  nginx3: Node Ready in time → Deletion CANCELLED      │
    │     └───────────────────────────────────────────────────────┘
    │
14:57:00  Router fully up
          All nodes Ready
```

## 5. Solution

### 1. Use Deployments Instead of Bare Pods

```bash
# Instead of:
kubectl run nginx --image=nginx

# Use:
kubectl create deployment nginx --image=nginx --replicas=3
```

Deployments automatically reschedule pods to healthy nodes.

### 2. Increase Tolerance for Workloads

**Note:** The 300s (5 min) default tolerance is hardcoded in Kubernetes and cannot be changed via kube-controller-manager flags in K8s v1.31+.

**Options to increase tolerance:**

**Option A: Specify in Deployment YAML (Recommended)**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      tolerations:
      - key: "node.kubernetes.io/not-ready"
        operator: "Exists"
        effect: "NoExecute"
        tolerationSeconds: 600    # 10 minutes
      - key: "node.kubernetes.io/unreachable"
        operator: "Exists"
        effect: "NoExecute"
        tolerationSeconds: 600    # 10 minutes
      containers:
      - name: nginx
        image: nginx
```

**Option B: Use Policy Engine (Kyverno/OPA Gatekeeper)**
- Install Kyverno and create a policy to inject tolerations into all pods automatically
- More complex but provides cluster-wide enforcement

**Option C: Use Deployments (simplest)**
- Just use Deployments instead of bare pods
- Pods get evicted but are automatically rescheduled to healthy nodes
- No tolerance change needed - the Deployment controller handles recovery

### 3. Change VM Boot Order - All Workers Together

**Problem:** Current staggered boot (orders 11→12→13 with 60s delays) means workers come online at different times, creating race conditions.

**Solution:** All masters start together, then all workers start together.

**Current (Prod) - Staggered:**
| VM | Order | Delay | Start Time |
|----|-------|-------|------------|
| master1 | 8 | 60s | T+0 |
| master2 | 9 | 60s | T+60s |
| master3 | 10 | 60s | T+120s |
| worker1 | 11 | 60s | T+180s |
| worker2 | 12 | 60s | T+240s |
| worker3 | 13 | 60s | T+300s |

**Proposed - Parallel with Control Plane Ready Wait:**
| VM | Order | Delay | Start Time | Reason |
|----|-------|-------|------------|--------|
| master1 | 8 | 0 | T+0 | All masters start together |
| master2 | 8 | 0 | T+0 | All masters start together |
| master3 | 8 | 0 | T+0 | All masters start together |
| worker1 | 9 | 60 | T+60s | Wait for control plane to be ready |
| worker2 | 9 | 0 | T+60s | Start with worker1 (same order) |
| worker3 | 9 | 0 | T+60s | Start with worker1 (same order) |

**Why worker1 has startup_delay=60:**
- Proxmox considers a VM "started" when it begins booting, not when services are ready
- Masters need ~30-60 seconds to fully boot and have kubelet/API server ready
- Without delay, workers would start before the K8s control plane is available
- The 60s delay on worker1 ensures masters are fully ready before any workers start
- worker2 and worker3 have delay=0 since they share the same order (9) and start together

**Terraform changes required:**
- `terraform/prod/proxmox/vms/k8s_masters/variables.tf` - all masters: startup_order=8, startup_delay=0
- `terraform/prod/proxmox/vms/k8s_workers/variables.tf` - worker1: startup_delay=60, worker2/3: startup_delay=0, all: startup_order=9

**After Terraform edit, unlock the gate lock to deploy:**
1. Unlock DEV K8s gate lock in GitHub Actions
2. Unlock PROD K8s gate lock in GitHub Actions
3. Run the K8s VM deployment workflows for both environments

### 4. Network Infrastructure Upgrade (Planned)

**Current Issue:** ER605 router has known bugs:
- VPN tunnel drops requiring restart every ~5 days (random tunnels)
- Port stability issues (see: `troubleshooting/network/48-er605-port4-gigabit-negotiation.md`)

**Planned Migration:** Migrate from TP-Link ER605 to **MikroTik L009UiGS-RM** for:
- Stable port negotiation
- Stable WireGuard VPN implementation
- Better inter-VLAN routing reliability

### 5. Router Health Monitoring (Future)

Will be developed with the new MikroTik router in shaa Allah:
- Uptime monitoring
- VPN tunnel health checks
- Automated alerting on router issues

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Deployments add minimal overhead; tolerance increase delays eviction (acceptable tradeoff for stability)

## 7. Impact After Fix
- Observed: Deployments automatically reschedule evicted pods to healthy nodes
- No manual intervention needed during network outages
- Race condition still occurs but impact eliminated (pods recreated automatically)

## 8. Notes

### Key Findings

1. **All nodes NotReady at same time** - Network outage affected all equally
2. **All nodes Ready at ~same time** - Recovered within 1 minute of each other
3. **TaintManagerEviction race** - Processing order determined pod survival
4. **Bare pods don't auto-recover** - Once evicted, they're gone permanently
5. **Default tolerance is 300s** - 5 minutes before eviction starts

### Lessons Learned

1. **Bare pods are fragile** - They don't survive node failures
2. **5-minute tolerance is tight** - Router reboots often exceed this
3. **Race conditions are unpredictable** - Same setup, different outcomes
4. **Deployments auto-recover** - K8s recreates evicted pods on healthy nodes
5. **Inter-VLAN dependency** - Router is single point of failure for K8s control plane
6. **Containerd logs are valuable** - Show complete container lifecycle

### Evidence Files

**Kubernetes Events:**
```bash
# NodeNotReady events (all nodes same time)
kubectl get events -A --field-selector reason=NodeNotReady

# TaintManagerEviction events (shows race condition outcome)
kubectl get events -A | grep -i "nginx\|evict"

# NodeReady events (recovery timeline)
kubectl get events -A --field-selector reason=NodeReady
```

**Worker Node Logs:**
```bash
# Kubelet logs
journalctl -u kubelet --since "2 hours ago" | grep -i "nginx\|evict\|kill"

# Containerd logs
journalctl -u containerd --since "2 hours ago" | grep -i nginx
```

### Commands Reference

**Check Pod Status:**
```bash
kubectl get pods -o wide
kubectl describe pod <pod-name>
kubectl get events --field-selector involvedObject.name=<pod-name>
```

**Check Node Status:**
```bash
kubectl get nodes -o wide
kubectl describe node <node-name> | grep -A 15 Conditions
kubectl get events -A --field-selector reason=NodeNotReady
kubectl get events -A --field-selector reason=NodeReady
```

**Check Eviction Events:**
```bash
kubectl get events -A | grep -i "evict\|taint\|kill"
```

**Check Pod Tolerations:**
```bash
kubectl get pod <pod-name> -o jsonpath='{.spec.tolerations}'
```

**Worker Node Investigation:**
```bash
journalctl -u kubelet --since "2 hours ago" | grep -i "evict\|kill\|delete"
journalctl -u containerd --since "2 hours ago" | grep -i <pod-name>
crictl ps -a | grep <pod-name>
ls -la /var/log/pods/ | grep <pod-name>
```

### Action Items

- [ ] Convert bare pods to Deployments for resilience (auto-recovery)
- [ ] For critical workloads, add explicit tolerations (600s) in Deployment YAML
- [x] Update Terraform: Change VM boot order so all masters start together, all workers start together
- [ ] Unlock gate locks and deploy boot order changes via GitHub workflow
- [ ] (Future) Migrate from ER605 to MikroTik L009UiGS-RM for stable routing
- [ ] (Future) Implement router health monitoring with new MikroTik
- [ ] (Future) Consider Kyverno for cluster-wide policy enforcement

### Related Issues

- `troubleshooting/network/43-switch-port4-link-flapping-loose-connection.md` - Physical network issues
- `troubleshooting/network/48-er605-port4-gigabit-negotiation.md` - Router port failure

## 9. Workaround (if any)
> Manually recreate evicted bare pods: `kubectl run nginx --image=nginx`
> Not recommended - use Deployments for automatic recovery instead.
