# TS-K8S-043 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Node Lifecycle / Taint-based Eviction
Sub-techs: NoExecute vs NoSchedule taint, PartialDisruption mode,
           unhealthy-zone-threshold, kube-controller-manager, self-healing
Environment: DEV k8s cluster | 3 masters + 3 workers | kubeadm v1.35.3
Severity: CRITICAL
Discovered during: DR Test 2 — Total Worker Loss
Related: TS-K8S-044 (CoreDNS HA — prerequisite fix for DNS stability),
         disaster-recovery/worker-2of3-down.md
Re-opened: No

_____________________________________________________________________

[Issue Description]
When nodes become unreachable (NotReady), K8s applied `NoSchedule` taint instead
of `NoExecute`. This prevented automatic pod eviction from failed nodes, breaking
the entire self-healing chain.

Expected:
```
Taints:  node.kubernetes.io/unreachable:NoExecute
```

Actual:
```
Taints:  node.kubernetes.io/unreachable:NoSchedule   ← WRONG!
```

_____________________________________________________________________

[Analysis]

# DR Test 2 — inconsistent taint behavior

| Node | NoExecute | NoSchedule |
|------|-----------|------------|
| master3 | NO | Yes |
| worker1 | NO | Yes |
| worker2 | YES | Yes |
| worker3 | NO | Yes |

Only worker2 got `NoExecute`. All others got `NoSchedule` only.

Controller-manager had leader election issues during the test:
```
E0418 19:44:19 "Error retrieving lease lock" err="context deadline exceeded"
E0418 19:45:15 "Error retrieving lease lock" err="connection refused"
```

This may have contributed to improper taint application.

# DR Test 3 — same pattern (after CoreDNS fix)

Shutdown master2 + all 3 workers (4 of 6 nodes = 66%):

| Node | NoExecute | NoSchedule |
|------|-----------|------------|
| master2 | NO | Yes |
| worker1 | YES | Yes |
| worker2 | NO | Yes |
| worker3 | NO | Yes |

Only worker1 got `NoExecute`. Pattern confirmed — PartialDisruption rate-limiting.

# Controller-manager logs — found the root cause

```
I0418 21:42:08 node_lifecycle_controller.go:460] "Starting node controller"
I0418 21:42:08 taint_eviction.go:283] "Starting" controller="taint-eviction-controller"
I0418 21:43:01 node_lifecycle_controller.go:1080] "Controller detected that zone is now in new state"
  zone="" newState="PartialDisruption"
```

When too many nodes fail simultaneously (>55% by default), K8s enters
PartialDisruption mode and rate-limits `NoExecute` taint application to prevent
cascading failures.

Default threshold: `--unhealthy-zone-threshold=0.55` (55%)

| Nodes Down | Percentage | Mode | Behavior |
|------------|------------|------|----------|
| 3/6 | 50% | Normal | All get NoExecute immediately |
| 4/6 | 66% | PartialDisruption | Rate-limited, only 1 gets NoExecute |

5 minutes after entering PartialDisruption, only worker1 pods got evicted:
```
I0418 21:47:59 taint_eviction.go:111] "Deleting pod" pod="monitoring/prometheus-kube-prometheus-stack-prometheus-0"
I0418 21:47:59 taint_eviction.go:111] "Deleting pod" pod="kube-system/csi-nfs-controller-64ff9db975-vhqxb"
```

All from worker1 (the only node with NoExecute). Other nodes' pods NOT evicted.

# Why this breaks self-healing

```
Scenario: master2 (has remediation) + all workers down

master2 → Only NoSchedule → Remediation NOT evicted
worker1 → NoExecute → Pods evicted, but nowhere to go
worker2 → Only NoSchedule → Pods NOT evicted
worker3 → Only NoSchedule → Pods NOT evicted

Result: Remediation stuck on master2, can't reschedule to master1/master3.
        Workers never recover. CLUSTER STUCK.
```

# Why CoreDNS fix alone didn't solve it

TS-K8S-044 (CoreDNS HA) ensures controller-manager keeps leadership. But
PartialDisruption mode is independent of DNS — it triggers based on percentage
of unhealthy nodes. Even with DNS working perfectly, 4/6 nodes down = 66% >
55% threshold = PartialDisruption = rate-limited eviction.

_____________________________________________________________________

[Final Root Cause]
K8s `--unhealthy-zone-threshold` defaults to 0.55 (55%). When 4+ of 6 nodes
fail (66%), controller-manager enters PartialDisruption mode and rate-limits
`NoExecute` taint application. Only ~1 node gets `NoExecute`, the rest get only
`NoSchedule`. This prevents pod eviction from most failed nodes, breaking
self-healing.

_____________________________________________________________________

[Final Solution]

# Fix: Raise unhealthy-zone-threshold to 0.8

Edited `/etc/kubernetes/manifests/kube-controller-manager.yaml` on ALL masters:
```yaml
- --unhealthy-zone-threshold=0.8
```

With 0.8 threshold:
| Nodes Down | Percentage | Mode | Behavior |
|------------|------------|------|----------|
| 4/6 | 66% < 80% | Normal | All get NoExecute immediately |
| 5/6 | 83% > 80% | PartialDisruption | Rate-limited (acceptable) |

Automated via Ansible: `ansible/<env>/playbooks/k8s/update_cluster_config.yml`

# DR Test 4 — verified fix

| Node | NoExecute | Status |
|------|-----------|--------|
| master1 | - | UP |
| master2 | YES | DOWN |
| master3 | - | UP |
| worker1 | YES | DOWN |
| worker2 | YES | DOWN |
| worker3 | YES | DOWN |

ALL down nodes got `NoExecute`. Full self-healing chain worked:

Remediation evicted from master2, rescheduled to master3:
```
remediation  Normal  TaintManagerEviction  pod/remediation-774679955-mlgxs  Marking for deletion
remediation  Normal  SuccessfulCreate      replicaset/remediation-774679955  Created pod: remediation-774679955-2bjsh
remediation  Normal  Scheduled             pod/remediation-774679955-2bjsh  Assigned to k8s-master3.lab.local
```

Remediation detected and recovered workers:
```
k8s-worker1.lab.local: UNHEALTHY! (Node NotReady)
k8s-worker2.lab.local: UNHEALTHY! (Node NotReady)
k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)
--- Remediating 3 unhealthy node(s) ---
[Attempt 1] Remediating k8s-worker1.lab.local (VM 1020) -> Starting VM 1020
[Attempt 1] Remediating k8s-worker2.lab.local (VM 1021) -> Starting VM 1021
[Attempt 1] Remediating k8s-worker3.lab.local (VM 1022) -> Starting VM 1022
```

CoreDNS stayed up on masters:
```
coredns-74b76c898f-mwjq6   Running   k8s-master1.lab.local
coredns-74b76c898f-rr6s9   Running   k8s-master3.lab.local
coredns-74b76c898f-94k7p   Terminating   k8s-master2.lab.local  # evicted correctly
```

Apps recovered after workers came up (brief DNS hiccup during CoreDNS eviction
from master2 is expected — pods retried and succeeded).

# Manual emergency command

If NoExecute taint is still not applied automatically:
```bash
for node in $(kubectl get nodes -o jsonpath='{.items[?(@.status.conditions[?(@.type=="Ready")].status=="Unknown")].metadata.name}'); do
  kubectl taint nodes $node node.kubernetes.io/unreachable:NoExecute --overwrite 2>/dev/null
done
```

Verified: Yes — DR Test 4 confirmed all down nodes get NoExecute, full
self-healing chain works end to end.

_____________________________________________________________________

[Risk Level] CRITICAL

Without `NoExecute`, pods don't get evicted from failed nodes. ReplicaSets don't
create replacements. Self-healing systems can't reschedule. Manual intervention
required for every node failure.

_____________________________________________________________________

[References]
- TS-K8S-044 — CoreDNS HA on masters (prerequisite DNS fix)
- disaster-recovery/worker-2of3-down.md — DR test where issue was discovered
- ansible/<env>/playbooks/k8s/update_cluster_config.yml — Ansible automation
