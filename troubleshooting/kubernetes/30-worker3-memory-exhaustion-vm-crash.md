# TS-K8S-030 | 2026-04-14 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Proxmox
Sub-techs: Worker node memory exhaustion, VM crash, Prometheus memory, no swap,
           Terraform rolling update, remediation pod, OOM, Proxmox task log
Environment: DEV k8s-dev cluster | k8s-worker3 (VM 1022)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Worker3 VM crashed twice in ~2 hours, found in "stopped" state each time.
Pods rescheduled, MariaDB failover, brief service disruption.
Proxmox task log: Error: VM quit/powerdown fa...

Timeline:
  Apr 13 22:26:25  Remediation detected worker3 NotReady, VM status: stopped
  Apr 13 22:26:25  Remediation started VM 1022
  Apr 13 22:35:27  Worker3 recovered
  Apr 14 00:12:15  Second crash — "VM quit/powerdown fa..."
  Apr 14 00:26:27  VM started again

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

Check 1 — Remediation pod logs:
  kubectl logs -n remediation -l app=remediation --tail=100

  Output:
  --- Health check at 2026-04-13 22:26:25 ---
  k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)
  [Attempt 1] Remediating k8s-worker3.lab.local (VM 1022)
    -> VM 1022 status: stopped   ← VM crashed, not just node NotReady
    -> VM 1022 is stopped, starting instead of rebooting
    -> Starting VM 1022
    -> Waiting 240s for recovery...
  --- Health check at 2026-04-13 22:35:27 ---
  k8s-worker3.lab.local: Recovered!

Check 2 — Memory state after recovery:
  ssh root@k8s-worker3 'free -h'
  Output:
    Mem:   total 2.4Gi   used 1.8Gi   free 88Mi   available 607Mi
    Swap:  0B  ← no swap configured

  Memory extremely tight. No swap = no safety buffer.

Check 3 — Top memory consumers:
  ssh root@k8s-worker3 'ps aux --sort=-%mem | head -10'
  Output:
    prometheus   691MB  27.4%  ← PRIMARY CONSUMER
    grafana      174MB   6.9%
    python x2    157MB   6.1%  (sidecars)
    kubelet       69MB   2.7%
    calico-node   67MB   2.6%
    containerd    56MB   2.2%
    promtail      54MB   2.1%
  Total major processes: ~1.3GB on 2.4GB = very tight, no headroom for spikes.

Check 4 — OOM killer evidence:
  ssh root@k8s-worker3 'dmesg | grep -i "oom\|killed"'
  Output: empty — no OOM kills logged.

  Why no OOM evidence:
    No swap = kernel cannot page out memory.
    Memory exhaustion happens too fast for OOM killer to activate.
    VM crashes at hypervisor level before kernel intervention.
    Death happens at Proxmox/QEMU level, not at Linux kernel level.

Check 5 — Kubelet logs:
  journalctl -u kubelet --since "2 hours ago" | grep -i "error\|fail\|memory"
  Output: empty — no errors (kubelet not running during crash).

Check 6 — Proxmox task log:
  Apr 14 00:26:27  VM 1022 - Start    OK
  Apr 14 00:12:15  VM 1022 - Reboot   Error: VM quit/powerdown fa...  ← crash
  Apr 13 22:56:55  VM 1022 - Start    OK
  Apr 13 22:56:23  VM 1022 - Reboot   OK

  "VM quit/powerdown fa..." = VM crashed unexpectedly at hypervisor level.

Estimated memory before crash (suspected load):
  Prometheus    ~700MB
  MariaDB       ~200-400MB  (was on worker3 before crash)
  Grafana       ~175MB
  Sidecars/kubelet/calico/promtail  ~400MB
  Total estimated: 1.5-1.7GB on 2.4GB = 60-70% base usage
  With query spikes → easily hits 90%+ → crash.


# Suspected Root Cause
Worker3 VM configured with only 2.75GB (2816MB) memory, running memory-heavy
workloads (Prometheus + MariaDB + Grafana simultaneously). No swap configured.
Memory exhaustion causes instant VM crash at hypervisor level with no OOM warning.


# More Checks Notes:
Node conditions after recovery showed MemoryPressure: False — no historical
evidence preserved in K8s. Proxmox UI showed 96% host memory utilisation.
Host pressure likely contributing factor.


# Suspected Solution
Increase worker VM memory via Terraform. Reduce Vault LXC memory to compensate
on Proxmox host. Add swap to workers as safety buffer.


# Test
Applied Terraform memory changes to all 3 workers.

⚠ INCIDENT DURING FIX (2026-04-14 03:07):
  Terraform applied changes to all 3 workers simultaneously → parallel reboots:
    Apr 14 03:07:06  VM 1020 - Reboot  (worker1)
    Apr 14 03:07:06  VM 1021 - Reboot  (worker2)
    Apr 14 03:07:11  VM 1022 - Reboot  (worker3)
    Apr 14 03:07:14  VM 1021 - Start
    Apr 14 03:07:21  VM 1020 - Start
    Apr 14 03:07:21  VM 1022 - Start

  Result: ~30 seconds complete cluster downtime (all workers down simultaneously).

  Correct approach — always apply one VM at a time:
    terraform apply -target=proxmox_virtual_environment_vm.k8s_worker1
    kubectl wait --for=condition=Ready node/k8s-worker1.lab.local --timeout=120s
    terraform apply -target=proxmox_virtual_environment_vm.k8s_worker2
    kubectl wait --for=condition=Ready node/k8s-worker2.lab.local --timeout=120s
    terraform apply -target=proxmox_virtual_environment_vm.k8s_worker3

  Same rule applies to: Vault LXCs (maintain Raft quorum), K8s masters (etcd quorum),
  any HA cluster components.

Result: PASS (after all workers restarted) — all workers at 3.25GB, no crashes
in monitoring window.

_____________________________________________________________________

[Final Root Cause]
Worker3 VM had only 2.75GB memory running Prometheus (~700MB), MariaDB, Grafana,
and system processes simultaneously. No swap configured — when memory is exhausted,
the kernel cannot page out and the VM crashes at hypervisor level before the Linux
OOM killer can activate. No OOM evidence in dmesg. Crash appears only in Proxmox
task log as "VM quit/powerdown fa...".

_____________________________________________________________________

[Final Solution]

Increased worker VM memory in Terraform:
  terraform/dev/proxmox/vms/k8s_workers/variables.tf:
    memory = 2816  → memory = 3328  (2.75GB → 3.25GB, +512MB, all 3 workers)

Reduced Vault LXC memory to free Proxmox host memory:
  vault LXCs: 768MB → 512MB

Applied changes one worker at a time using -target to avoid cluster-wide downtime:
  terraform apply -target=proxmox_virtual_environment_vm.k8s_worker1
  kubectl wait --for=condition=Ready node/k8s-worker1.lab.local --timeout=120s
  (repeat for worker2, worker3)

Future considerations:
  [ ] Add 1-2GB swap to worker VMs as safety buffer against spike crashes
  [ ] Set memory limits on Prometheus and Grafana pods
  [ ] Monitor Proxmox host memory — not just VM memory
  [ ] Spread heavy workloads — avoid stacking Prometheus + MariaDB + Grafana on same node

Verified: Yes

_____________________________________________________________________

[Risk Level] MEDIUM (during apply — VM restart required)
Note: Memory still relatively tight at 3.25GB. Monitor over 24-48 hours.
Vault LXC reduction accepted — Vault operates fine at 512MB.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Evidence summary:
  VM status              stopped                   crashed, not just unhealthy
  OOM in dmesg           empty                     no kernel OOM (no swap)
  Proxmox task log       VM quit/powerdown fa...   hypervisor-level crash
  Memory usage           2.4GB total, 1.8GB used   tight, no headroom
  Prometheus             691MB (27%)               primary memory consumer
  Swap                   0B                        no safety buffer

Notes:
  1. No swap = dangerous — instant crash with no warning, no OOM evidence
  2. OOM logs don't appear when VM crashes at hypervisor level
  3. Remediation pod worked correctly — detected and recovered node automatically
  4. Prometheus is heavy — 700MB for a small dev cluster is significant
  5. terraform apply reboots ALL VMs at once — causes cluster-wide downtime
  6. ALWAYS use -target for rolling VM changes — one VM/LXC at a time
  7. Same quorum rule for Vault LXCs and K8s masters — never restart all at once

Commands reference:
  grep -A5 "memory" terraform/dev/proxmox/vms/k8s_workers/variables.tf
  ssh root@k8s-worker3 'free -h'
  ssh root@k8s-worker3 'ps aux --sort=-%mem | head -10'
  ssh root@pve-dev 'qm config 1022 | grep memory'
  kubectl logs -n remediation -l app=remediation --tail=100
  kubectl describe node k8s-worker3.lab.local | grep -A10 "Conditions:"

Workaround if crash recurs before Terraform apply:
  # Move Prometheus off the saturated node
  kubectl patch deployment prometheus -n monitoring \
    -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-worker1.lab.local"}}}}}'

  # Or scale down non-critical pods temporarily
  kubectl scale deployment grafana -n monitoring --replicas=1