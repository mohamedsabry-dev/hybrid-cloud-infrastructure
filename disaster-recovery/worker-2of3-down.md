DR Test: Partial Worker Loss (2 of 3) + Total Worker Loss
Date: 2026-04-18
Result: PASS + 2 CRITICAL ISSUES FOUND
_____________________________________________________________________

[Info]
Domain: Kubernetes / Worker Nodes / Remediation / Pod Eviction / DNS
Environment: DEV — 3 masters + 3 workers, v1.35.3
Triggered by: Need to test worker loss — does the cluster reschedule
  workloads, does remediation auto-recover, what breaks?

_____________________________________________________________________

[Planned Scope]

Test 1: Force shutdown 2 of 3 workers (worker1 + worker2). Observe
failover to surviving worker3 and resource pressure.

Test 2: Escalate — shutdown master3 (kills remediation pod) + all 3
workers. No auto-recovery possible. Observe pod eviction, DNS
dependency chain, and manual recovery path.

_____________________________________________________________________

[Pre-State]

All 6 nodes Ready. Key placement:
  worker1: WordPress, Flux controllers, ingress-nginx, kube-state-metrics
  worker2: MariaDB, Grafana, Loki
  worker3: WordPress, Prometheus, ingress-nginx, csi-nfs-controller
  master3: remediation pod, vault-agent-injector, CoreDNS
  Memory: worker1 65%, worker2 67%, worker3 75% (~5.9GB combined)

_____________________________________________________________________

[Test 1.1 — Shutdown worker1 + worker2]

Action:
  ```
  qm stop 1020 --skiplock    # worker1
  qm stop 1021 --skiplock    # worker2
  ```

What happened:
  WordPress down (MariaDB on worker2 unreachable). Grafana 503.
  MariaDB, Grafana, Loki all need rescheduling from dead workers.

  But remediation system triggered at ~4 minutes — detected stopped
  VMs, auto-started both workers before pod eviction timeout (5 min
  default). Workers came back, pods restarted on original nodes.
  Full alert loop worked: reboot alerts → recovery alerts → Slack.

  ```
  [Attempt 1] Remediating k8s-worker1.lab.local (VM 1020)
    -> VM 1020 is stopped, starting instead of rebooting
  [Attempt 1] Remediating k8s-worker2.lab.local (VM 1021)
    -> VM 1021 is stopped, starting instead of rebooting
  ```

  Total downtime: ~4 minutes. No rescheduling occurred — VMs recovered
  before eviction timeout. Pods restarted in place.

What this tells me:
  Remediation works as designed — detects and recovers stopped VMs
  faster than the eviction timeout. But this means I couldn't test
  the rescheduling path. Need to disable remediation for that test.

_____________________________________________________________________

[Test 2.1 — Total worker loss + master3 (no remediation)]

Why this test: kill remediation first, then all workers. No auto-recovery.

Action:
  ```
  qm stop 1012    # master3 (remediation pod lives here)
  qm stop 1020    # worker1
  qm stop 1021    # worker2
  qm stop 1022    # worker3
  ```
  Surviving: master1 + master2 (etcd 2/3 quorum intact, API server works).

What happened:

  CRITICAL FINDING 1 — Taints are NoSchedule, not NoExecute:
  Nodes got `node.kubernetes.io/unreachable:NoSchedule` instead of
  `NoExecute`. This means pods on dead nodes are never evicted — they
  stay "Running" (stale status) forever. NoSchedule only prevents new
  scheduling, it doesn't evict existing pods. Manual NoExecute taint
  also didn't work (reason unknown, needs investigation).

  CRITICAL FINDING 2 — Single-replica deployments don't failover:
  vault-agent-injector (replicas=2): immediately created new pod on
  healthy node. remediation (replicas=1): no new pod created. With
  replicas=1, ReplicaSet sees "1/1 pods exist" and does nothing —
  it doesn't know the pod is unreachable.

  Same problem affects: remediation, alertmanager, mariadb, loki,
  prometheus, grafana — all single replica.

  DNS dependency chain failure:
  After force-deleting stuck remediation pod, new pod scheduled on
  master2 but vault-agent-init failed:
  ```
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: connection refused
  ```
  Both CoreDNS pods were on dead nodes (worker1 + master3). No DNS →
  remediation can't authenticate to Vault → can't start → can't heal
  the cluster. Self-healing system can't heal itself.

Cascade:
  master3 + all workers down → remediation pod on dead node → force
  delete → new pod → needs Vault auth → needs DNS → CoreDNS on dead
  nodes → COMPLETE FAILURE — manual intervention required

What this tells me:
  Three critical gaps: (1) NoExecute taint not applied automatically,
  (2) single-replica services don't failover, (3) CoreDNS placement
  can leave DNS dead during the exact scenario where you need it most.

_____________________________________________________________________

[Recovery — Test 2]

  Step 1 (manual): start master3 for CoreDNS
  ```
  qm start 1012
  ```
  Step 2 (manual): delete stuck remediation pod
  Step 3 (automatic): new remediation pod on master2, vault-agent-init
  succeeded (DNS now working), remediation started all 3 workers
  Step 4 (automatic): all nodes Ready, alerts confirmed recovery

  | Step                   | Type      | Time     |
  |------------------------|-----------|----------|
  | Start master3          | Manual    | ~1 min   |
  | Delete stuck pod       | Manual    | ~5 sec   |
  | Remediation starts     | Automatic | ~30 sec  |
  | Workers recovered      | Automatic | ~2-3 min |
  | Total                  |           | ~5 min   |

  Key insight: with DNS available and remediation restarted, automatic
  recovery worked. DNS was the only bottleneck.

_____________________________________________________________________

[Test 2.2 — Re-run with fixes]

Why this test: validate that fixing DNS placement + manual NoExecute
  taint resolves the failures.

Action:
  Same shutdown (master3 + all workers). CoreDNS had one pod on
  master1 (survived). Manual NoExecute taint added to master3.

What happened:
  Eviction worked — remediation pod on master3 evicted and rescheduled
  to master2. vault-agent-init succeeded (CoreDNS on master1 answered).
  Remediation started, recovered all workers. Cluster fully healed.

  ```
  TaintManagerEviction    Marking for deletion Pod remediation-774679955-94vmb
  SuccessfulCreate        Created pod: remediation-774679955-mlgxs
  Scheduled               Successfully assigned to k8s-master2.lab.local
  ```

  Note: qemu-ga CPU spike occurred on master1/master2 during test
  (self-recovered in 2-8 min, didn't block remediation).
  See TS-K8S-038.

_____________________________________________________________________

[Findings]

1. Remediation auto-recovery works — detects stopped VMs in ~4 minutes,
   starts them before pod eviction timeout. Full alert loop (reboot →
   recovery → Slack) validated. But this speed means pod rescheduling
   never gets tested organically.

2. CRITICAL: NoExecute taint not applied automatically. Nodes get
   NoSchedule instead of NoExecute when unreachable. Pods never evict
   from dead nodes. Manual NoExecute works but automatic doesn't —
   needs kube-controller-manager investigation.
   See: troubleshooting/kubernetes/43-noexecute-taint-not-applied.md

3. CRITICAL: Single-replica deployments don't failover. ReplicaSet
   sees "1/1 pods exist" and takes no action even if the pod is on a
   dead node. Only works with replicas≥2 (vault-agent-injector proved
   this). Affects: remediation, alertmanager, grafana, mariadb, loki,
   prometheus.

4. CoreDNS placement is a hidden SPOF. Both replicas can land on nodes
   that fail together. When DNS dies, everything dies — including the
   remediation system that's supposed to fix things. Fix: force CoreDNS
   onto control-plane nodes or add topologySpreadConstraints.
   See: troubleshooting/kubernetes/44-coredns-ha-masters.md

5. Self-healing systems must not depend on components that can fail in
   the same scenario they're trying to heal. Remediation → Vault → DNS
   → CoreDNS on dead nodes = circular dependency under failure.

_____________________________________________________________________

[References]

- troubleshooting/kubernetes/43-noexecute-taint-not-applied.md
- troubleshooting/kubernetes/44-coredns-ha-masters.md
- troubleshooting/kubernetes/38-qemu-guest-agent-cpu-loop.md
- master-2of3-down.md — DNS SPOF from control plane side
- network-ipa-dns-outage.md — DNS SPOF via IPA
