# TS-K8S-030 | 2026-04-14 | RESOLVED

## 1. Context

- System: Kubernetes Worker Node / Proxmox VM / Memory Management
- Environment: DEV (k8s-worker3.lab.local, VM 1022)
- Related components: Prometheus, MariaDB, Grafana, Remediation Pod
- Discovered during: Routine monitoring, remediation pod alerts

## 2. Issue

- Symptom: Worker3 VM crashed twice in ~2 hours, found in "stopped" state
- Impact: Pods rescheduled, MariaDB failover, brief service disruption
- Error: Proxmox task log shows `Error: VM quit/powerdown fa...` (VM crashed)

**Timeline:**
| Time | Event |
|------|-------|
| Apr 13 22:26:25 | Remediation detected worker3 NotReady, VM status: stopped |
| Apr 13 22:26:25 | Remediation started VM 1022 |
| Apr 13 22:35:27 | Worker3 recovered |
| Apr 14 00:12:15 | Second crash - "VM quit/powerdown fa..." |
| Apr 14 00:26:27 | VM started again |

## 3. Analysis

### Check 1: Remediation Pod Logs

```bash
kubectl logs -n remediation -l app=remediation --tail=100
```

```
--- Health check at 2026-04-13 22:26:25 ---
k8s-worker1.lab.local: Healthy
k8s-worker2.lab.local: Healthy
k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)
[Attempt 1] Remediating k8s-worker3.lab.local (VM 1022)
  -> VM 1022 status: stopped
  -> VM 1022 is stopped, starting instead of rebooting
  -> Starting VM 1022
  -> Waiting 240s for recovery...

--- Health check at 2026-04-13 22:35:27 ---
k8s-worker3.lab.local: Recovered! Resetting counter.
```

**Key finding:** VM was `stopped` - not just node NotReady. VM crashed.

### Check 2: Current Memory State (after recovery)

```bash
ssh root@k8s-worker3 'free -h'
```

```
               total        used        free      shared  buff/cache   available
Mem:           2.4Gi       1.8Gi        88Mi        18Mi       686Mi       607Mi
Swap:             0B          0B          0B
```

**Key finding:** No swap configured. Memory exhaustion = instant crash (no graceful OOM).

### Check 3: Top Memory Consumers

```bash
ssh root@k8s-worker3 'ps aux --sort=-%mem | head -10'
```

```
USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
gandalf     4503  3.7 27.4 4679392 691832 ?      Ssl  00:27   5:32 /bin/prometheus ...
472         4764  0.4  6.9 1769288 174568 ?      Ssl  00:28   0:38 grafana server ...
472         4695  0.1  3.1 105028 79140 ?        Ssl  00:28   0:10 python -u -m sidecar
472         4734  0.0  3.0 103284 77588 ?        Ssl  00:28   0:05 python -u -m sidecar
root        1824  1.3  2.7 2406120 69424 ?       Ssl  00:26   2:05 /usr/bin/kubelet ...
root        2755  0.7  2.6 2049828 67532 ?       Sl   00:27   1:05 calico-node -felix
```

**Memory breakdown (current state, after MariaDB moved):**
| Process | RSS | %MEM |
|---------|-----|------|
| Prometheus | 691MB | 27.4% |
| Grafana | 174MB | 6.9% |
| Python sidecars (2x) | 157MB | 6.1% |
| kubelet | 69MB | 2.7% |
| calico-node | 67MB | 2.6% |
| containerd | 56MB | 2.2% |
| promtail | 54MB | 2.1% |

**Total major processes:** ~1.3GB on 2.4GB available = very tight

### Check 4: OOM Killer Evidence

```bash
ssh root@k8s-worker3 'dmesg | grep -i "oom\|killed"'
```

```
(empty - no output)
```

**Key finding:** No OOM kills logged. This is because:
- No swap = kernel cannot page out, instant memory exhaustion
- VM crashes before Linux OOM killer activates
- Death happens at hypervisor level, not kernel level

### Check 5: Kubelet Logs

```bash
ssh root@k8s-worker3 'journalctl -u kubelet --since "2 hours ago" | grep -i "error\|fail\|memory"'
```

```
(empty - no errors)
```

### Check 6: Node Conditions

```bash
kubectl describe node k8s-worker3.lab.local | grep -A 10 "Conditions:"
```

```
Conditions:
  Type                 Status  LastHeartbeatTime                 LastTransitionTime                Reason                       Message
  MemoryPressure       False   Tue, 14 Apr 2026 02:55:30 +0200   Tue, 14 Apr 2026 00:26:58 +0200   KubeletHasSufficientMemory   kubelet has sufficient memory available
  DiskPressure         False   ...
  Ready                True    ...
```

**Key finding:** After recovery, node shows healthy. No historical evidence preserved.

### Check 7: Proxmox Task Log

```
Apr 14 00:26:27  VM 1022 - Start                    OK
Apr 14 00:12:15  VM 1022 - Reboot                   Error: VM quit/powerdown fa...
Apr 13 22:56:55  VM 1022 - Start                    OK
Apr 13 22:56:23  VM 1022 - Reboot                   OK
```

**Key finding:** `VM quit/powerdown fa...` = VM crashed unexpectedly at Proxmox level.

### Check 8: Pod Distribution Before Crash (suspected)

Before crash, worker3 likely had:
- Prometheus (~700MB)
- MariaDB (~200-400MB)
- Grafana (~175MB)
- Sidecars, kubelet, calico, promtail (~400MB)

**Total estimated:** 1.5-1.7GB on 2.4GB = 60-70% usage

With memory spikes (queries, writes), easily hits 90%+ → crash.

## 4. Root Cause

**Primary:** Worker3 VM configured with only 2.75GB (2816MB) memory, running memory-heavy workloads (Prometheus + MariaDB + Grafana).

**Contributing factors:**
1. No swap configured on worker VMs
2. Prometheus retention/queries consuming 691MB+
3. MariaDB was on same node before crash
4. No memory limits enforced on some pods
5. Proxmox ballooning or host pressure (observed 96% in Proxmox UI)

**Why no OOM evidence:**
- Without swap, Linux cannot page out memory
- Memory exhaustion happens too fast for OOM killer
- VM crashes at hypervisor level before kernel intervention

## 5. Solution

### Fix Applied: Increase Worker Memory

**File:** `terraform/dev/proxmox/vms/k8s_workers/variables.tf`

```hcl
# BEFORE
memory         = 2816  # 2.75GB

# AFTER
memory         = 3328  # 3.25GB
```

**Applied to:** All 3 workers (worker1, worker2, worker3)

**Additional change made:** Vault LXCs reduced 768 → 512MB to free Proxmox host memory.

### Deployment

```bash
cd terraform/dev/proxmox/vms/k8s_workers
terraform plan
terraform apply
# Requires VM restart to take effect
```

### ⚠️ CRITICAL: Apply Changes One VM/LXC at a Time

**Incident during fix (2026-04-14 03:07):**

Terraform applied memory changes to all 3 workers simultaneously, triggering parallel reboots:

```
Apr 14 03:07:06  VM 1020 - Reboot   (worker1)
Apr 14 03:07:06  VM 1021 - Reboot   (worker2)
Apr 14 03:07:11  VM 1022 - Reboot   (worker3)
Apr 14 03:07:14  VM 1021 - Start
Apr 14 03:07:21  VM 1020 - Start
Apr 14 03:07:21  VM 1022 - Start
```

**Result:** ~30 seconds complete cluster downtime (all workers down simultaneously).

**Correct approach for production-safe changes:**

```bash
# Option 1: Target specific resources one at a time
terraform apply -target=proxmox_virtual_environment_vm.k8s_worker1
# Wait for worker1 to be Ready
kubectl wait --for=condition=Ready node/k8s-worker1.lab.local --timeout=120s

terraform apply -target=proxmox_virtual_environment_vm.k8s_worker2
# Wait for worker2 to be Ready
kubectl wait --for=condition=Ready node/k8s-worker2.lab.local --timeout=120s

terraform apply -target=proxmox_virtual_environment_vm.k8s_worker3
# Wait for worker3 to be Ready

# Option 2: Manual rolling restart via Proxmox
# Apply Terraform without reboot, then manually restart one at a time
```

**Same applies to:**
- Vault LXCs (2004, 2005, 2006) - must maintain quorum during changes
- K8s Masters - must maintain etcd quorum
- Any HA cluster components

### Future Considerations

1. **Add swap** to worker VMs (1-2GB) as safety buffer
2. **Set memory limits** on Prometheus, Grafana pods
3. **Monitor Proxmox host** memory, not just VM memory
4. **Spread workloads** - avoid stacking heavy pods on same node

## 6. Solution Risk

| Risk | Level | Mitigation |
|------|-------|------------|
| VM restart required | Medium | Schedule during maintenance window |
| Memory still tight | Low | 3.25GB gives ~500MB more headroom |
| Proxmox host memory | Low | Reduced Vault LXCs to compensate |

## 7. Impact After Fix

- [x] Terraform applied (2026-04-14 03:07)
- [x] All workers now have 3.25GB memory
- [x] All Vault LXCs now have 512MB memory
- [ ] Monitor: Check memory usage over 24-48 hours

**Unintended impact:** All 3 workers rebooted simultaneously → 30s downtime.
**Lesson:** Use `terraform apply -target=<resource>` for rolling updates.

## 8. Notes

### Lessons Learned

1. **No swap = dangerous** - instant crash without warning
2. **OOM logs don't appear** when VM crashes at hypervisor level
3. **Remediation pod worked** - detected and recovered the node automatically
4. **Prometheus is heavy** - 700MB for a small dev cluster is significant
5. **⚠️ Terraform apply reboots ALL VMs at once** - causes cluster-wide downtime
6. **Always use `-target` for rolling changes** - one VM/LXC at a time
7. **Same rule for Vault/Masters** - maintain quorum during changes

### Related Commands

```bash
# Check VM memory in Terraform
grep -A5 "memory" terraform/dev/proxmox/vms/k8s_workers/variables.tf

# Check current node memory
ssh root@k8s-worker3 'free -h'

# Top memory processes
ssh root@k8s-worker3 'ps aux --sort=-%mem | head -10'

# Check Proxmox VM config
ssh root@pve-dev 'qm config 1022 | grep memory'

# Remediation logs
kubectl logs -n remediation -l app=remediation --tail=100
```

### Evidence Summary

| Check | Result | Conclusion |
|-------|--------|------------|
| VM status | stopped | Crashed, not just unhealthy |
| OOM in dmesg | empty | No kernel OOM (no swap) |
| Proxmox task | "VM quit/powerdown" | Hypervisor-level crash |
| Memory usage | 2.4GB total, ~1.8GB used | Very tight, no headroom |
| Prometheus | 691MB (27%) | Primary memory consumer |
| Swap | 0B | No safety buffer |

## 9. Workaround

If crash recurs before Terraform apply:

1. Move Prometheus to different worker:
```bash
kubectl patch deployment prometheus -n monitoring -p '{"spec":{"template":{"spec":{"nodeSelector":{"kubernetes.io/hostname":"k8s-worker1.lab.local"}}}}}'
```

2. Or scale down non-critical pods temporarily:
```bash
kubectl scale deployment grafana -n monitoring --replicas=1
```
