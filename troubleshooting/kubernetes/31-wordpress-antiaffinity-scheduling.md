# TS-K8S-031 | 2026-04-15 | RESOLVED (No Action Required)
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes
Sub-techs: Pod anti-affinity, soft vs hard scheduling, topology spread constraints,
           Kubernetes scheduler scoring
Environment: DEV k8s-dev cluster | apps namespace | WordPress deployment
Re-opened: No

_____________________________________________________________________

[Issue Description]
WordPress pods (3 replicas) scheduled unevenly despite anti-affinity configuration.
Discovered during IPA Domain Down DR Test (Part 2).

  Pod distribution:
  wordpress-56bf4b697d-87tvx  k8s-worker3  ← 2 pods on same node
  wordpress-56bf4b697d-8k8jc  k8s-worker3
  wordpress-56bf4b697d-vxc69  k8s-worker1
  (k8s-worker2: 0 pods)

  Expected: 1 pod per worker (even distribution).

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked scheduling timeline and node resource allocation at scheduling time.

Scheduling order:
  6m25s: Pod 87tvx → worker3 (first)
  6m13s: Pod 8k8jc → worker3 (second — same node)
  6m3s:  Pod vxc69 → worker1 (third)

Node resource allocation at scheduling time:
  k8s-worker1   CPU: 1280m (64%)   Memory: 898Mi (31%)   Moderate
  k8s-worker2   CPU: 1380m (69%)   Memory: 788Mi (27%)   Highest CPU
  k8s-worker3   CPU: 1230m (61%)   Memory: 508Mi (17%)   Lowest — SCHEDULER PREFERRED

Current anti-affinity configuration:
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:   ← SOFT (preferred, not required)
    - podAffinityTerm:
        labelSelector:
          matchLabels:
            app: wordpress
        topologyKey: kubernetes.io/hostname
      weight: 100

Why scheduler chose worker3 twice:
  1. Soft anti-affinity (preferredDuring) — scheduler CAN ignore it
  2. worker3 had lowest resource utilisation (61% CPU, 17% memory)
  3. Resource availability score was high enough to override anti-affinity penalty
  4. After 2 pods on worker3, anti-affinity penalty doubled → worker1 won for third pod
  5. worker2 had highest CPU (69%) — scheduler preferred less-loaded nodes


# Suspected Root Cause
Soft anti-affinity is a preference, not a requirement. Kubernetes scheduler
balanced anti-affinity penalty against resource utilisation scores. worker3's
low utilisation outweighed the anti-affinity penalty for the second pod.
This is expected scheduler behaviour, not a bug.


# More Checks Notes:
Options considered:

  Option A — Hard anti-affinity:
    requiredDuringSchedulingIgnoredDuringExecution
    Risk: if only 2 workers available, 3rd pod stays Pending forever.
    Rejected.

  Option B — Topology spread constraints:
    topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: kubernetes.io/hostname
      whenUnsatisfiable: DoNotSchedule
    Better for controlled skew with fallback behaviour.
    Not selected — current behaviour acceptable.

  Option C — Keep current config:
    Scheduler makes intelligent resource-based decisions.
    Anti-affinity is a preference, not a rule.
    Pods are on 2 different nodes — still HA.
    Selected.


# Suspected Solution
No action required — behaviour is by design.


# Test
N/A — accepted as correct behaviour.

_____________________________________________________________________

[Final Root Cause]
Soft anti-affinity (preferredDuringSchedulingIgnoredDuringExecution) allows
the scheduler to ignore the preference when resource scoring favours it.
worker3 had the lowest utilisation — scheduler's resource score outweighed
the anti-affinity penalty for the second pod. Working as designed.

_____________________________________________________________________

[Final Solution]
No action taken. Current configuration accepted.

Reasoning:
  WordPress has 2/3 pods on separate nodes — still meets HA requirement
  Scheduler optimised for resource utilisation — correct behaviour
  Hard anti-affinity risks Pending pods when workers are reduced
  Soft anti-affinity provides flexibility for resource-constrained scenarios

Acceptance criteria met:
  [x] No single point of failure (pods on multiple nodes)
  [x] Resource-efficient scheduling
  [x] No manual intervention required

If even distribution becomes critical in the future:
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app: wordpress

Verified: Yes (no action — behaviour confirmed acceptable)

_____________________________________________________________________

[Risk Level] N/A
Note: No action taken. Current soft anti-affinity behaviour is acceptable.

_____________________________________________________________________

[References]
- disaster-recovery/tmp-ipa-domain-down-part2.md

_____________________________________________________________________

[Draft Notes]

Soft vs hard anti-affinity summary:
  preferredDuring (soft)  → scheduler preference, can be overridden by resource scoring
  requiredDuring (hard)   → strict requirement, pod stays Pending if not satisfiable

Topology spread constraints are better than hard anti-affinity for even distribution
because they support maxSkew (acceptable imbalance) and fallback behaviours.