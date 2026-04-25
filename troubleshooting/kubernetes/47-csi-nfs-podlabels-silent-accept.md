# TS-K8S-047 | 2026-04-20 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Helm / FluxCD
Sub-techs: HelmRelease values, Helm chart values schema, podLabels vs customLabels,
           Deployment matchLabels, label selector dependency chain, rolling restart
Environment: DEV k8s-dev cluster | csi-driver-nfs 4.13.1 | Flux GitOps
Re-opened: No

_____________________________________________________________________

[Issue Description]
I was adding pod labels across all infrastructure HelmReleases as a labeling
signature for monitoring. Used `controller.podLabels` for csi-driver-nfs — same
pattern I used for ingress-nginx and metrics-server.

Helm accepted the value silently. No error. No warning. Flux showed it as a drift.
But the label never appeared on the pods. The pods didn't restart either.

That's how I noticed — nginx and metrics-server pods both rolled after adding
podLabels, but CSI NFS pods didn't move.

_____________________________________________________________________

[Analysis]

# How I Caught It

After pushing the pod label changes, nginx and metrics-server both restarted.
CSI NFS didn't. That was the signal.

Command: kubectl get pods -n kube-system -l app=nfs-controller

Output:
```
No resources found in kube-system namespace.
```

The label didn't land. Pods still had only the chart's hardcoded labels.

# Checking What Helm Stored vs What Pods Have

Command: helm get values csi-driver-nfs -n kube-system

Output:
```
USER-SUPPLIED VALUES:
controller:
  podLabels:
    app: nfs-controller
  ...
```

Helm stored the value — it just never made it into the pod template.

Command: kubectl get pods -n kube-system -l app.kubernetes.io/name=csi-driver-nfs -o yaml | grep -A5 labels

Output:
```
labels:
  app: csi-nfs-controller
  app.kubernetes.io/instance: csi-driver-nfs
  app.kubernetes.io/managed-by: Helm
  app.kubernetes.io/name: csi-driver-nfs
  app.kubernetes.io/version: 4.13.1
```

No `nfs-controller` label anywhere. The chart doesn't template `controller.podLabels`.

# Finding the Correct Value Name

Command: helm show values csi-driver-nfs --repo https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts | grep -i -B2 -A2 label

Output:
```
customLabels: {}
image:
    baseRepo: registry.k8s.io
```

The chart uses `customLabels` at the top level, not `controller.podLabels`.

# The Near-Miss — customLabels With app Key

First instinct was to use `customLabels: { app: nfs-controller }`. Ran a diff:

Command: flux diff kustomization infrastructure --path kubernetes/dev/deployments/infrastructure

Output:
```
spec.values
+ one map entry added:
  customLabels:
    app: nfs-controller

spec.values.controller
- one map entry removed:
  podLabels:
    app: nfs-controller
```

Looked clean. But then I checked — the pods already HAVE an `app` label from
the chart: `app: csi-nfs-controller`. And the Deployment selector depends on it:

Command: kubectl get deployment csi-nfs-controller -n kube-system -o jsonpath='{.spec.selector.matchLabels}'

Output:
```
{"app":"csi-nfs-controller"}
```

`customLabels` would overwrite `app: csi-nfs-controller` → `app: nfs-controller`.
The Deployment's matchLabels would stop matching its own pods. That's a break.

This is the dependency chain that would have broken:
```
customLabels: { app: nfs-controller }
  → overwrites pod label app: csi-nfs-controller
    → Deployment matchLabels { app: csi-nfs-controller } no longer matches
      → Deployment loses track of pods
        → new pods created, old pods orphaned
          → potential NFS mount disruption across cluster
```

# Decision: Stop, Use Safe Label

Instead of going down the path of editing matchLabels, Services, anti-affinity
selectors — which touches too many things and risks breaking storage —
I chose a different label key entirely: `stack: nfs`.

This is a non-conflicting key that:
- Doesn't collide with any existing chart labels
- Doesn't interfere with any selector
- Still serves the purpose of verifying that customLabels actually works
- Keeps the change minimal and safe

_____________________________________________________________________

[Final Root Cause]
Two issues combined:

1. **Silent value acceptance** — Helm stores any values you pass, even if the
   chart template never uses them. `controller.podLabels` was stored but never
   rendered. No error, no warning. You only catch this by checking whether the
   label actually appears on the pods.

2. **Different charts, different value schemas** — ingress-nginx and metrics-server
   both support `controller.podLabels` / `podLabels`. csi-driver-nfs uses
   `customLabels` at the top level. No standard across charts.

_____________________________________________________________________

[Final Solution]
1. Removed `controller.podLabels` (silently ignored by chart)
2. Used `customLabels: { stack: nfs }` — safe non-conflicting key
3. Did NOT use `customLabels: { app: nfs-controller }` — would have broken
   Deployment matchLabels selector

```yaml
values:
  customLabels:
    stack: nfs
```

Verified: Yes

_____________________________________________________________________

[Post-Push Observation — DaemonSet Full Restart]

After pushing `customLabels: { stack: nfs }`, Flux reconciled and the rollout
triggered. Expected only the csi-nfs-controller Deployment to restart. Instead,
the ENTIRE CSI NFS stack restarted — both controller pods AND all csi-nfs-node
DaemonSet pods across all 3 workers.

Command: kubectl get pods -n kube-system | grep csi

Output (during rollout):
```
csi-nfs-controller-56646d6c4-w56gq   5/5  Running            0  3s
csi-nfs-controller-56646d6c4-x88tf   5/5  Running            0  3s
csi-nfs-node-4bv68                    3/3  Running            0  4s
csi-nfs-node-czdrh                    3/3  Running            27 (68m ago)  3d21h
csi-nfs-node-hkshn                    0/3  ContainerCreating  0  1s
```

Output (settled):
```
csi-nfs-controller-56646d6c4-w56gq   5/5  Running  0  14s
csi-nfs-controller-56646d6c4-x88tf   5/5  Running  0  14s
csi-nfs-node-4bv68                    3/3  Running  0  15s
csi-nfs-node-8ggcl                    3/3  Running  0  10s
csi-nfs-node-hkshn                    3/3  Running  0  12s
```

This makes sense — `customLabels` is a top-level chart value, not scoped to
controller or node. Helm re-renders all templates, both Deployment and DaemonSet
get new pod specs, both roll.

# Impact Assessment — Why No NFS Errors?

This was the key question. The CSI NFS node pods restarted on every worker —
that's the component responsible for mounting/unmounting PVCs. During the restart,
the CSI plugin deregistered from kubelet for ~2 seconds per worker.

## Timeline from kubelet logs (worker1):

```
21:10:42  Old csi-nfs-node sandbox shm mounts deactivated
21:10:46  CSI NFS plugin DEREGISTERED from kubelet
21:10:47  containerd creates new pod sandbox (RunPodSandbox)
21:10:47  Flood of "ContainerStatus: not found" for old container IDs (normal cleanup)
21:10:47  New "nfs" container created inside new sandbox
21:10:47  Pod startup completed in ~2 seconds
21:10:48  NFS CSI plugin re-registered with kubelet
```

## Two rollout waves observed:

Wave 1 (~21:10): All 3 workers restarted csi-nfs-node within seconds
Wave 2 (~21:26): Second restart wave — Flux was waiting for controller to report
Ready before proceeding. Controller on worker2 showed podStartSLOduration=960s
(16 minutes from creation to confirmed Running).

## Why zero NFS impact:

Checked all 3 workers. Results identical — completely clean:

```
worker1: nfsstat -c retrans = 0 out of 32,629 calls
worker2: nfsstat -c retrans = 0
worker3: nfsstat -c retrans = 0
dmesg | grep "server not responding": nothing on any worker
journalctl -k | grep oom: nothing on any worker
```

The reason: CSI driver is only involved at mount/unmount time. Once a PVC is
mounted, the kernel NFS client handles all runtime I/O directly — it talks to
the NAS (10.0.40.120) without going through the CSI plugin at all.

```
CSI driver role:
  Mount time   → CSI needed  (NodePublishVolume)
  Runtime I/O  → kernel NFS client handles directly, CSI NOT involved
  Unmount time → CSI needed  (NodeUnpublishVolume)
```

During the ~2 second CSI restart window, the only risk was: if a NEW pod was
being scheduled and needed to mount a PVC at that exact moment, it would have
failed with a CSI attach error. But nothing was scheduling during that window.

WordPress and MariaDB kept serving the whole time — confirmed by checking logs
during the rollout window:

Command: kubectl logs -l app=wordpress -n apps

Output:
```
10.0.64.12 - [20/Apr/2026:19:11:59] "GET / HTTP/1.1" 200 15242
10.0.64.11 - [20/Apr/2026:19:11:59] "GET / HTTP/1.1" 200 15242
(continuous kube-probe 200s, no errors)
```

## Mount flags confirm soft mount protection:

```
nfsstat -m:
  soft,timeo=30,retrans=3,vers=3,proto=tcp
```

Even if the NAS had gone down during this window, `soft` mount means the kernel
returns an error after ~9 seconds (timeo=30 × retrans=3) instead of hanging
forever.

## Notable finding — worker2 has mixed NFS versions:

```
Prometheus PVC: vers=4.2, hard, timeo=600, retrans=5
Other PVCs:     vers=3,   soft, timeo=30,  retrans=3
```

The Prometheus PVC uses `hard` mount. If the NAS went down, Prometheus on worker2
would hang in uninterruptible D state while everything else would get I/O errors
and move on. Worth noting for DR test planning.

This finding triggered a deeper investigation into why Prometheus ended up on
NFSv4.2 instead of v3 — root cause identified and documented in TS-K8S-048.

_____________________________________________________________________

[Risk Level] MEDIUM

The silent accept was low risk (label just didn't appear). The near-miss with
`app` key overwrite was HIGH risk — would have broken Deployment selector for
the cluster's storage driver. Caught before push by checking matchLabels.

Post-push rollout was clean — full DaemonSet restart with zero NFS impact due to
kernel NFS client independence from CSI plugin at runtime.

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml
- Chart source: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
- TS-K8S-046 — related kustomization stale reference from same editing session
- TS-K8S-015 — prior case where CSI NFS restart DID cause MariaDB crash (different
  scenario: stale NFS handles after config change, not a label-only rollout)

_____________________________________________________________________

[Draft Notes]
Lesson 1: Helm will eat any values you throw at it — silence doesn't mean success.
Always verify labels landed on the actual pods after a rollout. When in doubt,
use `helm show values` to check the chart's actual schema before assuming value
paths from other charts apply.

Lesson 2: When adding labels to pods that already have selector-critical labels
(like `app`), check the Deployment matchLabels first. Overwriting a selector
label will break the cluster silently.

Lesson 3: `customLabels` is chart-wide — changing it restarts EVERYTHING the chart
manages (Deployment + DaemonSet), not just the component you're thinking about.
For CSI NFS, that means every worker's node plugin restarts. Safe in this case
because kernel NFS client is independent, but know that everything restarts.

Lesson 4: The worker2 hard-mount Prometheus PVC is a DR asymmetry — NAS failure
would hit worker2 differently than the soft-mount workers. Good chaos test candidate.
