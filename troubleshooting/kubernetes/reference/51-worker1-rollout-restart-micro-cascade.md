# TS-K8S-051 | 2026-04-25 | RESOLVED | IMPROVEMENT
_____________________________________________________________________

[Info]
Domain: Kubernetes / Worker Node / Resource Pressure
Sub-techs: kubectl rollout restart, calico exec probes, pod density, CPU contention
Environment: dev
Re-opened: No

_____________________________________________________________________

[Issue Description]
After resolving the IO cascade root cause (TS-PVE-DEV-002), I did a cluster-wide
`kubectl rollout restart` to zero out restart counters for cleaner dashboards.

Worker1 hit ~70% sustained CPU for 39 minutes (02:14–02:53 EEST). Pod startups
took abnormally long — calico-node 4m24s, wordpress 7m13s (normal: 10–60s).
Calico exec probes timed out at 10s but didn't breach failureThreshold, so no
restart cascade triggered. Other workers were fine. Self-recovered.

Same probe-timeout mechanism as TS-PVE-DEV-002 but stayed local to worker1.

_____________________________________________________________________

[Analysis]

Worker1 was carrying 14 pods including the heaviest workloads in the cluster:
prometheus, csi-nfs-controller (5 containers), ingress-nginx, kube-state-metrics,
wordpress (2 containers), plus 6 DaemonSets. All on 2 CPU cores and 2.3GB
allocatable memory.

The rollout restart tore down and recreated all 14 simultaneously. Each new pod
competed for CPU during image checks, container creation, and probe spawning.
Both cores maxed out for ~40 minutes.

From kubelet logs:
  calico-node podStartSLOduration: 264.2s (normal: ~20s)
  wordpress podStartSLOduration: 433.4s (normal: ~45s)

Calico exec probe timeouts (10s deadline exceeded):
  02:17:20 — /bin/calico-node -felix-live -bird-live
  02:17:21 — /bin/calico-node -felix-ready -bird-ready

Post-recovery (03:03), kubelet was still hitting its own client-side QPS limiter
on SubjectAccessReview calls — the system was still settling 40+ minutes later.

Why it stayed contained (vs TS-PVE-DEV-002 full cascade):
- Rollout restart creates LOCAL CPU work (container starts). Master rejoin storm
  creates NETWORK work (controller LISTs through etcd → all masters' NVMe).
- Local pressure stays local. etcd/IO pressure goes everywhere.
- Host NVMe was not saturated — single VM doing local work.
- failureThreshold prevented actual probe-driven restart cascade.

_____________________________________________________________________

[Final Root Cause]
14 pods recreated simultaneously on a 2-core VM with the cluster's heaviest
pod density. Pure CPU starvation — not IO, not network, not etcd.

The deeper issue: worker1 was overloaded even before the restart. Memory at 96%,
OOM events happening periodically. With flux controllers + prometheus +
metrics-server + csi-nfs-controller all on one 2.75GB node, there wasn't enough
headroom for normal operations, let alone a mass restart.

_____________________________________________________________________

[Final Solution]
RESOLVED — this case directly drove the 2-worker drift decision (kubernetes/DESIGN.md §8).

The real fix wasn't about the rollout restart — it was about the resource model.
3 workers × 2.75GB each = 8.25GB gross, but each node burns ~500MB on OS + DaemonSet
overhead. 2 workers × 4GB each = 8GB gross with only 2× overhead instead of 3×,
giving more usable memory per node.

Changes applied:
- Worker1 + Worker2: RAM 2816 → 4096 MB (terraform variables.tf)
- Worker3: `started: false`, `on_boot: false` (shut down, excluded from boot sequence)
- Remediation pod: worker3 removed from NODE_MAP (configmap.yaml)

Worker3 VM preserved in Terraform state — `started: true` brings it back if needed.

_____________________________________________________________________

[Risk Level] LOW — self-recovered, no service impact, root cause addressed by drift

_____________________________________________________________________

[References]
- TS-PVE-DEV-002 — full IO cascade root cause (same probe-timeout pattern at larger scale)
- TS-K8S-038 — qemu-ga EAGAIN busy loop (separate trigger, same investigation window)
- TS-K8S-030 — worker3 memory exhaustion VM crash (earlier instance of same resource pressure)
- kubernetes/DESIGN.md §8 — 2-worker drift decision driven by this case
