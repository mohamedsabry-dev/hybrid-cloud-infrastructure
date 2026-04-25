# TS-K8S-001 | 2026-03-25 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Pod Scheduling / Taint-based Eviction
Sub-techs: TaintManager, tolerationSeconds, bare pods, NodeNotReady, inter-VLAN routing
Environment: Prod & Dev K8s clusters | v1.31.14 (kubeadm) | Calico v3.27.0
           Pod CIDR: 10.245.0.0/16 | HA API: 10.0.51.100:16443 (HAProxy + Keepalived)
Discovered during: Routine check after ER605 router reboot
Duration: ~2 hours troubleshooting
Re-opened: No

_____________________________________________________________________

[Issue Description]
Router reboot caused a ~5-10 minute network outage between masters (VLAN 51) and
workers (VLAN 54). I had 3 bare nginx test pods, one per worker. After the outage,
one pod was gone — evicted and permanently deleted. The other two survived. Same
pattern in both prod and dev environments (1 evicted, 2 survived). The inconsistency
is the interesting part — identical pods on identical nodes, different outcomes.

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
│  │ master3     │        │  │ worker3     │ ← nginx3 (SURVIVED)  │
│  │ 10.0.51.12  │        │  │ 10.0.54.12  │                      │
│  └─────────────┘        │  └─────────────┘                      │
└─────────────────────────┴───────────────────────────────────────┘
```

Pod status before vs after:

Before:
```
NAME     READY   STATUS    NODE
nginx    1/1     Running   k8s-worker2.lab.local
nginx2   1/1     Running   k8s-worker1.lab.local
nginx3   1/1     Running   k8s-worker3.lab.local
```

After:
```
NAME     READY   STATUS    RESTARTS   NODE
nginx2   1/1     Running   1          k8s-worker1.lab.local
nginx3   1/1     Running   1          k8s-worker3.lab.local
# nginx - GONE (evicted and deleted)
```

_____________________________________________________________________

[Analysis]

# Step 1: Node status after recovery

Command: kubectl get nodes -o wide

Output:
```
k8s-master1.lab.local   Ready    control-plane   15h   v1.31.14
k8s-master2.lab.local   Ready    control-plane   15h   v1.31.14
k8s-master3.lab.local   Ready    control-plane   15h   v1.31.14
k8s-worker1.lab.local   Ready    <none>          15h   v1.31.14
k8s-worker2.lab.local   Ready    <none>          15h   v1.31.14
k8s-worker3.lab.local   Ready    <none>          15h   v1.31.14
```

All nodes recovered. So the eviction happened during the outage window, not after.

# Step 2: Node events — when did they go NotReady?

Command: kubectl describe node k8s-worker2.lab.local | grep -A 15 Conditions

Output (worker2 — where nginx died):
```
Events:
  Normal   NodeNotReady   37m (x2 over 63m)  node-controller  Node k8s-worker2.lab.local status is now: NodeNotReady
  Normal   NodeReady      32m                 kubelet          Node k8s-worker2.lab.local status is now: NodeReady
```

# Step 3: All nodes went NotReady at the same time

Command: kubectl get events -A --field-selector reason=NodeNotReady

Output:
```
NAMESPACE   LAST SEEN   TYPE      REASON         OBJECT                       MESSAGE
default     40m         Normal    NodeNotReady   node/k8s-worker1.lab.local   Node status is now: NodeNotReady
default     40m         Normal    NodeNotReady   node/k8s-worker2.lab.local   Node status is now: NodeNotReady
default     40m         Normal    NodeNotReady   node/k8s-worker3.lab.local   Node status is now: NodeNotReady
default     40m         Warning   NodeNotReady   pod/nginx                    Node is not ready
default     40m         Warning   NodeNotReady   pod/nginx2                   Node is not ready
default     40m         Warning   NodeNotReady   pod/nginx3                   Node is not ready
```

All 3 nodes down at the same time. All 3 pods got the NodeNotReady warning.

# Step 4: Recovery timeline — nodes came back within seconds of each other

Command: kubectl get events -A --field-selector reason=NodeReady

Output:
```
NAMESPACE   LAST SEEN   TYPE     REASON      OBJECT                       MESSAGE
default     35m         Normal   NodeReady   node/k8s-worker1.lab.local   Node status is now: NodeReady
default     36m         Normal   NodeReady   node/k8s-worker2.lab.local   Node status is now: NodeReady
default     36m         Normal   NodeReady   node/k8s-worker3.lab.local   Node status is now: NodeReady
```

All nodes down ~4-5 minutes — right at the edge of the 300-second eviction threshold.

# Step 5: TaintManagerEviction events — the smoking gun

Command: kubectl get events -A | grep nginx

Output:
```
default   57m   Normal   TaintManagerEviction   pod/nginx    Marking for deletion Pod default/nginx
default   57m   Normal   Killing                pod/nginx    Stopping container nginx
default   57m   Normal   TaintManagerEviction   pod/nginx2   Cancelling deletion of Pod default/nginx2
default   57m   Normal   TaintManagerEviction   pod/nginx3   Cancelling deletion of Pod default/nginx3
```

This is it. TaintManager queued all 3 pods for eviction. nginx got processed first
and was killed. nginx2 and nginx3 — their nodes came back Ready before the eviction
completed, so TaintManager cancelled the deletion. Millisecond-level race condition.

# Step 6: Confirm the tolerance threshold

Command: kubectl get pods nginx2 -o jsonpath='{.spec.tolerations}'

Output:
```json
[
  {"effect":"NoExecute","key":"node.kubernetes.io/not-ready","operator":"Exists","tolerationSeconds":300},
  {"effect":"NoExecute","key":"node.kubernetes.io/unreachable","operator":"Exists","tolerationSeconds":300}
]
```

Default tolerance: 300 seconds (5 minutes). Router outage was ~5-10 minutes. Right at the edge.

# Step 7: Kubelet logs on worker2

Command: ssh root@10.0.54.11 && journalctl -u kubelet --since "2 hours ago" | grep -i "nginx\|evict\|kill"

Output:
```
Mar 25 14:22:36 kubelet[1432]: I0325 14:22:36.319017 eviction_manager.go:189] "Eviction manager: starting control loop"
Mar 25 14:23:07 kubelet[1432]: E0325 14:23:07.658397 "killPodWithSyncResult failed" err="...dial tcp 10.96.0.1:443: i/o timeout" pod="default/nginx"
Mar 25 14:51:39 kubelet[1432]: I0325 14:51:39.923022 "DeleteContainer returned error" containerID="0656b8833e90b21d..."
```

Kubelet tried to kill the pod at 14:23:07 but failed — network still down (i/o timeout
to the API server). Pod wasn't actually cleaned up until 14:51:39.

# Step 8: Containerd logs — full container lifecycle

Command: journalctl -u containerd --since "2 hours ago" | grep -i nginx

Output:
```
Mar 25 14:23:21 containerd: RunPodSandbox for name:"nginx" uid:"2d3ae868-739b-4e66-9518-acf045658018" attempt:1
Mar 25 14:23:21 containerd: Calico CNI IPAM assigned addresses IPv4=[10.245.207.66/26]
Mar 25 14:23:35 containerd: Pulled image "nginx:latest"
Mar 25 14:23:35 containerd: CreateContainer within sandbox for container name:"nginx"
Mar 25 14:51:39 containerd: Releasing address using handleID ContainerID="fd4cd39522e83d7a..."
```

Timeline reconstruction:
  14:22:36  Kubelet started, eviction manager loop began
  14:23:07  Kill attempted, FAILED — network down (i/o timeout)
  14:23:21  Pod recreated — network restored, new sandbox created
  14:23:35  Container created, nginx image pulled
  14:51:39  Pod finally deleted — eviction processed late

_____________________________________________________________________

[Final Root Cause]
Race condition at the eviction threshold boundary. The router outage lasted ~5-10
minutes, which is right at the edge of the default 300-second NoExecute tolerance.
TaintManager queued evictions for all 3 pods simultaneously. The outcome depended
on which node's kubelet re-established connectivity to the API server first:

- nginx (worker2): eviction completed before node recovered → permanently deleted
- nginx2 (worker1): node recovered just in time → deletion cancelled
- nginx3 (worker3): node recovered just in time → deletion cancelled

```
14:51:00  Router reboot started
    │
    │     ALL NODES: NotReady taint applied
    │     ALL PODS: 300s tolerance timer starts
    │
14:56:00  5-minute tolerance EXPIRES
    │     TaintManager starts eviction process
    │
    │     RACE CONDITION WINDOW:
    │       nginx:  eviction processed → DELETED
    │       nginx2: node Ready first → deletion CANCELLED
    │       nginx3: node Ready in time → deletion CANCELLED
    │
14:57:00  Router fully up, all nodes Ready
```

The fundamental issue: bare pods don't recover from eviction. Once deleted, they're
gone. A Deployment would have automatically rescheduled the evicted pod to a healthy
node.

_____________________________________________________________________

[Final Solution]
1. Use Deployments instead of bare pods — evicted pods get automatically rescheduled
2. For critical workloads, added explicit tolerations with 600s (10 min) to survive
   longer outages
3. Changed VM boot order in Terraform so all masters start together (order 8), then
   all workers start together (order 9, with 60s startup delay on worker1 to let
   control plane initialize first). This eliminates the staggered boot that was
   creating additional race conditions during restarts.
   Files changed: terraform/{prod,dev}/proxmox/vms/k8s_masters/variables.tf (order 8,
   delay 0) and k8s_workers/variables.tf (order 9, worker1 delay 60s, others 0).
   Deployed by unlocking the K8s gate locks in GitHub Actions and running the VM
   deployment workflows for both environments

Verified: Yes — Deployments auto-recover from eviction, tolerance increase prevents
eviction during typical router reboot windows.

_____________________________________________________________________

[Risk Level] MEDIUM

The race condition itself is low-risk (bare test pods, no production workloads affected).
But it exposed the inter-VLAN routing single point of failure — the ER605 router
reboot took down cross-VLAN communication for all K8s traffic. Later mitigated by
MikroTik migration (see troubleshooting/network/).

_____________________________________________________________________

[References]
- troubleshooting/network/ — ER605 stability issues that led to MikroTik migration
- TS-K8S-022 — worker node failure cascading pod failures (related eviction behavior)
