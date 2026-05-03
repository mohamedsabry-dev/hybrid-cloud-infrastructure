# TS-K8S-054 | 2026-04-30 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Monitoring / Prometheus / Control Plane
Sub-techs: kube-scheduler, kube-controller-manager, kubeadm static pods,
           --bind-address, Prometheus scraping, Grafana dashboards
Environment: DEV + PROD k8s clusters | 3 masters (kubeadm) + 3 workers each
Severity: MEDIUM
Discovered during: DR Test — Control Plane Component Failures (scenario 1a)
Parent ticket: TS-K8S-039 (kube-system TargetDown false positives)
Related: DR test plan — GROUP 1: Control Plane Component Failures
Re-opened: No

_____________________________________________________________________

[Issue Description]
Scheduler and controller-manager metrics completely invisible in Grafana.
All dashboards showing "No data" or "Up: 0" across all 3 masters. Both
dev and prod affected — been broken since initial cluster setup.

Found this while running DR test 1a (scheduler down on 1 node). Went to
Grafana to observe the break and realized there was nothing to observe —
metrics were never being scraped in the first place.

_____________________________________________________________________

[Analysis]

# How I found it

Started DR test scenario 1a — kill the scheduler on one master and observe
the impact across all 5 monitoring sources (Prometheus, Grafana, Alertmanager,
Loki, kubectl).

Moved the scheduler manifest out on master1:

```
mv /etc/kubernetes/manifests/kube-scheduler.yaml /root/kube-scheduler.yaml.bak
```

Confirmed the break:

```
[root@k8s-master1 ~]# kubectl get pods -n kube-system | grep scheduler
kube-scheduler-k8s-master2.lab.local            1/1     Running   123 (27m ago)   34d
kube-scheduler-k8s-master3.lab.local            1/1     Running   128 (27m ago)   34d
```

Master1 scheduler gone. Good. Went to Grafana → Kubernetes / Scheduler
dashboard to see the impact. Dashboard showed Up: 0, everything "No data."

Checked with instance filter set to each master — all 0. Checked prod
cluster — same thing. Nobody touched prod. This has been broken from day 1.

# Connection to TS-K8S-039

Immediately recognized this was the same root cause as the suspended
ticket TS-K8S-039 — Prometheus firing TargetDown alerts for scheduler,
controller-manager, etcd, and kube-proxy because it couldn't scrape
any of them.

TS-K8S-039 was suspended because the fix needed modifying kubeadm
manifests on all 3 masters. The workaround at the time was just
suspending the ticket. But now I'm running DR tests that depend on
these metrics — the workaround of "ignore it" doesn't work anymore.
I need actual observability to validate DR scenarios.

# Why I didn't use Ansible

The fix touches static pod manifests on control plane nodes. Changing
--bind-address on scheduler and controller-manager restarts those
components. Hitting all 3 masters at once — even with serial: 1 and
sleep delays — means I'm blindly trusting automation on the control
plane during a restart. If something goes wrong mid-playbook I'd be
chasing it instead of watching it.

Manual one-by-one: fix master1, verify metrics appear, fix master2,
verify, fix master3, verify. Rolling change with eyes on each step.
This is how you'd do it in production.

# Why I fixed both scheduler and controller-manager together

Same fix, same file location pattern, same root cause. The bind-address
issue affects both identically:

| Component            | Manifest Path                                        | Metric Port |
|----------------------|------------------------------------------------------|-------------|
| kube-scheduler       | /etc/kubernetes/manifests/kube-scheduler.yaml         | 10259       |
| kube-controller-mgr  | /etc/kubernetes/manifests/kube-controller-manager.yaml| 10257       |

Both default to `--bind-address=127.0.0.1` under kubeadm. Prometheus
can't reach 127.0.0.1 from a pod on a different node. Fix is the same
line change in both manifests.

_____________________________________________________________________

[Final Root Cause]
kubeadm sets `--bind-address=127.0.0.1` by default on kube-scheduler
and kube-controller-manager static pods. This binds the metrics endpoint
to localhost only — Prometheus (running as a pod with its own network
namespace) cannot reach it. All scheduler and controller-manager metrics
have been invisible since cluster creation.

_____________________________________________________________________

[Final Solution]

Changed `--bind-address=127.0.0.1` to `--bind-address=0.0.0.0` in both
manifests on all 3 masters. Applied manually, one master at a time with
verification between each.

On each master:

```
# Scheduler
vi /etc/kubernetes/manifests/kube-scheduler.yaml
# Change: --bind-address=127.0.0.1
# To:     --bind-address=0.0.0.0

# Controller-Manager
vi /etc/kubernetes/manifests/kube-controller-manager.yaml
# Change: --bind-address=127.0.0.1
# To:     --bind-address=0.0.0.0
```

Kubelet detects the manifest change and auto-restarts the static pod —
no manual restart needed.

# Verification

After applying on master1, Grafana Kubernetes / Scheduler dashboard:
- Up: 1 (was 0)
- Memory: 54.9 MiB showing for 10.0.61.10:10259
- Goroutines: 252
- Scheduling Rate and Latency panels populated after ~2 minutes
  (needed a scrape cycle + actual scheduling activity)

After all 3 masters:
- Up: 3
- All panels showing data for all instances
- Controller-manager dashboard same — all 3 instances visible

# Rollout sequence

1. Master1 — scheduler + controller-manager → verified Up: 1 on both dashboards
2. Master2 — same → verified Up: 2
3. Master3 — same → verified Up: 3

Zero downtime. Each component restarted in seconds. Leader election
handled the brief absence of each instance transparently.

# Loki evidence — leader election during rolling fix

LogQL query: `{namespace="kube-system", pod=~"kube-scheduler.*"} |= "leader"`

Master1 fix (done first, alone):
```
12:45:50  E leaderelection.go:445  "Failed to update lease optimistically, falling back to slow path"
          err="context canceled" lock="kube-system/kube-scheduler"
12:45:51  E leaderelection.go:452  "Error retrieving lease lock" err="context canceled"
12:45:51  I leaderelection.go:299  "Failed to renew lease" err="context canceled"
12:45:51  E leaderelection.go:336  "Failed to release lease" err="the object has been modified"
12:46:04  I leaderelection.go:258  "Attempting to acquire leader lease..."
12:46:08  I leaderelection.go:272  "Successfully acquired lease"
```

Scheduler killed by kubelet manifest change → lease lost → re-acquired
after restart in ~18 seconds. Error cascade is normal — context canceled
because the process was shutting down mid-renewal.

Master2 + Master3 fix (done simultaneously after master1 stable):
```
12:36:03  I leaderelection.go:258  "Attempting to acquire leader lease..."
12:37:25  I leaderelection.go:258  "Attempting to acquire leader lease..."
```

Both restarted and re-attempted lease acquisition. No errors — master1
held the lease throughout since it was already fixed and stable.

Applied same fix to prod after confirming dev was clean — same rolling
approach, one master at a time with verification.

_____________________________________________________________________

[Risk Level] LOW

Changing bind-address only affects which interface the metrics endpoint
listens on. No impact on scheduling or controller logic. Kubelet
auto-restarts the pod — downtime per component per node is seconds,
and HA (3 masters) covers the gap.

Security note: 0.0.0.0 exposes the metrics port to the pod network.
Acceptable in this environment — cluster network is trusted and
metrics endpoints are read-only.

_____________________________________________________________________

[Decision Notes]

I was mid-DR test when I hit this. Could have continued the test using
kubectl-only observation and fixed the metrics later. But the whole
point of the DR test framework is validating with all 5 observation
sources — Prometheus, Grafana, Alertmanager, Loki, kubectl. Running
the test without metrics defeats the purpose.

The suspended ticket (TS-K8S-039) had been sitting for 12 days waiting
for "later." The DR test made "later" turn into "now" — can't test
what I can't observe.

Still remaining from TS-K8S-039: kube-proxy and etcd metrics. Those
are different fixes (ConfigMap for proxy, cert config for etcd). Will
handle as separate tickets.

_____________________________________________________________________

[References]
- TS-K8S-039 — Parent ticket: kube-system TargetDown false positives (SUSPENDED → partially resolved by this fix)
- DR Test Plan — GROUP 1: Control Plane Component Failures, scenario 1a (scheduler down — 1 node)
- /etc/kubernetes/manifests/kube-scheduler.yaml — modified on all 3 masters
- /etc/kubernetes/manifests/kube-controller-manager.yaml — modified on all 3 masters
- Applied to both DEV and PROD clusters
