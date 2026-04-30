# TS-K8S-039 | 2026-04-18 | SUSPENDED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring / Prometheus
Sub-techs: kube-prometheus-stack, ServiceMonitor, kubeadm manifests,
           TargetDown alerts, etcd metrics, control plane scraping
Environment: DEV k8s cluster | 3 masters (kubeadm) + 3 workers
Reason suspended: Fix requires modifying kubeadm manifests on all 3 masters
                  via Ansible — deferred for later
Discovered during: Post-cluster-outage recovery (2026-04-18)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Prometheus firing TargetDown and etcd alerts for kube-system components despite
all pods being healthy. False positives — kubeadm-deployed control plane
components don't expose metrics by default.

```
alertname = TargetDown
job = kube-controller-manager
description = 100% of the kube-controller-manager targets in kube-system namespace are down.

alertname = TargetDown
job = kube-etcd
description = 100% of the kube-etcd targets in kube-system namespace are down.

alertname = TargetDown
job = kube-proxy
description = 100% of the kube-proxy targets in kube-system namespace are down.

alertname = TargetDown
job = kube-scheduler
description = 100% of the kube-scheduler targets in kube-system namespace are down.

alertname = etcdMembersDown
description = etcd cluster "kube-etcd": members are down (3).

alertname = etcdInsufficientMembers
description = etcd cluster "kube-etcd": insufficient members (0).
```

_____________________________________________________________________

[Analysis]

# Step 1: Confirmed cluster is actually healthy

```
kubectl get pods -n kube-system | grep -E "etcd|controller|scheduler|proxy"
etcd-k8s-master1.lab.local                      1/1     Running   36   22d
etcd-k8s-master2.lab.local                      1/1     Running   35   22d
etcd-k8s-master3.lab.local                      1/1     Running   8    22d
kube-controller-manager-k8s-master1.lab.local   1/1     Running   51   22d
kube-controller-manager-k8s-master2.lab.local   1/1     Running   58   22d
kube-controller-manager-k8s-master3.lab.local   1/1     Running   50   22d
kube-proxy-6c4z6                                1/1     Running   36   22d
kube-proxy-7sx59                                1/1     Running   41   22d
kube-scheduler-k8s-master1.lab.local            1/1     Running   46   22d
kube-scheduler-k8s-master2.lab.local            1/1     Running   53   22d
kube-scheduler-k8s-master3.lab.local            1/1     Running   51   22d
```

All pods 1/1 Running. This is a scraping issue, not a health issue.

_____________________________________________________________________

[Final Root Cause]
kubeadm-deployed control plane components don't expose metrics endpoints by
default:

| Component | Expected Endpoint | kubeadm Default |
|-----------|-------------------|-----------------|
| kube-controller-manager | 10.0.61.x:10257 | Binds to 127.0.0.1 only |
| kube-scheduler | 10.0.61.x:10259 | Binds to 127.0.0.1 only |
| kube-proxy | 10.0.6x.x:10249 | May not be exposed |
| etcd | 10.0.61.x:2379 | Requires client certs, localhost only |

kube-prometheus-stack creates ServiceMonitors expecting these endpoints to be
reachable from the Prometheus pod, but they're not.

These alerts were firing BEFORE the 2026-04-18 cluster outage but went unnoticed.

_____________________________________________________________________

[Final Solution]

SUSPENDED — two options identified:

Option 1 (quick): Disable ServiceMonitors in helm-release.yaml:
```yaml
kubeControllerManager:
  enabled: false
kubeScheduler:
  enabled: false
kubeProxy:
  enabled: false
kubeEtcd:
  enabled: false
```
Stops false positives but loses control plane monitoring.

Option 2 (proper): Expose metrics by modifying kubeadm manifests on all 3
masters to add `--bind-address=0.0.0.0`:
```yaml
# /etc/kubernetes/manifests/kube-controller-manager.yaml
- --bind-address=0.0.0.0

# /etc/kubernetes/manifests/kube-scheduler.yaml
- --bind-address=0.0.0.0
```

kube-proxy via ConfigMap:
```
kubectl edit configmap kube-proxy -n kube-system
# Set metricsBindAddress: 0.0.0.0:10249
kubectl rollout restart daemonset kube-proxy -n kube-system
```

etcd is more complex — requires exposing metrics endpoint with proper certs.

Option 3: Use kube-prometheus-stack kubeadm-specific ServiceMonitor config with
explicit master endpoints:
```yaml
kubeControllerManager:
  endpoints:
    - 10.0.61.10
    - 10.0.61.11
    - 10.0.61.12
  service:
    enabled: true
    port: 10257
    targetPort: 10257
```

TODO: decide approach and implement via Ansible across all 3 masters.

_____________________________________________________________________

[Risk Level] LOW

False positives only — no actual impact on cluster health or functionality.

_____________________________________________________________________

[References]
- Discovered after 2026-04-18 cluster outage recovery (TS-K8S-042)
- TS-K8S-054 — Scheduler + controller-manager bind-address fix (partial resolution, 2026-04-30)
- Remaining: kube-proxy (ConfigMap fix) and etcd (cert config) — separate tickets
