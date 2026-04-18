# Issue: kube-system TargetDown Alerts - False Positives

**Status:** SUSPENDED
**Date Discovered:** 2026-04-18
**Severity:** Low (false positives, not actual failures)
**Reason Suspended:** Fix requires modifying kubeadm manifests on all 3 masters via Ansible - deferred for later

---

## Summary

Prometheus firing TargetDown and etcd alerts for kube-system components despite all pods being healthy. These are false positives because kubeadm-deployed control plane components don't expose metrics by default.

---

## Alerts Firing

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

---

## Evidence - Cluster Actually Healthy

```bash
kubectl get pods -n kube-system | grep -E "etcd|controller|scheduler|proxy"
```
```
etcd-k8s-master1.lab.local                      1/1     Running   36   22d
etcd-k8s-master2.lab.local                      1/1     Running   35   22d
etcd-k8s-master3.lab.local                      1/1     Running   8    22d
kube-apiserver-k8s-master1.lab.local            1/1     Running   51   22d
kube-apiserver-k8s-master2.lab.local            1/1     Running   45   22d
kube-apiserver-k8s-master3.lab.local            1/1     Running   55   22d
kube-controller-manager-k8s-master1.lab.local   1/1     Running   51   22d
kube-controller-manager-k8s-master2.lab.local   1/1     Running   58   22d
kube-controller-manager-k8s-master3.lab.local   1/1     Running   50   22d
kube-proxy-6c4z6                                1/1     Running   36   22d
kube-proxy-7sx59                                1/1     Running   41   22d
... (all Running)
kube-scheduler-k8s-master1.lab.local            1/1     Running   46   22d
kube-scheduler-k8s-master2.lab.local            1/1     Running   53   22d
kube-scheduler-k8s-master3.lab.local            1/1     Running   51   22d
```

All pods 1/1 Running - this is a scraping issue, not a health issue.

---

## Root Cause

kubeadm-deployed control plane components don't expose metrics endpoints by default:

| Component | Expected Metrics Endpoint | kubeadm Default |
|-----------|---------------------------|-----------------|
| kube-controller-manager | 10.0.61.x:10257/metrics | Binds to 127.0.0.1 only |
| kube-scheduler | 10.0.61.x:10259/metrics | Binds to 127.0.0.1 only |
| kube-proxy | 10.0.6x.x:10249/metrics | May not be exposed |
| etcd | 10.0.61.x:2379/metrics | Requires client certs, localhost only |

kube-prometheus-stack creates ServiceMonitors expecting these endpoints to be reachable from Prometheus pod, but they're not.

---

## Solution Options

### Option 1: Disable ServiceMonitors (Quick Fix)

Add to `helm-release.yaml` under `values:`:

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

**Pros:** Stops false positives immediately
**Cons:** Loses control plane monitoring

### Option 2: Expose Metrics (Proper Fix)

Modify kubeadm component configs to bind metrics to 0.0.0.0:

**kube-controller-manager** (`/etc/kubernetes/manifests/kube-controller-manager.yaml`):
```yaml
spec:
  containers:
  - command:
    - kube-controller-manager
    - --bind-address=0.0.0.0  # Add this
```

**kube-scheduler** (`/etc/kubernetes/manifests/kube-scheduler.yaml`):
```yaml
spec:
  containers:
  - command:
    - kube-scheduler
    - --bind-address=0.0.0.0  # Add this
```

**kube-proxy** (via ConfigMap):
```bash
kubectl edit configmap kube-proxy -n kube-system
# Set metricsBindAddress: 0.0.0.0:10249
kubectl rollout restart daemonset kube-proxy -n kube-system
```

**etcd** - More complex, requires exposing metrics endpoint with proper certs.

**Pros:** Full control plane monitoring
**Cons:** More complex, requires manifest changes on all masters

### Option 3: Use kube-prometheus-stack kubeadm-specific config

Some versions of kube-prometheus-stack have kubeadm-specific ServiceMonitor configs that scrape via localhost. Check if available:

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

---

## TODO

- [ ] Decide: disable ServiceMonitors or expose metrics
- [ ] If exposing metrics, update manifests on all 3 masters
- [ ] Test Prometheus can scrape after changes
- [ ] Verify alerts resolve

---

## Related

- Discovered after 2026-04-18 cluster outage recovery
- These alerts were firing BEFORE the incident but went unnoticed
- The incident caused additional PodCrashLooping alerts which have since resolved
