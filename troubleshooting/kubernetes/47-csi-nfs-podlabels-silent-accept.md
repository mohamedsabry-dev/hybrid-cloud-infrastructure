# TS-K8S-047 | 2026-04-20 | RESOLVED
_____________________________________________________________________

[Info]
Author: Sabry
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
selectors — which touches too many things with real blast radius on storage —
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

Verified: Pending push — diff confirms correct change

_____________________________________________________________________

[Risk Level] MEDIUM

The silent accept was low risk (label just didn't appear). The near-miss with
`app` key overwrite was HIGH risk — would have broken Deployment selector for
the cluster's storage driver. Caught before push by checking matchLabels.

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml
- Chart source: https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/charts
- TS-K8S-046 — related kustomization stale reference from same editing session

_____________________________________________________________________

[Draft Notes]
Lesson: Helm will eat any values you throw at it — silence doesn't mean success.
Always verify labels landed on the actual pods after a rollout. When in doubt,
use `helm show values` to check the chart's actual schema before assuming value
paths from other charts apply.

Second lesson: when adding labels to pods that already have selector-critical
labels (like `app`), check the Deployment matchLabels first. Overwriting a
selector label is a silent cluster bomb.
