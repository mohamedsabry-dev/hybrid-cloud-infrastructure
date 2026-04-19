# Remediation — design notes and reasoning

Why this node self-healing system is shaped the way it is. Focused on the reasoning behind current design choices — not the history of how it got here. The companion [`SETUP.md`](SETUP.md) is the one-time provisioning log (firewall, Proxmox API user, Vault, K8s resources); the source of truth for behavior is [`configmap.yaml`](configmap.yaml) itself.

---

## What this system does

A single-replica Deployment running on a K8s master watches worker-node `Ready` status via the K8s API and, when a worker is NotReady, remediates it via the Proxmox API on an escalating path. Every 5 minutes, the loop does two phases:

```
Phase 1 — Check ALL worker nodes for Ready status
          Collect the unhealthy set

Phase 2 — For each unhealthy worker (sequential, independent):
            Attempt 1 → soft reboot (ACPI), or start if VM is stopped
            Attempt 2 → hard reset, or start if VM is stopped
            Attempt 3 → restore VM from latest NAS vzdump backup
                        (stop → delete → restore at same VMID → start)
                        + 120s buffer sleep to let restore complete
            Attempt 4+ → alert "exhausted, manual intervention"
          Send Alertmanager alert for each action
          On recovery: reset counter, send recovery alert
```

Nothing about pods. Nothing about masters. No clone-to-dump step. No leader election. Each of those is absent for a specific reason — explained below.

## Why this exists at all

K8s handles pod-level failure natively — crashes, OOM, liveness fail, readiness fail, scheduling and rescheduling. What K8s does NOT handle on-prem is **the VM underneath being gone** (frozen kernel, unresponsive hypervisor context, broken network from inside the VM).

Managed cloud solves this by terminating the unhealthy instance and letting the autoscaler make a new one — "cattle, not pets," no identity preserved. On-prem on Proxmox is the opposite. My worker VMs are pets:

- FreeIPA-enrolled (Kerberos principal + DNS record)
- Fixed VMID (Terraform state tracks it)
- Fixed MAC → fixed IP (DHCP reservation)
- SSH host keys (Ansible trusts them)
- K8s kubelet client cert on disk at `/var/lib/kubelet/pki/`, signed by the cluster CA, rotating via the CSR API before expiry

Destroy-and-recreate breaks all of that. The pattern has to be "same VM, heal in place." Proxmox's API is exactly the right tool: `reboot`, `reset`, `restore-from-backup` — each preserves VMID / MAC / hostname, so everything downstream (Terraform, IPA, Ansible, kubelet cert) keeps working.

**The kubelet cert is the critical piece that makes restore viable.** It's on the VM's disk, so a backup → restore cycle gives kubelet back its own cert. It reconnects to the API server automatically on first boot. No bootstrap token needed, no IPA re-enrollment, no manual join. That property is what makes "restore at same VMID" a complete recovery path instead of a partial one.

## The two-phase loop — why it looks the way it does

Phase 1 (check-all) and Phase 2 (remediate-all) are separate on purpose.

If remediation were interleaved with checking — "for each node, if unhealthy, remediate" — then a single slow remediation step blocks observation of every other node for the duration. A second failure goes silent until the first finishes. The 2-phase version observes every node every cycle and then acts, so multi-node failure is seen as multi-node failure and handled as such. 

**The direct consequence: simultaneous multi-worker failure is handled.** If 2 or 3 workers go NotReady together, every one of them gets remediated in the same cycle. Each remediation is independent — they don't interfere at the Proxmox layer. This was a deliberate design goal, confirmed in testing (worker2 + worker3 shut down simultaneously, both recovered in the same cycle).

## Decision — why 1 replica on a master

| Choice | Why |
|--------|-----|
| **1 replica, not N** | N replicas without leader election = N pods racing to reboot the same VM. Leader election is ~50 lines of state machinery (lease acquire / renew / failover) for a scenario that's self-limiting — if the single pod dies, K8s reschedules it to another master within 30s, and that window is smaller than the 5-minute check interval. Net benefit of N replicas is below the cost of building leader election. |
| **Master placement** (`nodeSelector: node-role.kubernetes.io/control-plane: ""` + master toleration) | Two reasons: (1) only the master VLAN is allowed to reach the Proxmox API on port 8006 (MikroTik ACL), so a worker pod literally can't do the job; (2) the thing healing workers shouldn't depend on workers being alive. |
| **`priorityClassName: self-healing-critical`** (1,000,000) | Sits above normal apps so it survives resource pressure from a misbehaving app; stays below the system-critical tier so it never preempts actual cluster plumbing. See priority table below. |

## Decision — why node-only checking

Earlier versions monitored both node `Ready` and pod `Ready` (with a 70% pod-failure threshold triggering remediation on the node). That heuristic false-positives during rolling deploys, during ImagePullBackOff while a registry is briefly slow, and during any app-level crash cycle unrelated to the underlying VM. Remediating a VM for a pod-level problem is worse than not remediating — it destroys a working VM to "fix" a scheduling issue K8s will fix on its own.

Current rule: **this script only handles what K8s cannot fix.** K8s can fix every pod-level problem. K8s cannot fix a frozen VM. So: node Ready status only.

```python
def is_node_healthy(v1, node_name):
    return is_node_ready(v1, node_name)
```

## Decision — why no per-action wait, just the 5-minute interval

Per-action waits (sleep N seconds after reboot / reset / restore) stack with the main loop's check interval. A 4-minute post-reboot wait + a 5-minute main-loop sleep = 9 minutes between "I just rebooted this" and "let me check again." Too slow.

Dropping the per-action waits lets the natural `CHECK_INTERVAL = 300s` cadence carry the rhythm: the remediation gets its own 5-minute window to complete, and the next check observes the result.

**Exception — 120s buffer after restore.** The Proxmox `POST /qemu` restore call returns immediately (async), but the actual restore takes ~3.5 minutes. Without a buffer, the next 5-minute check would see NotReady (because the restore is still running) and increment the counter. The buffer fires only on the one path that needs it — step 3's restore — and keeps the counter from tripping prematurely.

```python
if result == "restored":
    send_alert(node_name, "restore", "initiated", severity="critical")
    time.sleep(120)  # 2-min buffer for restore to actually complete
```

## Decision — why alerts through Alertmanager, not direct SMTP

Two plausible options:

1. Script sends email directly via SMTP — no dependency on Alertmanager being healthy.
2. Script POSTs alerts to the Alertmanager HTTP API — reuses the existing email config.

Picked option 2. Reasoning: Alertmanager runs on a master node (same class as remediation itself, by the same placement rules). Its availability domain is the same as this script's. The scenario where "remediation is alive to send, but Alertmanager is down" is narrow — almost always indicates a bigger cluster problem that a direct-SMTP path wouldn't save. Not worth duplicating SMTP config into the Python script and maintaining it in two places.

The tradeoff: if I ever need to restructure monitoring so Alertmanager is elsewhere, the alert path has to be revisited. For now, same-class placement keeps the coupling safe.

```python
ALERTMANAGER_URL = "http://alertmanager.monitoring.svc:9093/api/v2/alerts"
```

## Decision — Alertmanager on master + stateless

Because remediation alerts go to Alertmanager, and Alertmanager shouldn't be on the thing being healed, Alertmanager itself moved to master via the same `nodeSelector` + toleration. That introduced a secondary question: the NFS CSI driver DaemonSet doesn't tolerate master taints, so an Alertmanager PVC on NFS can't mount. Two options: add masters to the NFS CSI DaemonSet tolerations (widens CSI exposure), or make Alertmanager stateless.

Went stateless (`emptyDir` volume). The cost is losing silence history across restarts — acceptable for a homelab. The benefit is zero storage coupling between Alertmanager and the workers it's monitoring.

## Decision — restore at same VMID, no clone step

The restore path is: stop → delete → restore-from-backup at the same VMID → start. The VMID doesn't change, so Terraform state stays intact, IPA enrollment survives, the IP stays the same, and the kubelet cert on disk comes back intact.

I do NOT clone to a dump VMID before restoring. The clone step was attractive in principle (preserve the broken VM for forensics) but:

- Clone on large VMs is slow enough to exceed the remediation cycle and lock the source during the operation
- Proxmox's lock detection (both API and on-disk file) is unreliable enough that "wait for clone to finish" can't be done cleanly

If I want a forensic copy of a broken VM, I snapshot it manually on the Proxmox admin side before triggering remediation. That keeps the automatic path simple and reliable.

## Decision — how the Proxmox API token is handled

Credentials flow: Vault secret at `secret/remediation/config` holds `PROXMOX_HOST`, `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET`. The Vault Agent sidecar injects them at `/vault/secrets/proxmox-creds` inside the pod. The script reads that file at startup and uses it for every Proxmox API call.

This matches the same Vault injection pattern every other app in the cluster uses — see [`../../../../deployment-docs/vault-k8s-integration-guide.txt`](../../../../deployment-docs/vault-k8s-integration-guide.txt). Nothing special for remediation; it's the platform-wide pattern.

RBAC is minimal on the K8s side — read-only on nodes (see [`remediation-auth-sa.yaml`](remediation-auth-sa.yaml)):

```yaml
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
```

The pod cannot modify anything inside K8s. All mutations happen via the Proxmox API, which is outside the cluster.

## Decision — startup delay before first check

The script waits `CHECK_INTERVAL` (300s / 5 min) before its first health check:

```python
# Startup delay: wait before first health check to avoid race during cluster boot
time.sleep(CHECK_INTERVAL)
```

Why: during a cold cluster boot, nodes flap between NotReady and Ready as kubelet + CNI + DNS come up in their own order. The pod itself may start before kubelet finishes reporting Ready on all nodes. Without the delay, the very first health check could observe "worker3 NotReady" and trigger a reboot on a node that's actually 30 seconds away from finishing boot.

The 5-minute startup delay gives the cluster time to reach a stable baseline before the script starts making decisions.

## Decision — ConfigMap version annotation

K8s doesn't restart pods when a mounted ConfigMap changes. If I update `configmap.yaml`, Flux applies the ConfigMap but the running pod keeps its old copy in memory. To force a rollout when the script changes, there's a `config-version` annotation on the Deployment pod template — bumping it triggers a new pod.

```yaml
spec:
  template:
    metadata:
      annotations:
        config-version: "N"   # bump on ConfigMap change
```

Not elegant, but it's the standard K8s pattern for this.

## Priority class hierarchy

```
system-node-critical        (2000001000)   etcd, kube-apiserver, calico-node
system-cluster-critical     (2000000000)   coredns, ingress, flux, csi
self-healing-critical       (1000000)      remediation pod + alertmanager
database-critical           (1000000)      mariadb
app-standard                (500000)       wordpress
```

[`priorityclass.yaml`](priorityclass.yaml) defines `self-healing-critical`. If the cluster is under enough resource pressure that system-critical pods are being evicted, remediation can't help anyway — the API server itself is unhappy. So preempting anything above self-healing would be pointless. The ordering is right where it needs to be.

## Production vs homelab — the "cattle vs pets" frame

In managed cloud:
- Node unhealthy → autoscaler terminates instance
- New instance boots from user-data template
- Bootstrap token joins the new instance
- ~3-5 minutes end-to-end, zero identity preserved

CAPI on-prem does the same with VM templates, but running CAPI adds 3-4 controller pods and the bootstrap-token flow conflicts with my IPA enrollment story (every "new" VM needs to be re-enrolled in IPA, re-registered in DNS, re-added to Ansible inventory). For a 3-worker homelab it's pure ceremony.

Restore-at-same-VMID avoids all of that. VMID, MAC, IP, IPA enrollment, SSH host keys, kubelet cert — all preserved. Recovery time is comparable (~5 min) with much less moving infrastructure. It's the right tradeoff for this scale.

## What's not in scope

Things explicitly NOT handled by this system, with the reasoning:

- **Master node failure.** Not automated. Masters run control-plane components, not workloads, and fail rarely in practice. Automating master recovery introduces etcd quorum / member rejoin / split-brain risk without meaningful operational benefit. If a master dies, I SSH in and fix it by hand.
- **Pod-level self-healing.** Explicitly K8s' job. The script only covers what K8s cannot fix.
- **External cluster-API-unreachable detection.** A cross-cloud tripwire (e.g., CloudWatch Synthetics + SNS pinging the cluster API from AWS) would catch the "everything is down" case. Not built — that case manifests obviously via other channels (monitoring dashboards stop, Flux reconciles stop, apps unreachable externally).
- **Post-recovery workload rebalancing.** When a worker comes back from restore, existing pods stay on whichever workers picked them up during the outage. Scheduler only makes placement decisions for NEW pods. Manual fix: `kubectl rollout restart deployment <name>`. Automatic fix would be deploying Descheduler — on the future list, not done.

## Current limitations (honest)

1. **Proxmox API token has Administrator role.** Planned scope-down to `VM.PowerMgmt` + `VM.Backup` + `VM.Audit` on specific worker VMIDs only. Not yet done.
2. **Counter is per-node and per-process — it doesn't persist.** If the remediation pod restarts mid-incident, the counter resets to 0 and the next action starts at "reboot" again regardless of where the last pod left off. For the normal 5-min cycle this doesn't matter; for a pathological "pod keeps crashing during a remediation" scenario it could cause re-escalation oddity. Acceptable tradeoff vs. adding a PVC + state reconciliation.
3. **Counter reset requires node recovery.** If a node remains unhealthy past attempt 3, the script keeps logging "max attempts reached" every cycle but doesn't take further action. Human has to intervene (fix the VM / node) and let it go Ready for the counter to reset.
4. **No `/metrics` endpoint.** Remediation events are observable via Alertmanager alerts and pod logs, not as Prometheus metrics. Would make Grafana dashboards on remediation history easy — deferred.

## Testing

Full recovery cycle validated 2026-04-17. Shut down worker2 and worker3 manually, both went NotReady. The script observed both in the same Phase 1, remediated both in Phase 2 (worker2 got its reboot path, worker3 progressed through to restore on a later attempt), both recovered in subsequent cycles, counters reset, recovery alerts fired. Observed restore-path timing: Proxmox API call instant (async), actual restore ~3.5 min, VM boot + kubelet rejoin ~1–2 min, total ~5 min.

DR test writeups live in the main `disaster-recovery/` folder; worker-loss DR tests that exercise this system are tracked there.

---

## Related files

### In this folder
- [`README.md`](README.md) — short orientation pointing at this file + SETUP
- [`SETUP.md`](SETUP.md) — one-time provisioning log (firewall, Proxmox user/token, Vault, K8s resources)
- [`configmap.yaml`](configmap.yaml) — the Python remediation script (canonical source of truth)
- [`deployment.yaml`](deployment.yaml) — Deployment spec with master placement + Vault annotations
- [`priorityclass.yaml`](priorityclass.yaml) — `self-healing-critical` priority class
- [`remediation-auth-sa.yaml`](remediation-auth-sa.yaml) — ServiceAccount + read-only ClusterRole on nodes
- [`namespace.yaml`](namespace.yaml) — `remediation` namespace
- [`vault-ca-secret.yaml`](vault-ca-secret.yaml) — IPA CA cert for Vault TLS trust

### Elsewhere in the repo
- [`../../../../docker-images/remediation/`](../../../../docker-images/remediation/) — Dockerfile with debugging tools, image used by the Deployment
- [`../monitoring/`](../monitoring/) — Prometheus + Alertmanager stack that receives alerts from this system
- [`../../../../deployment-docs/vault-k8s-integration-guide.txt`](../../../../deployment-docs/vault-k8s-integration-guide.txt) — Vault injection pattern used by this Deployment
- [`../../../../disaster-recovery/README.md`](../../../../disaster-recovery/README.md) — DR hub
- [`../../../../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md`](../../../../troubleshooting/kubernetes/17-vault-injection-system-namespace-denied.md) — the TS case that drove the dedicated `remediation` namespace
