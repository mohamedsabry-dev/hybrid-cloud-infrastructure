# Case 8: Kubernetes Scheduler Limitations and Advanced Scheduling

## Status: IN PROGRESS (VPA + Descheduler Implementation Planned)
## Date: 2026-04-04
## Severity: Medium
## Environment: k8s-dev and k8s-prod clusters
## Related Cases: [Case 7: K8s Dev Cluster Memory Over-Commitment](./7-k8s-dev-memory-overcommit-strategy.md)

---

## 1. Executive Summary

While investigating memory over-commitment in [Case 7](./7-k8s-dev-memory-overcommit-strategy.md), we discovered fundamental limitations in the default Kubernetes scheduler. Pods were not distributing evenly across nodes despite having anti-affinity configured. This investigation revealed:

1. **Scheduler uses only requests, ignores limits and actual usage**
2. **Anti-affinity behaves unexpectedly during rolling updates**
3. **Simultaneous pod scheduling bypasses anti-affinity**
4. **No automatic rebalancing of existing pods**

**Solution Chosen:**
Implement two production-grade tools to address these limitations:
- **Vertical Pod Autoscaler (VPA)**: Auto-tune resource requests based on actual usage
- **Descheduler**: Automatically rebalance pods across nodes

---

## 2. Problem Discovery Timeline

### 2.1 Initial Observation

After applying anti-affinity patches to Flux controllers, we expected even distribution:

**Expected:**
```
Worker1: 1-2 Flux pods
Worker2: 1-2 Flux pods
Worker3: 1-2 Flux pods
```

**Actual Result:**
```
Worker1: 0 Flux pods  ← Why avoided entirely?
Worker2: 2 Flux pods
Worker3: 2 Flux pods
```

### 2.2 Investigation Question

> "Why did worker1 get zero pods when it has the best resources and no taints?"

---

## 3. Investigation Process

### 3.1 Step 1: Check Node Conditions

**Command:**
```bash
kubectl describe node k8s-worker1.lab.local | grep -A 10 "Conditions:"
```

**Output:**
```
Conditions:
  Type                 Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  ----                 ------  -----------------                 ------------------                ------                       -------
  NetworkUnavailable   False   Fri, 03 Apr 2026 09:32:15 +0200   Fri, 03 Apr 2026 09:32:15 +0200   CalicoIsUp                   Calico is running on this node
  MemoryPressure       False   Sat, 04 Apr 2026 02:00:44 +0200   Fri, 27 Mar 2026 20:19:57 +0200   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   Sat, 04 Apr 2026 02:00:44 +0200   Fri, 27 Mar 2026 20:19:57 +0200   KubeletHasNoDiskPressure     kubelet has no disk pressure
  PIDPressure          False   Sat, 04 Apr 2026 02:00:44 +0200   Fri, 27 Mar 2026 20:19:57 +0200   KubeletHasSufficientPID      kubelet has sufficient PID available
  Ready                True    Sat, 04 Apr 2026 02:00:44 +0200   Fri, 03 Apr 2026 09:31:50 +0200   KubeletReady                 kubelet is posting ready status
```

**Analysis:** Worker1 is healthy - no memory pressure, no disk pressure, Ready=True.

### 3.2 Step 2: Check for Taints

**Command:**
```bash
kubectl describe node k8s-worker1.lab.local | grep -A 5 "Taints:"
```

**Output:**
```
Taints:             <none>
Unschedulable:      false
```

**Analysis:** No taints blocking scheduling.

### 3.3 Step 3: Compare Resource Allocation

**Command:**
```bash
kubectl describe nodes | grep -E "(Name:|Allocated)" -A 6
```

**Output:**
```
Name:               k8s-worker1.lab.local
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests    Limits
  --------           --------    ------
  cpu                380m (19%)  0 (0%)
  memory             150Mi (6%)  500Mi (21%)      ← BEST: Lowest usage
--
Name:               k8s-worker2.lab.local
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                680m (34%)   2 (100%)
  memory             348Mi (14%)  2718Mi (115%)   ← Over-committed
--
Name:               k8s-worker3.lab.local
Allocated resources:
  (Total limits may be over 100 percent, i.e., overcommitted.)
  Resource           Requests     Limits
  --------           --------     ------
  cpu                680m (34%)   2 (100%)
  memory             448Mi (18%)  4018Mi (170%)   ← Most over-committed
```

**Analysis:** Worker1 has the BEST resources (6% requests, 21% limits) but got ZERO pods. This is backwards!

### 3.4 Step 4: Verify Anti-Affinity Applied

**Command:**
```bash
kubectl get deployment -n flux-system helm-controller -o yaml | grep -A 20 "affinity"
```

**Output:**
```yaml
      affinity:
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - podAffinityTerm:
              labelSelector:
                matchLabels:
                  app.kubernetes.io/part-of: flux
              topologyKey: kubernetes.io/hostname
            weight: 100
```

**Analysis:** Anti-affinity IS correctly applied to the deployment.

### 3.5 Step 5: Verify Pod Labels Match

**Command:**
```bash
kubectl get pods -n flux-system --show-labels
```

**Output:**
```
NAME                                       READY   STATUS    LABELS
helm-controller-844f6958dc-x89dd           1/1     Running   app.kubernetes.io/component=helm-controller,app.kubernetes.io/instance=flux-system,app.kubernetes.io/part-of=flux,...
kustomize-controller-67486f5bfd-g256v      1/1     Running   app.kubernetes.io/component=kustomize-controller,app.kubernetes.io/instance=flux-system,app.kubernetes.io/part-of=flux,...
notification-controller-7f5d7cb966-pvw56   1/1     Running   app.kubernetes.io/component=notification-controller,app.kubernetes.io/instance=flux-system,app.kubernetes.io/part-of=flux,...
source-controller-6d8d58659f-6rfkc         1/1     Running   app.kubernetes.io/component=source-controller,app.kubernetes.io/instance=flux-system,app.kubernetes.io/part-of=flux,...
```

**Analysis:** All pods have `app.kubernetes.io/part-of=flux` label. Anti-affinity selector matches.

### 3.6 Step 6: Check Scheduling Events

**Command:**
```bash
kubectl get events -A --sort-by='.lastTimestamp' | grep -i schedule | tail -20
```

**Output:**
```
flux-system   8m51s   Normal   Scheduled   pod/notification-controller-7f5d7cb966-pvw56   Successfully assigned flux-system/notification-controller-7f5d7cb966-pvw56 to k8s-worker2.lab.local
flux-system   8m51s   Normal   Scheduled   pod/helm-controller-844f6958dc-x89dd           Successfully assigned flux-system/helm-controller-844f6958dc-x89dd to k8s-worker3.lab.local
flux-system   8m51s   Normal   Scheduled   pod/kustomize-controller-67486f5bfd-g256v      Successfully assigned flux-system/kustomize-controller-67486f5bfd-g256v to k8s-worker2.lab.local
flux-system   8m50s   Normal   Scheduled   pod/source-controller-6d8d58659f-6rfkc         Successfully assigned flux-system/source-controller-6d8d58659f-6rfkc to k8s-worker3.lab.local
```

**Critical Finding:** All 4 pods were scheduled at the SAME SECOND (8m51s, 8m50s). This is the clue!

---

## 4. Root Cause Analysis

### 4.1 The Rolling Update Problem

**Before the anti-affinity patch:**
```
Worker1: [helm-OLD] [kustomize-OLD] [notification-OLD] [source-OLD]
Worker2: (empty)
Worker3: (empty)
```

**When Flux applied the patch (rolling update):**
```
Timeline:
────────────────────────────────────────────────────────────────────────────

1. Flux patches all 4 deployments simultaneously

2. Rolling update begins for ALL deployments at once

3. New helm-controller pod needs scheduling:
   Scheduler: "I see 4 Flux pods on worker1 (OLD pods still running)"
   Scheduler: "Anti-affinity says avoid nodes with Flux pods"
   Scheduler: "Worker1 has 4, Worker2 has 0, Worker3 has 0"
   Decision: → Worker2 or Worker3

4. New kustomize-controller pod needs scheduling:
   Scheduler: "Worker1 has 4 OLD pods, Worker2 has 1 NEW, Worker3 has 1 NEW"
   Decision: → Worker2 or Worker3 (avoid Worker1)

5. Same for notification-controller and source-controller
   All avoid Worker1 because OLD pods are still there

6. Old pods terminate AFTER new pods are running

RESULT: All new pods on Worker2/Worker3, Worker1 empty

────────────────────────────────────────────────────────────────────────────
```

**The anti-affinity worked correctly - against the OLD pods!**

### 4.2 Visualization

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    ROLLING UPDATE TIMELINE                              │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  TIME 0: Before patch                                                   │
│  ════════════════════                                                   │
│  Worker1: [helm-OLD] [kustomize-OLD] [notif-OLD] [source-OLD]           │
│  Worker2: (empty)                                                       │
│  Worker3: (empty)                                                       │
│                                                                         │
│  TIME 1: Patch applied, new pods scheduling                             │
│  ═══════════════════════════════════════════                            │
│  Worker1: [helm-OLD] [kustomize-OLD] [notif-OLD] [source-OLD] ← 4 pods! │
│  Worker2: [helm-NEW scheduling...]                                      │
│  Worker3: [kustomize-NEW scheduling...]                                 │
│                                                                         │
│  Scheduler sees: "Worker1 has 4 flux pods, AVOID IT"                    │
│                                                                         │
│  TIME 2: New pods running, old pods terminating                         │
│  ══════════════════════════════════════════════                         │
│  Worker1: [terminating...] [terminating...] [terminating...] [term...]  │
│  Worker2: [helm-NEW ✓] [notif-NEW ✓]                                    │
│  Worker3: [kustomize-NEW ✓] [source-NEW ✓]                              │
│                                                                         │
│  TIME 3: Final state                                                    │
│  ══════════════════                                                     │
│  Worker1: (empty) ← All old pods gone                                   │
│  Worker2: [helm] [notification]                                         │
│  Worker3: [kustomize] [source]                                          │
│                                                                         │
│  Result: 0-2-2 distribution instead of expected 1-2-1 or 2-1-1          │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 4.3 The Fix: Sequential Restart

**Command:**
```bash
for dep in helm-controller kustomize-controller notification-controller source-controller; do
  echo "Restarting $dep..."
  kubectl rollout restart deployment/$dep -n flux-system
  kubectl rollout status deployment/$dep -n flux-system
  sleep 5
done
```

**Why this works:**
```
Sequential restart timeline:
────────────────────────────────────────────────────────────────────────────

1. Restart helm-controller:
   No other Flux pods exist (old ones terminated)
   → Scheduler places on Worker1 (best resources)

2. Wait for Running... then restart kustomize-controller:
   Worker1 has 1 Flux pod now
   → Scheduler prefers Worker2 (anti-affinity)

3. Wait for Running... then restart notification-controller:
   Worker1 has 1, Worker2 has 1
   → Scheduler prefers Worker3

4. Wait for Running... then restart source-controller:
   Worker1=1, Worker2=1, Worker3=1
   → Any node acceptable, picks best resources (Worker1)

RESULT: 2-1-1 distribution ✓

────────────────────────────────────────────────────────────────────────────
```

**Result After Sequential Restart:**

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-worker1.lab.local
```

```
NAMESPACE       NAME                                       NODE
flux-system     helm-controller-7d7d496d88-smffn           k8s-worker1.lab.local
flux-system     kustomize-controller-6f59f854cf-bhml6      k8s-worker1.lab.local
ingress-nginx   ingress-nginx-controller-ccdf84b85-6hwwl   k8s-worker1.lab.local
```

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-worker2.lab.local
```

```
NAMESPACE       NAME                                       NODE
flux-system     source-controller-6d444bfc77-pp9vg         k8s-worker2.lab.local
ingress-nginx   ingress-nginx-controller-ccdf84b85-kvw6x   k8s-worker2.lab.local
```

```bash
kubectl get pods -A -o wide --field-selector spec.nodeName=k8s-worker3.lab.local
```

```
NAMESPACE       NAME                                       NODE
flux-system     notification-controller-xxx                k8s-worker3.lab.local
ingress-nginx   ingress-nginx-controller-ccdf84b85-n649w   k8s-worker3.lab.local
```

**New Distribution:**

| Node | Flux Pods | Ingress Pods | Total Critical |
|------|-----------|--------------|----------------|
| Worker1 | 2 | 1 | 3 |
| Worker2 | 1 | 1 | 2 |
| Worker3 | 1 | 1 | 2 |

Now if any worker dies, we still have Flux and Ingress running on other nodes.

---

## 5. Deeper Scheduler Limitation Discovered

### 5.1 The Fundamental Problem

After fixing the distribution, we observed the memory allocation:

```
Worker1: 214Mi requests,  1524Mi limits (64%)   ← Most headroom
Worker2: 348Mi requests,  2718Mi limits (115%)  ← Over-committed
Worker3: 384Mi requests,  2994Mi limits (126%)  ← Most over-committed
```

**Question:** Why does the scheduler put more load on over-committed nodes?

### 5.2 Answer: Scheduler Only Uses Requests

```
┌─────────────────────────────────────────────────────────────────────────┐
│              KUBERNETES SCHEDULER RESOURCE VIEW                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  WHAT SCHEDULER SEES:                     WHAT IT IGNORES:              │
│  ════════════════════                     ════════════════              │
│                                                                         │
│  ✅ Requests (guaranteed allocation)      ❌ Limits (max burst)         │
│  ✅ Node allocatable resources            ❌ Actual current usage       │
│  ✅ Taints and tolerations                ❌ Historical patterns        │
│  ✅ Affinity/anti-affinity rules          ❌ Memory pressure trends     │
│  ✅ Node selectors                        ❌ Limit over-commitment %    │
│                                                                         │
│  SCHEDULER'S VIEW OF OUR CLUSTER:                                       │
│  ════════════════════════════════                                       │
│                                                                         │
│  Worker1: 9% requests used  ← "Plenty of room"                          │
│  Worker2: 14% requests used ← "Plenty of room"                          │
│  Worker3: 16% requests used ← "Plenty of room"                          │
│                                                                         │
│  All look equally good! Scheduler doesn't care about:                   │
│  Worker2: 115% limits (over-committed)                                  │
│  Worker3: 126% limits (most over-committed)                             │
│                                                                         │
│  THIS IS BY DESIGN, NOT A BUG                                           │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 5.3 Why Kubernetes Does This

**Reason 1: Performance**
- Checking actual usage requires metrics queries
- Default scheduler optimizes for speed
- Thousands of scheduling decisions per second in large clusters

**Reason 2: Over-commitment is a feature**
- Allows better resource utilization
- Not all pods burst to limits simultaneously
- Same principle as airline overbooking

**Reason 3: Simplicity**
- Requests/limits are declarative and predictable
- Actual usage fluctuates constantly
- Deterministic scheduling is easier to debug

### 5.4 The Tradeoff Dilemma

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    THE SCHEDULING DILEMMA                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  OPTION A: Set requests = limits (no over-commit)                       │
│  ═══════════════════════════════════════════════                        │
│                                                                         │
│  Worker1: 2GB committed (requests), 500MB actual use                    │
│  Worker2: 500MB committed (requests), 400MB actual use                  │
│                                                                         │
│  New pod needs 300MB → Goes to Worker2                                  │
│  But Worker1 has 1.5GB FREE actual memory! Wasted.                      │
│                                                                         │
│  Pros: Safe, no OOM surprises                                           │
│  Cons: Wastes resources, needs more nodes                               │
│                                                                         │
│  ────────────────────────────────────────────────────────────────────── │
│                                                                         │
│  OPTION B: Set requests < limits (over-commit allowed)                  │
│  ════════════════════════════════════════════════════                   │
│                                                                         │
│  Worker1: 500MB committed (requests), 500MB actual                      │
│  Worker2: 500MB committed (requests), but 2GB limits                    │
│                                                                         │
│  Scheduler sees both equal → spreads pods                               │
│  But if Worker2 pods burst → OOM kill                                   │
│                                                                         │
│  Pros: Better utilization, fewer nodes needed                           │
│  Cons: Risk of OOM under load                                           │
│                                                                         │
│  ────────────────────────────────────────────────────────────────────── │
│                                                                         │
│  THERE IS NO PERFECT SOLUTION IN DEFAULT KUBERNETES                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 6. Available Solutions

### 6.1 Overview of Options

| Solution | Effort | What It Solves | Production Use |
|----------|--------|----------------|----------------|
| **Vertical Pod Autoscaler (VPA)** | Medium | Right-sizes requests automatically | ✅ Very common |
| **Descheduler** | Low-Medium | Rebalances pods across nodes | ✅ Very common |
| Trimaran Scheduler Plugins | High | Metrics-based scheduling | ⚠️ Less common |
| Custom Scheduler | Very High | Full control | ❌ Rare |
| Set requests=limits | Low | Prevents over-commit | ⚠️ Wastes resources |

### 6.2 Chosen Solution: VPA + Descheduler

We chose these two because:

1. **Both are official Kubernetes SIG projects** (well-maintained)
2. **Both are widely used in production** (proven solutions)
3. **They complement each other** (VPA fixes requests, Descheduler fixes placement)
4. **Reasonable complexity** (suitable for learning and homelab)

---

## 7. Solution 1: Vertical Pod Autoscaler (VPA)

### 7.1 What VPA Does

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    VPA OPERATION                                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  BEFORE VPA:                                                            │
│  ═══════════                                                            │
│  You guess: requests=500Mi, limits=1Gi                                  │
│  Reality: Pod uses 80-150Mi most of the time                            │
│  Result: Scheduler reserves 500Mi, wastes 350Mi+                        │
│                                                                         │
│  WITH VPA:                                                              │
│  ═════════                                                              │
│                                                                         │
│  Week 1: VPA observes actual usage                                      │
│          ├── Pod typically uses: 80-150Mi                               │
│          ├── Peak usage: 200Mi                                          │
│          └── P95: 180Mi                                                 │
│                                                                         │
│  Week 2: VPA recommends:                                                │
│          ├── requests: 150Mi (covers typical + buffer)                  │
│          └── limits: 300Mi (covers peaks + headroom)                    │
│                                                                         │
│  Week 3+: VPA auto-applies (if configured) or you apply manually        │
│                                                                         │
│  RESULT:                                                                │
│  ════════                                                               │
│  Scheduler now sees ACCURATE resource needs                             │
│  Better placement decisions                                             │
│  Less over-commitment                                                   │
│  More efficient cluster utilization                                     │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 7.2 VPA Modes

| Mode | Behavior | Risk | Use Case |
|------|----------|------|----------|
| **Off** | Only recommends, doesn't apply | None | Learning, initial setup |
| **Initial** | Sets requests on pod creation only | Low | Conservative approach |
| **Auto** | Updates running pods (causes restarts) | Medium | Full automation |

### 7.3 VPA Installation

```bash
# Clone the autoscaler repository
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler

# Install VPA components
./hack/vpa-up.sh

# Verify installation
kubectl get pods -n kube-system | grep vpa
```

**Expected output:**
```
vpa-admission-controller-xxx   1/1     Running
vpa-recommender-xxx            1/1     Running
vpa-updater-xxx                1/1     Running
```

### 7.4 VPA Configuration Example

```yaml
# vpa-flux-controllers.yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: flux-helm-controller-vpa
  namespace: flux-system
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: helm-controller
  updatePolicy:
    updateMode: "Off"  # Start with recommendations only
  resourcePolicy:
    containerPolicies:
    - containerName: manager
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: 1
        memory: 1Gi
```

### 7.5 Reading VPA Recommendations

```bash
kubectl describe vpa flux-helm-controller-vpa -n flux-system
```

**Sample output:**
```yaml
Recommendation:
  Container Recommendations:
    Container Name: manager
    Lower Bound:
      Cpu:     25m
      Memory:  64Mi
    Target:
      Cpu:     50m
      Memory:  128Mi     ← Recommended requests
    Uncapped Target:
      Cpu:     50m
      Memory:  128Mi
    Upper Bound:
      Cpu:     100m
      Memory:  256Mi     ← Recommended limits
```

---

## 8. Solution 2: Descheduler

### 8.1 What Descheduler Does

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    DESCHEDULER OPERATION                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  PROBLEM: Scheduler doesn't rebalance existing pods                     │
│  ═════════════════════════════════════════════════                      │
│                                                                         │
│  Scenario: New worker node added                                        │
│                                                                         │
│  Before:                                                                │
│  Worker1: [pod1] [pod2] [pod3] [pod4] [pod5]                            │
│  Worker2: [pod6] [pod7] [pod8] [pod9] [pod10]                           │
│  Worker3: (new, empty)  ← Scheduler won't move existing pods here       │
│                                                                         │
│  ────────────────────────────────────────────────────────────────────── │
│                                                                         │
│  DESCHEDULER SOLUTION:                                                  │
│  ═════════════════════                                                  │
│                                                                         │
│  Runs periodically (e.g., every 5 minutes):                             │
│                                                                         │
│  1. Analyzes cluster state                                              │
│  2. Identifies imbalances                                               │
│  3. EVICTS pods from overloaded nodes                                   │
│  4. Scheduler reschedules evicted pods to better nodes                  │
│                                                                         │
│  After Descheduler:                                                     │
│  Worker1: [pod1] [pod2] [pod3]                                          │
│  Worker2: [pod6] [pod7] [pod8]                                          │
│  Worker3: [pod4] [pod5] [pod9] [pod10]  ← Now balanced!                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### 8.2 Descheduler Strategies

| Strategy | What It Does | Use Case |
|----------|--------------|----------|
| **RemoveDuplicates** | Evicts duplicate pods from same node | Anti-affinity violations |
| **LowNodeUtilization** | Moves pods from busy to idle nodes | Balance utilization |
| **HighNodeUtilization** | Consolidates pods to fewer nodes | Cost savings |
| **RemovePodsViolatingInterPodAntiAffinity** | Fixes anti-affinity violations | After rolling updates |
| **RemovePodsViolatingNodeAffinity** | Fixes node affinity violations | After node changes |
| **RemovePodsViolatingTopologySpreadConstraint** | Ensures even spread | Zone/region balance |

### 8.3 Descheduler Installation

```bash
# Add Helm repo
helm repo add descheduler https://kubernetes-sigs.github.io/descheduler
helm repo update

# Install with default config
helm install descheduler descheduler/descheduler \
  --namespace kube-system \
  --set schedule="*/5 * * * *"  # Run every 5 minutes
```

### 8.4 Descheduler Configuration Example

```yaml
# descheduler-policy.yaml
apiVersion: "descheduler/v1alpha2"
kind: "DeschedulerPolicy"
profiles:
  - name: default
    pluginConfig:
    - name: "RemoveDuplicates"
    - name: "RemovePodsViolatingInterPodAntiAffinity"
    - name: "LowNodeUtilization"
      args:
        thresholds:
          cpu: 20
          memory: 20
          pods: 20
        targetThresholds:
          cpu: 50
          memory: 50
          pods: 50
    plugins:
      balance:
        enabled:
          - "RemoveDuplicates"
          - "RemovePodsViolatingInterPodAntiAffinity"
          - "LowNodeUtilization"
```

### 8.5 How LowNodeUtilization Works

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    LOW NODE UTILIZATION STRATEGY                        │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  Configuration:                                                         │
│  thresholds:        # Node considered "underutilized" if BELOW these    │
│    cpu: 20%                                                             │
│    memory: 20%                                                          │
│  targetThresholds:  # Node considered "overutilized" if ABOVE these     │
│    cpu: 50%                                                             │
│    memory: 50%                                                          │
│                                                                         │
│  Example:                                                               │
│  ─────────                                                              │
│  Worker1: CPU 60%, Memory 55%  → OVERUTILIZED (above 50%)               │
│  Worker2: CPU 45%, Memory 40%  → NORMAL                                 │
│  Worker3: CPU 10%, Memory 15%  → UNDERUTILIZED (below 20%)              │
│                                                                         │
│  Action:                                                                │
│  Descheduler evicts pods from Worker1 (overutilized)                    │
│  Scheduler places them on Worker3 (underutilized)                       │
│                                                                         │
│  After:                                                                 │
│  Worker1: CPU 40%, Memory 35%  → NORMAL                                 │
│  Worker2: CPU 45%, Memory 40%  → NORMAL                                 │
│  Worker3: CPU 30%, Memory 30%  → NORMAL                                 │
│                                                                         │
│  Result: Balanced cluster!                                              │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 9. How VPA and Descheduler Work Together

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    VPA + DESCHEDULER SYNERGY                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  STEP 1: VPA Learns Actual Usage                                        │
│  ════════════════════════════════                                       │
│  "Flux helm-controller typically uses 80Mi, not 1Gi"                    │
│  → Recommends requests: 100Mi, limits: 256Mi                            │
│                                                                         │
│  STEP 2: VPA Updates Requests                                           │
│  ═══════════════════════════                                            │
│  Deployment updated with accurate requests                              │
│  Scheduler now has truthful data                                        │
│                                                                         │
│  STEP 3: Scheduler Makes Better Decisions                               │
│  ════════════════════════════════════════                               │
│  New pods placed based on realistic resource needs                      │
│  Less over-commitment, better distribution                              │
│                                                                         │
│  STEP 4: Descheduler Fixes Historical Imbalances                        │
│  ═══════════════════════════════════════════════                        │
│  "Worker1 is overloaded, Worker3 is underutilized"                      │
│  → Evicts pods from Worker1                                             │
│  → Scheduler places them on Worker3                                     │
│                                                                         │
│  STEP 5: Continuous Optimization                                        │
│  ════════════════════════════════                                       │
│  VPA keeps learning and adjusting                                       │
│  Descheduler keeps rebalancing                                          │
│  Cluster stays optimized automatically                                  │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐    │
│  │                                                                 │    │
│  │  VPA: "Here's what pods ACTUALLY need"                          │    │
│  │         ↓                                                       │    │
│  │  Scheduler: "I can now place pods accurately"                   │    │
│  │         ↓                                                       │    │
│  │  Descheduler: "I'll fix any imbalance over time"                │    │
│  │                                                                 │    │
│  │  Result: Right-sized pods, evenly distributed, stable cluster   │    │
│  │                                                                 │    │
│  └─────────────────────────────────────────────────────────────────┘    │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Implementation Plan

### 10.1 Phase 1: Descheduler (Simpler, Start Here)

| Step | Action | Timeline |
|------|--------|----------|
| 1 | Install Descheduler via Helm | Day 1 |
| 2 | Configure LowNodeUtilization strategy | Day 1 |
| 3 | Monitor cluster rebalancing | Week 1 |
| 4 | Tune thresholds based on observations | Week 2 |

### 10.2 Phase 2: VPA

| Step | Action | Timeline |
|------|--------|----------|
| 1 | Install VPA components | Week 2 |
| 2 | Create VPA resources in "Off" mode (recommendations only) | Week 2 |
| 3 | Observe recommendations for 1-2 weeks | Week 2-4 |
| 4 | Apply recommendations manually | Week 4 |
| 5 | Consider switching to "Auto" mode | Month 2 |

### 10.3 Files to Create

```
kubernetes/
├── dev/
│   └── deployments/
│       └── infrastructure/
│           ├── descheduler/
│           │   ├── kustomization.yaml
│           │   ├── namespace.yaml
│           │   └── helm-release.yaml
│           └── vpa/
│               ├── kustomization.yaml
│               ├── namespace.yaml
│               └── helm-release.yaml
└── prod/
    └── deployments/
        └── infrastructure/
            ├── descheduler/
            │   └── (same structure)
            └── vpa/
                └── (same structure)
```

---

## 11. Verification Commands

### 11.1 Check Pod Distribution

```bash
# Count pods per node
kubectl get pods -A -o wide --no-headers | awk '{print $8}' | sort | uniq -c

# Detailed view per node
for node in k8s-worker1 k8s-worker2 k8s-worker3; do
  echo "=== $node ==="
  kubectl get pods -A --field-selector spec.nodeName=$node.lab.local --no-headers | wc -l
done
```

### 11.2 Check Resource Allocation

```bash
# Per-node summary
kubectl describe nodes | grep -E "(Name:|Allocated)" -A 6

# Specific namespace
kubectl describe nodes | grep -E "(Name:|memory)"
```

### 11.3 Check VPA Recommendations

```bash
# List all VPAs
kubectl get vpa -A

# Get recommendations
kubectl describe vpa <vpa-name> -n <namespace>
```

### 11.4 Check Descheduler Activity

```bash
# View descheduler logs
kubectl logs -n kube-system -l app=descheduler --tail=100

# Check for eviction events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i evict
```

---

## 12. Lessons Learned

### 12.1 Scheduler Behavior

1. **Scheduler uses REQUESTS, not limits or actual usage**
   - This is by design for performance
   - Over-commitment is allowed and expected

2. **Anti-affinity during rolling updates sees OLD pods**
   - Rolling update creates new pods while old ones still exist
   - Anti-affinity avoids nodes with old pods
   - Sequential restarts needed for proper distribution

3. **Simultaneous scheduling bypasses anti-affinity**
   - When pods schedule at same second, they don't see each other
   - Staggered scheduling or Descheduler needed

4. **Scheduler doesn't rebalance existing pods**
   - New nodes stay empty unless pods are evicted
   - Descheduler fills this gap

### 12.2 Best Practices

1. **Start with recommendations before auto-tuning**
   - VPA "Off" mode first, observe before applying

2. **Use soft anti-affinity for critical pods**
   - Availability > perfect distribution
   - Hard anti-affinity can block scheduling entirely

3. **Right-size requests based on actual usage**
   - Over-provisioned requests waste resources
   - Under-provisioned requests cause bad scheduling decisions

4. **Implement gradual rebalancing**
   - Descheduler with conservative thresholds
   - Avoid excessive pod churn

---

## 13. Open Questions for Future Investigation

1. **How does VPA interact with HPA (Horizontal Pod Autoscaler)?**
   - VPA adjusts per-pod resources
   - HPA adjusts pod count
   - Need to understand interaction

2. **What's the impact of Descheduler on stateful workloads?**
   - StatefulSets with PVCs
   - Database pods
   - Should they be excluded?

3. **How to handle VPA recommendations for system components?**
   - Flux controllers
   - Ingress controllers
   - CoreDNS

---

## 14. References

- [Kubernetes VPA GitHub](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Kubernetes Descheduler GitHub](https://github.com/kubernetes-sigs/descheduler)
- [Kubernetes Scheduler Documentation](https://kubernetes.io/docs/concepts/scheduling-eviction/kube-scheduler/)
- [Case 7: Memory Over-Commitment Strategy](./7-k8s-dev-memory-overcommit-strategy.md)

---

## 15. Resolution Status

| Component | Status | Notes |
|-----------|--------|-------|
| Anti-affinity for Flux | ✅ Complete | Pods now spread across nodes |
| Anti-affinity for Ingress | ✅ Complete | 1 pod per node |
| Sequential restart workaround | ✅ Documented | Manual fix for rolling update issue |
| Root cause analysis | ✅ Complete | Scheduler limitations understood |
| VPA | 🔄 Planned | To be implemented |
| Descheduler | 🔄 Planned | To be implemented |

**Status: IN PROGRESS** - Investigation complete, solutions identified, implementation planned.
