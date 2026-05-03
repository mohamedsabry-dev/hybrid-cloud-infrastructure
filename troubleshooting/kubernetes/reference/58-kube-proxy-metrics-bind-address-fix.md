# TS-K8S-058 | 2026-05-01 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring / Prometheus / kube-proxy
Sub-techs: kube-proxy DaemonSet, ConfigMap, metricsBindAddress,
           Prometheus scraping, Flux GitOps, Kustomize
Environment: DEV k8s cluster | 3 masters (kubeadm) + 3 workers
Severity: LOW
Parent ticket: TS-K8S-039 (kube-system TargetDown false positives)
Related: TS-K8S-054 (scheduler + controller-manager bind-address fix — same root cause, different fix path)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Prometheus firing TargetDown for `job="kube-proxy"` — can't scrape
kube-proxy metrics on any node. Same class of problem as TS-K8S-054
(scheduler/controller-manager), but different fix because kube-proxy
is a DaemonSet, not a static pod.

_____________________________________________________________________

[Analysis]

# How I found it

Still clearing the remaining alerts from TS-K8S-039. Yesterday's
TS-K8S-054 fixed scheduler and controller-manager (static pod
bind-address). Kube-proxy was next on the list.

# Why kube-proxy is different

Scheduler and controller-manager are static pods — config lives as
manifest files on each master's disk. You edit the file, kubelet
restarts the pod.

Kube-proxy is a DaemonSet — managed by the cluster, runs on every
node. Config lives in a ConfigMap (`kube-proxy` in `kube-system`).
Edit the ConfigMap, then rollout restart the DaemonSet.

# The actual problem

```
kubectl get configmap kube-proxy -n kube-system -o yaml | grep metricsBindAddress
    metricsBindAddress: ""
```

Empty string = defaults to `127.0.0.1:10249`. Prometheus runs as a
pod in its own network namespace — can't reach localhost on other nodes.
Same story as scheduler/controller-manager, just a different config path.

# Flux approach — same as CoreDNS

Instead of just `kubectl edit` (which gets wiped on kubeadm upgrade),
I followed the same approach we used for CoreDNS: full ConfigMap copy
in the repo, managed by Flux through Kustomize.

Already had a `kube-proxy/` folder under `infrastructure/` — it was
set up but had the wrong file in it (a copy of the CoreDNS config,
probably from when I was setting up the folder structure). Cleaned
that up and put the actual kube-proxy ConfigMap in its place.

Changed only `metricsBindAddress: ""` → `metricsBindAddress: "0.0.0.0:10249"`.
Stripped the cluster-generated metadata (creationTimestamp, resourceVersion,
uid, kubeadm hash annotation) since Flux owns it now.

The parent `infrastructure/kustomization.yaml` already had `kube-proxy`
in its resources list, so the chain works:
```
infrastructure/kustomization.yaml → kube-proxy/ → kube-proxy-custom.yaml
```

Flux applies it, takes ownership. Even if kubeadm resets the ConfigMap
during a future cluster upgrade, Flux overwrites it back on the next
reconcile cycle. Same survival guarantee as our CoreDNS custom config.

_____________________________________________________________________

[Final Root Cause]
kube-proxy's `metricsBindAddress` defaults to empty string, which
resolves to `127.0.0.1:10249`. Prometheus can't scrape it from a
different network namespace. Been like this since cluster creation —
same root cause family as TS-K8S-054.

_____________________________________________________________________

[Final Solution]

ConfigMap change managed through Flux:

File: `kubernetes/dev/deployments/infrastructure/kube-proxy/kube-proxy-custom.yaml`

Only change from the kubeadm default:
```yaml
metricsBindAddress: "0.0.0.0:10249"
```

After Flux applies the ConfigMap, restart the DaemonSet to pick it up:
```
kubectl rollout restart daemonset kube-proxy -n kube-system
```

Kube-proxy pods don't auto-reload ConfigMap changes — they need a
restart. DaemonSet rolling update handles this safely: `maxUnavailable: 1`,
one pod at a time, existing iptables rules stay loaded in the kernel
during the restart window so traffic isn't affected.

Verified: Pending — waiting for Flux reconcile + rollout restart on
dev cluster. TargetDown alert for kube-proxy should clear after first
Prometheus scrape cycle.

_____________________________________________________________________

[Risk Level] LOW

Same as TS-K8S-054 — only changes which interface the metrics endpoint
listens on. No impact on proxy logic or iptables rules. Rolling restart
means one node at a time with near-zero traffic impact.

_____________________________________________________________________

[References]
- TS-K8S-039 — Parent ticket: kube-system TargetDown false positives (kube-proxy was one of the 4 remaining)
- TS-K8S-054 — Scheduler + controller-manager bind-address fix (same root cause, static pod path)
- kubernetes/dev/deployments/infrastructure/kube-proxy/kube-proxy-custom.yaml — the Flux-managed ConfigMap
- kubernetes/dev/deployments/infrastructure/coredns/coredns-custom.yaml — same Flux approach used here
- Remaining from TS-K8S-039: etcd metrics (requires cert config — separate ticket)
