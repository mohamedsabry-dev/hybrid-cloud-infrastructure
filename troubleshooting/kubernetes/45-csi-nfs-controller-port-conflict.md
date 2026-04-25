# TS-K8S-045 | 2026-04-18 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Storage / CSI NFS
Sub-techs: CSI NFS controller, liveness probe port conflict, podAntiAffinity,
           CrashLoopBackOff, Flux HelmRelease
Environment: DEV k8s cluster | CSI NFS controller replicas=2
Discovered during: Post-DR Test 2 recovery
Related: TS-K8S-036 (Grafana anti-affinity — same scheduling pattern)
Re-opened: No

_____________________________________________________________________

[Issue Description]
CSI NFS controller deployment (replicas=2) scheduled both pods on the same
worker node, causing liveness probe port conflict and CrashLoopBackOff.

```
kubectl get pods -n kube-system | grep csi-nfs-controller
csi-nfs-controller-8455c76c5f-8k7xv   4/5   CrashLoopBackOff   52 (2m4s ago)   107m   k8s-worker3.lab.local
csi-nfs-controller-8455c76c5f-9p4tt   5/5   Running            28 (5m17s ago) 159m   k8s-worker3.lab.local
```

Both on worker3 — one crashing, one running.

_____________________________________________________________________

[Analysis]

During DR test, workers 1 and 2 were down. Both controller pods got scheduled
to worker3 (only available worker). Second pod couldn't bind to liveness probe
port:

```
listen tcp 127.0.0.1:29652: bind: address already in use
```

CSI NFS controller uses liveness probe on `127.0.0.1:29652`. Two pods on the
same node = port conflict on `127.0.0.1`.

The deployment had `nodeAffinity` (run on workers only, not control-plane) but
NO `podAntiAffinity` to prevent co-location.

```
Before Fix:
┌─────────┐ ┌─────────┐ ┌─────────┐
│ worker1 │ │ worker2 │ │ worker3 │
│  (down) │ │  (down) │ │ csi-1   │ ← Both here!
│         │ │         │ │ csi-2   │   Port conflict!
└─────────┘ └─────────┘ └─────────┘
```

_____________________________________________________________________

[Final Root Cause]
CSI NFS controller uses a host-bound liveness probe port (`127.0.0.1:29652`).
With no `podAntiAffinity`, both replicas can schedule on the same node. When
they do, the second pod crashes because the port is already in use.

_____________________________________________________________________

[Final Solution]

Added `podAntiAffinity` to CSI NFS controller helm values:

File: `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`

```yaml
controller:
  replicas: 2
  priorityClassName: system-cluster-critical
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
          - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: csi-nfs-controller
          topologyKey: kubernetes.io/hostname
```

After Flux applied the change:
```
kubectl get pods -n kube-system -l app=csi-nfs-controller -o wide
NAME                                  READY   NODE
csi-nfs-controller-xxx-aaa            5/5     k8s-worker1.lab.local
csi-nfs-controller-xxx-bbb            5/5     k8s-worker2.lab.local
```

Each pod on a different worker. No more port conflict.

Verified: Yes — pods spread across workers, no CrashLoopBackOff.

_____________________________________________________________________

[Risk Level] MEDIUM

CrashLoopBackOff on one controller pod means reduced CSI availability. The
running pod still handles provisioning, but no redundancy.

_____________________________________________________________________

[References]
- TS-K8S-036 — Grafana anti-affinity rollout stuck (same scheduling pattern)
