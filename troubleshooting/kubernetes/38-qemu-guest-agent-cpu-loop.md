# Issue: QEMU Guest Agent CPU Busy Loop

**Status:** OPEN (Workaround applied, root cause not fully identified)
**Date Discovered:** 2026-04-17
**Affected Node:** k8s-master3.lab.local
**Severity:** High (node CPU maxed out)

---

## Summary

QEMU Guest Agent (`qemu-ga`) entered a busy loop consuming 98% CPU on k8s-master3, even though no operations were performed on that node. The issue was discovered during remediation testing on k8s-worker3.

---

## Symptoms

```bash
top - 00:01:12 up 13:22,  2 users,  load average: 2.49, 2.33, 2.27
%Cpu(s): 16.1 us, 39.8 sy,  0.0 ni, 41.9 id,  0.3 wa,  1.2 hi,  0.5 si,  0.2 st

  PID USER   PR  NI  VIRT   RES   SHR S  %CPU  %MEM     TIME+ COMMAND
  970 root   20   0 97312   960   628 R  98.7   0.0  88:54.12 qemu-ga
```

- `qemu-ga` process at 98.7% CPU
- High system CPU (39.8% sy)
- Load average elevated (2.49)
- Node showed 57% CPU in `kubectl top node`

---

## Investigation

### strace Output

```bash
strace -p 970
```

```
write(4, "\377{\"return\": 35553302}\n", 22) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "\377{\"return\": 35553302}\n", 22) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "\377{\"return\": 35553302}\n", 22) = -1 EAGAIN (Resource temporarily unavailable)
... (repeating infinitely)
```

### Analysis

1. **File descriptor 4** = virtio-serial channel to Proxmox host
2. **EAGAIN** = Write buffer is full, operation would block
3. **No sleep/backoff** = qemu-ga immediately retries
4. **Result** = Infinite busy loop at 100% CPU

### Diagram

```
┌─────────────────┐         virtio-serial         ┌─────────────────┐
│   VM (guest)    │  ←───── channel buffer ─────→ │  Proxmox (host) │
│   qemu-ga       │         (FULL/STUCK)          │   not reading   │
└─────────────────┘                               └─────────────────┘
         │
         ▼
    write() → EAGAIN
         │
         ▼
    retry immediately (no sleep)
         │
         ▼
    100% CPU busy loop
```

---

## Root Cause

### What We Know
- virtio-serial channel between VM and Proxmox was stuck/full
- Proxmox side was not reading from the channel
- qemu-ga has no backoff logic when write fails

### What We Don't Know (OPEN QUESTION)
- **Why did this happen on master3?** We were testing clone/restore on worker3
- **Possible theories:**
  1. Proxmox-wide channel issue affecting multiple VMs
  2. Coincidental timing - unrelated backup job on master3
  3. Proxmox host resource exhaustion during clone operation
  4. Bug in Proxmox 8.x qemu-guest-agent handling

### Bug Location
The bug is in `qemu-ga` code - it should implement exponential backoff when `write()` returns `EAGAIN`:

**Current (buggy):**
```c
while (write(fd, buf, len) == -1 && errno == EAGAIN) {
    // Immediate retry - busy loop!
}
```

**Should be:**
```c
int backoff_ms = 10;
while (write(fd, buf, len) == -1 && errno == EAGAIN) {
    usleep(backoff_ms * 1000);
    backoff_ms = min(backoff_ms * 2, 1000);  // Exponential backoff, max 1s
}
```

---

## Workaround

```bash
# On affected node
systemctl restart qemu-guest-agent
```

This:
1. Kills the stuck process
2. Reconnects virtio-serial channel
3. Clears the buffer
4. Returns CPU to normal

### Result After Workaround

```bash
kubectl top node
NAME                    CPU(cores)   CPU(%)
k8s-master3.lab.local   192m         9%      # Was 57% (1098m)
```

---

## TODO: Monitoring Alert

**Need to implement:** Alert when CPU usage is abnormally high on nodes, indicating process hang.

### Proposed Thresholds

| Node Type | CPU Threshold | Duration |
|-----------|---------------|----------|
| Master    | > 50%         | 5 min    |
| Worker    | > 75%         | 5 min    |

### PrometheusRule (TO BE IMPLEMENTED)

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: node-cpu-alerts
  namespace: monitoring
spec:
  groups:
  - name: node-cpu
    rules:
    - alert: MasterNodeHighCPU
      expr: |
        100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 50
        and on(node) kube_node_role{role="control-plane"}
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Master {{ $labels.node }} CPU > 50%"
        description: "High CPU may indicate process hang (qemu-ga, etcd, etc.)"

    - alert: WorkerNodeHighCPU
      expr: |
        100 - (avg by(node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 75
        and on(node) kube_node_role{role="worker"}
      for: 5m
      labels:
        severity: warning
      annotations:
        summary: "Worker {{ $labels.node }} CPU > 75%"
        description: "High CPU may indicate process hang or resource exhaustion"
```

---

## Prevention

1. **Monitor for early detection** (alerts above)
2. **Consider disabling qemu-ga** on masters if not needed
3. **Report bug upstream** to QEMU project with strace evidence
4. **Check Proxmox forums** for similar reports

---

## Related Context

This issue was discovered during remediation system testing:
- Testing clone/restore operations on k8s-worker3
- Clone was slow (13+ min estimated)
- Master3 was not involved in any operations
- Correlation unclear - may be coincidence or Proxmox-wide effect

---

## Timeline

| Time | Event |
|------|-------|
| ~20:30 | Started remediation testing on worker3 |
| ~21:00 | Clone operation triggered on worker3 |
| ~23:00 | Noticed master3 at 57% CPU |
| ~00:01 | Identified qemu-ga at 98% CPU |
| ~00:03 | Applied workaround (restart qemu-guest-agent) |
| ~00:03 | CPU returned to normal (9%) |

---

## Files

- **This document:** `disaster-recovery/issues/qemu-guest-agent-cpu-loop.md`
- **Related:** `disaster-recovery/remediation-design-decisions.md`
