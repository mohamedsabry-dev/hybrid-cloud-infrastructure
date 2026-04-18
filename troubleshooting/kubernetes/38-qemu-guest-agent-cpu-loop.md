# Issue: QEMU Guest Agent CPU Busy Loop

**Status:** TRIGGER NOT IDENTIFIED (Bug mechanism understood, monitoring alerts implemented)
**Date Discovered:** 2026-04-17
**Affected Nodes:**
- k8s-master3.lab.local (2026-04-17)
- k8s-master1.lab.local (2026-04-18 19:09)
- k8s-master1.lab.local + k8s-master2.lab.local (2026-04-18 22:36)
**Occurrences:** 3 total (all self-recovered)
**Severity:** High (node CPU maxed out, can self-recover in 2-8 min)
**Next Step:** Wait for next occurrence to capture more evidence

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

## Root Cause - CONFIRMED (2026-04-18)

### Confirmed Root Cause
1. Proxmox sends `guest-ping` via virtio-serial channel
2. qemu-ga processes the ping and tries to write response `{"return": {}}`
3. virtio-serial buffer becomes full/stuck (Proxmox not reading fast enough)
4. `write()` returns `EAGAIN` (Resource temporarily unavailable)
5. qemu-ga immediately retries without any backoff
6. Result: 100% CPU busy loop

### Evidence from Second Occurrence (master1, 2026-04-18)

**strace output:**
```
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
... (infinite loop)
```

**journalctl showing trigger:**
```
Apr 18 19:09:57 k8s-master1.lab.local qemu-ga[970]: info: guest-ping called
```

**Proxmox socket status:**
```bash
lsof /var/run/qemu-server/1010.qga
# Shows: kvm process LISTENING but not actively reading
```

### Self-Recovery Observed
- Issue lasted ~4 minutes (19:09:57 to 19:14:18)
- Buffer eventually drained when Proxmox resumed reading
- Multiple `qm guest cmd ping` from Proxmox may help clear buffer
- CPU returned to normal without manual restart

### Why It Happens
- Proxmox periodically pings VMs via guest agent
- If host is busy or socket read is delayed, buffer fills up
- qemu-ga bug: no exponential backoff on EAGAIN

---

## Deep Investigation (2026-04-18)

### Trigger Investigation - INCONCLUSIVE

Attempted to identify the exact trigger that causes the buffer to fill up.

#### What We Checked

**Proxmox logs around failure times:**
```bash
journalctl -u pvedaemon --since "2026-04-18 19:05" --until "2026-04-18 19:15" | grep -i "1010\|ping"
```
```
Apr 18 19:09:37 - vncproxy:1010 started (user opened VNC to investigate)
Apr 18 19:09:42 - VM 1010 qga command 'guest-ping' failed - got timeout
Apr 18 19:09:55 - VM 1010 qga command 'guest-ping' failed - got timeout
```

**Proxmox socket status:**
```bash
lsof /var/run/qemu-server/1010.qga
# Shows: kvm 789875 root 15u unix LISTEN (not being read)
```

**First occurrence correlation:**
```
Apr 17 22:30:36 - shutdown VM 1022 (worker3) - remediation test
Apr 17 22:30:50 - VM 1022 qga command 'guest-ping' failed - timeout
Apr 17 22:31:20 - VM 1010 qga command 'guest-ping' failed - timeout (master1)
Apr 17 22:31:23 - VM 1012 qga command 'guest-ping' failed - timeout (master3)
```

#### Theories Tested

| Theory | Test | Result |
|--------|------|--------|
| SSH connections trigger it | Opened 3 SSH sessions simultaneously | Not reproduced |
| VM operations trigger it | Correlated with worker3 shutdown | Partial correlation but not consistent |
| VNC console triggers it | VNC was opened AFTER issue started | VNC was for investigation, not trigger |
| Proxmox host load | Checked systemd-logind suspend spam | Unrelated (lid closed, masked) |
| Scheduled tasks | Checked cron, timers | No correlation |

#### What We Know For Certain

1. **Bug is in qemu-ga** - no backoff on EAGAIN (confirmed via strace)
2. **Only affects K8s VMs** - FreeIPA on same host is fine
3. **Timing-based** - cannot reproduce on demand
4. **Self-recovers sometimes** - buffer eventually drains (~4 min)
5. **Proxmox not actively reading** - socket in LISTEN state during issue

#### Proxmox Host IO Delay Correlation (2026-04-18)

**Evidence from Proxmox CPU/IO graph:**

| Timestamp | Event |
|-----------|-------|
| 2026-04-17 ~22:30-23:00 | First qemu-ga CPU loop on master3 |
| 2026-04-17 23:39:00 | **IO delay spike: 38.54%** on Proxmox host |

**Theory: qemu-ga loop CAUSES host IO delay (not the opposite)**

```
qemu-ga busy loop (millions of write() syscalls/sec)
    ↓
Each write() syscall = VM exit to KVM hypervisor
    ↓
Proxmox host overwhelmed handling VM exits
    ↓
IO delay spike on host (38.54% observed)
```

**Supporting evidence:**
- qemu-ga issue started BEFORE the IO delay spike (timeline matches)
- High syscall rate from VM creates hypervisor overhead
- Could be a feedback loop: initial delay → buffer fills → EAGAIN loop → more host pressure

**To verify on next occurrence:**
```bash
# On Proxmox host during qemu-ga spike - check KVM process CPU
top -p $(pgrep -f "kvm.*<VMID>")
```

#### What Remains Unknown

- Exact trigger that causes Proxmox to stop reading qga socket
- Why only K8s VMs (more activity? timing? specific config?)
- Why production Proxmox laptop doesn't have this issue
- Whether qemu-ga loop causes host IO delay or vice versa (chicken/egg)

#### Normal vs Stuck Behavior

**Normal (from strace):**
```
poll() → wait for data
read(4, ...) → nothing to read
clock_nanosleep() → sleep 100ms
repeat (low CPU)
```

**Stuck (from strace):**
```
write(4, "{\"return\": {}}\n") → EAGAIN
write(4, "{\"return\": {}}\n") → EAGAIN
... (infinite, no sleep, 100% CPU)
```

### What is qemu-ga?

QEMU Guest Agent is a service inside VMs that enables:
- Graceful shutdown/reboot via Proxmox
- Filesystem freeze for consistent snapshots
- VM info reporting (IP, hostname, OS)
- Time synchronization
- Command execution inside VM

### Recommendation

Until root cause is identified:
1. **Keep monitoring alerts** - Early detection implemented
2. **Workaround ready** - `systemctl restart qemu-guest-agent`
3. **Consider disabling on masters** - Control plane doesn't need qemu-ga features
4. **Wait for next occurrence** - Capture more evidence when it happens

### Evidence to Capture on Next Occurrence

```bash
# IMMEDIATELY when issue detected (before recovery):

# 1. On affected VM
strace -p $(pgrep qemu-ga) -o /tmp/qemu-ga-stuck.txt &
sleep 10 && kill %1

# 2. On Proxmox host
journalctl -u pvedaemon --since "5 min ago" > /tmp/pvedaemon.log
lsof /var/run/qemu-server/*.qga > /tmp/qga-sockets.txt
cat /proc/loadavg > /tmp/host-load.txt
ps aux | grep -E "qm|kvm" > /tmp/processes.txt

# 3. Check if qemu-ga loop causes host CPU/IO pressure
top -b -n 1 -p $(pgrep -f "kvm.*<VMID>") > /tmp/kvm-process-cpu.txt
cat /proc/stat > /tmp/host-cpu-stat.txt

# 4. Timing
date > /tmp/issue-time.txt
```

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

## Monitoring Alerts - IMPLEMENTED

**Status:** Implemented on 2026-04-18
**File:** `kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml`

### Alerts Added

| Alert | Threshold | Duration | Description |
|-------|-----------|----------|-------------|
| `KubernetesNodeHighCPU` | > 85% | 5 min | General high CPU warning |
| `KubernetesNodeCriticalCPU` | > 95% | 2 min | Critical CPU saturation |
| `KubernetesNodeHighLoad` | Load > 2x CPUs | 5 min | High load average detection |
| `KubernetesNodeHighSystemCPU` | > 30% system | 5 min | High kernel CPU (qemu-ga EAGAIN symptom) |

The `KubernetesNodeHighSystemCPU` alert specifically targets the symptom observed in this incident (39.8% system CPU from repeated syscalls in busy loop).

---

## Prevention

1. ~~**Monitor for early detection**~~ ✅ Implemented - see Monitoring Alerts section
2. **Consider disabling qemu-ga** on masters if not needed
3. **Report bug upstream** to QEMU project with strace evidence
4. **Check Proxmox forums** for similar reports

---

## Mitigation Attempt: Increase Master CPU Cores

**Date:** 2026-04-18
**Status:** PENDING MONITORING

**Idea:** Increase master node CPU from 2 cores to 4 cores.

**Rationale:**
- qemu-ga busy loop consumes 1 CPU core at 100%
- With 2 cores: 50% total CPU impact, node severely degraded
- With 4 cores: 25% total CPU impact, node remains more responsive
- Other processes (kubelet, kube-apiserver, etcd) can still run on remaining cores

**Change:**
```bash
# On Proxmox
qm set 1010 --cores 4  # master1
qm set 1011 --cores 4  # master2
qm set 1012 --cores 4  # master3
```

**Expected outcome:**
- qemu-ga spike still happens (bug not fixed)
- But node impact reduced from ~50% to ~25%
- Control plane remains more responsive during spike
- Self-recovery may be faster

**To monitor:** Compare next occurrence behavior with 4 cores vs previous 2 cores.

---

## Related Context

This issue was discovered during remediation system testing:
- Testing clone/restore operations on k8s-worker3
- Clone was slow (13+ min estimated)
- Master3 was not involved in any operations
- Correlation unclear - may be coincidence or Proxmox-wide effect

---

## Timeline

### First Occurrence - master3 (2026-04-17)

| Time | Event |
|------|-------|
| ~20:30 | Started remediation testing on worker3 |
| ~21:00 | Clone operation triggered on worker3 |
| ~23:00 | Noticed master3 at 57% CPU |
| ~00:01 | Identified qemu-ga at 98% CPU |
| ~00:03 | Applied workaround (restart qemu-guest-agent) |
| ~00:03 | CPU returned to normal (9%) |

### Second Occurrence - master1 (2026-04-18)

| Time | Event |
|------|-------|
| 19:09:57 | guest-ping triggered, qemu-ga stuck in EAGAIN loop |
| 19:09-19:14 | CPU at 99%, kubectl commands failing |
| 19:14:18 | Buffer self-cleared, multiple pings processed |
| 19:16:xx | System fully recovered without manual intervention |

**Key difference:** Second occurrence self-recovered (~4 min), first required manual restart.

### Third Occurrence - master1 + master2 (2026-04-18 22:36)

Occurred during DR Test 2.

| Node | Start Time | Duration | Recovery |
|------|------------|----------|----------|
| master1 | ~22:36 | ~2 min | Self-recovered |
| master2 | ~22:38 | ~8 min | Self-recovered |

**strace captured on master2:**
```
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
... (infinite loop)
```

**Proxmox logs (VM 1011 = master2):**
```
22:39:37 vncproxy:1011 started
22:39:41 VM 1011 qga command 'guest-ping' failed - got timeout
```

**Note:** VNC console was opened AFTER issue started (to investigate), not the trigger. Trigger remains unknown.

**Proxmox host CPU graph:**
- Showed 60%+ CPU for ~40 minutes
- User experienced actual hang for only 2-4 minutes
- Discrepancy between graph and perceived duration

**Impact on DR test:** Did NOT block remediation - workers were still recovered successfully.

---

## Files

- **This document:** `troubleshooting/kubernetes/38-qemu-guest-agent-cpu-loop.md`
- **Monitoring alerts:** `kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml`
- **Related:** `disaster-recovery/remediation-design-decisions.md`
