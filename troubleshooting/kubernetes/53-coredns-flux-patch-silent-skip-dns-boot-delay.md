# TS-K8S-053 | 2026-04-26 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / CoreDNS / Flux GitOps / Cold Boot
Sub-techs: CoreDNS deployment, Flux kustomize patches: vs resources:,
           server-side apply (SSA), nodeSelector, control-plane scheduling,
           boot dependency chain, DNS availability timing
Environment: PROD k8s cluster | 3 masters + 3 workers
Severity: HIGH
Discovered during: Pod lifecycle investigation — remediation pod Unknown for ~5 min after cold boot
Related: TS-K8S-044 (original CoreDNS HA fix — re-opened, root cause was incomplete)
Re-opened: No (new ticket — re-opens TS-K8S-044)

_____________________________________________________________________

[Issue Description]
CoreDNS pods were running on worker nodes in prod despite the Flux
kustomization patch existing in the git repo. The patch was silently
skipped because it used `patches:` instead of `resources:` — and
CoreDNS Deployment isn't part of the kustomize build, it's managed
by kubeadm.

This meant on every cold boot, CoreDNS couldn't start until workers
came up (~3 minutes after masters), leaving DNS unavailable for ~3.5
minutes. Every DNS-dependent workload — Vault agent init, CSI leader
election, Flux reconciliation — was blocked during that window.

_____________________________________________________________________

[Analysis]

# How I found it

Was investigating why remediation pod sat in Unknown for ~5 minutes
after cluster cold boot (TS-K8S-052). Went deep into kubelet logs,
boot sequence events, the whole control-plane startup chain. Spent a
while tracing etcd → apiserver → controller-manager → calico, trying
to understand what was bottlenecking.

Then noticed the pattern — workers fire NodeNotReady events, expected
(I have 3-minute delay before workers boot after masters). But also saw
CoreDNS getting TaintManagerEviction'd and recreated. Why would CoreDNS
care about worker status?

Checked where the pods were running:

```
kubectl describe pod coredns-797d5558c8-58s4z -n kube-system
Node:                 k8s-worker3.lab.local/10.0.54.12
```

That's a worker. Both CoreDNS pods were on workers.

# Wait, I already fixed this

First reaction — "forgot to mirror this config to prod" — because I
fixed this exact thing in TS-K8S-044 during DR Test 2. But checked the
repo and config already there:

```yaml
# kubernetes/prod/deployments/infrastructure/coredns/coredns-patch.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
spec:
  template:
    spec:
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
                  k8s-app: kube-dns
              topologyKey: kubernetes.io/hostname
```

Config in git, Flux says "Applied revision" with no errors. So what's
going on?

# The gotcha — dev vs prod comparison

Compared `kubectl describe pod coredns` between dev and prod:

Dev (working):
```
Node-Selectors:  kubernetes.io/os=linux
                 node-role.kubernetes.io/control-plane=
```

Prod (broken):
```
Node-Selectors:  kubernetes.io/os=linux
```

Prod missing `node-role.kubernetes.io/control-plane=` entirely.
Despite config in repo. Despite Flux saying reconciled successfully.

# The actual root cause — patches: vs resources:

Checked what Flux actually managed:

```
kubectl describe kustomization infrastructure -n flux-system | grep coredns
      Id:                     kube-system_coredns__ConfigMap
```

Only the ConfigMap (Corefile with custom hosts entries). No Deployment.

The kustomization.yaml was using:

```yaml
patches:
  - path: coredns-patch.yaml
    target:
      kind: Deployment
      name: coredns
      namespace: kube-system
```

Tells kustomize "find a Deployment named coredns in your resources list
and patch it." But CoreDNS Deployment managed by kubeadm, NOT in the
kustomize resources list. Kustomize had nothing to patch — **silent no-op**.

# Why dev worked — the false positive

On dev I applied the CoreDNS patch manually first (TS-K8S-044), then
set up Flux to manage it. Flux adopted the ConfigMap via SSA but
Deployment already had the manual nodeSelector. Looked like Flux was
managing it, but never actually applied the Deployment patch. Copied
same pattern to prod without realizing the manual step was the real fix.

# Boot timing evidence — before fix (Test 1)

Master boot: 10:56:51 local (07:56 UTC)
Worker boot: 10:59 local (07:59 UTC) — 3 min delay by design

CoreDNS on workers → couldn't start until workers ready:
```
08:00:39  SandboxChanged  coredns-797d5558c8-58s4z  (worker)
08:00:40  Started         coredns-797d5558c8-58s4z
08:00:40  Started         coredns-797d5558c8-ddvss
```

**DNS available at 08:00:40 = ~3 min 35 sec after master boot**

Everything DNS-dependent stacked behind this:
- Calico unhealthy until BGP stabilized (needs API → needs DNS)
- CSI NFS controllers restarting (leader election via watch streams)
- Vault agent init blocked (DNS lookup for vault.lab.local)

_____________________________________________________________________

[Final Root Cause]
Flux kustomize `patches:` block targets resources within the same
kustomize build. CoreDNS Deployment is managed by kubeadm, not part
of the Flux build — so the nodeSelector/toleration/antiAffinity patch
was silently skipped. CoreDNS pods scheduled on workers, adding ~3.5
minutes to DNS availability on every cold boot.

Dev masked the issue because the patch was applied manually first.

_____________________________________________________________________

[Final Solution]

Changed the kustomization to apply coredns-patch.yaml as a direct
`resources:` entry instead of a `patches:` entry. This uses Kubernetes
server-side apply (SSA) to merge into the existing Deployment.

Updated coredns-patch.yaml to include required fields for SSA:
→ kubernetes/prod/deployments/infrastructure/coredns/coredns-patch.yaml

Key changes from the old patch file:
- Added `spec.selector.matchLabels` — required for Deployment as full resource
- Added `template.metadata.labels` — must match selector
- Added `kubernetes.io/os: linux` to nodeSelector — SSA would remove it otherwise

Updated kustomization.yaml:
```yaml
resources:
  - coredns-custom.yaml
  - coredns-patch.yaml    # was under patches: block before
```

Applied to dev first, verified, then mirrored to prod.

# Verification — Flux owns both ConfigMap and Deployment now

```
kubectl describe deployment coredns -n kube-system | grep -A5 "Labels:"
Labels:                 k8s-app=kube-dns
                        kustomize.toolkit.fluxcd.io/name=infrastructure
                        kustomize.toolkit.fluxcd.io/namespace=flux-system

kubectl describe kustomization infrastructure -n flux-system | grep coredns
      Id:                     kube-system_coredns__ConfigMap
      Id:                     kube-system_coredns_apps_Deployment
  Normal  Progressing  kustomize-controller  Deployment/kube-system/coredns configured
```

Before: only ConfigMap in inventory.
After: both ConfigMap AND Deployment.

# Verification — boot timing after fix (Test 2)

Rebooted prod cluster. CoreDNS now on masters:

```
kubectl get pod -A -o wide | grep coredns
kube-system  coredns-7cfc478ff9-cjx44  1/1  Running  k8s-master3.lab.local
kube-system  coredns-7cfc478ff9-dntwx  1/1  Running  k8s-master1.lab.local
```

Boot timing with fix:
```
10:49:56  Master boot (all control-plane SandboxChanged)
10:51:30  CoreDNS SandboxChanged + Started on both pods
```

**DNS available at 10:51:30 = 94 seconds after boot**

Improvement: 3 min 35 sec → 94 seconds (~56% faster DNS availability)

# Downstream impact

- Boot-to-stable: ~7 min → ~4 min
- CSI NFS controller restarts: halved (leader election stabilizes faster
  when watch streams can resolve DNS sooner)
- Remediation pod: vault-agent-init unblocked sooner (DNS resolves
  vault.lab.local earlier)

Verified: Yes — two cold boot tests, before and after.

_____________________________________________________________________

[Risk Level] HIGH

Every cold boot had ~3.5 minute window with no cluster DNS. All
DNS-dependent workloads — Vault injection, CSI leader election, Flux
reconciliation — blocked. Silent failure mode (Flux says "Applied"
with no errors) makes this especially dangerous because it looks like
everything is working.

_____________________________________________________________________

[References]
- TS-K8S-044 — Original CoreDNS HA fix (re-opened — manual apply masked the Flux issue)
- TS-K8S-052 — Remediation pod startup delay (found during same investigation, same boot window)
- TS-PVE-017 — Proxmox disk throttle config (disk IO limits that compounded the boot delay)
- kubernetes/prod/deployments/infrastructure/coredns/coredns-patch.yaml — fixed patch file
- kubernetes/prod/deployments/infrastructure/coredns/kustomization.yaml — resources: vs patches:
