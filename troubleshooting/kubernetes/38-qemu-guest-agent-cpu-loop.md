# TS-K8S-038 | 2026-04-17 | WORKAROUND APPLIED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Proxmox / QEMU Guest Agent
Sub-techs: qemu-ga, virtio-serial, EAGAIN busy loop, strace,
           Proxmox guest-ping, Prometheus CPU alerts
Environment: DEV k8s cluster | Proxmox host
Affected nodes: k8s-master3 (2026-04-17), k8s-master1 (2026-04-18 19:09),
                k8s-master1 + k8s-master2 (2026-04-18 22:36)
Occurrences: 3 total (all self-recovered or manually restarted)
Discovered during: Remediation testing on k8s-worker3
Related: disaster-recovery/remediation-design-decisions.md
Re-opened: No (monitoring alerts implemented, waiting for next occurrence)

_____________________________________________________________________

[Issue Description]
QEMU Guest Agent (`qemu-ga`) entered a busy loop consuming 98% CPU on master
nodes. Happened 3 times across different nodes. The bug mechanism is understood
but the trigger that causes it is still unknown.

```
top - 00:01:12 up 13:22,  2 users,  load average: 2.49, 2.33, 2.27
%Cpu(s): 16.1 us, 39.8 sy,  0.0 ni, 41.9 id,  0.3 wa,  1.2 hi,  0.5 si,  0.2 st

  PID USER   PR  NI  VIRT   RES   SHR S  %CPU  %MEM     TIME+ COMMAND
  970 root   20   0 97312   960   628 R  98.7   0.0  88:54.12 qemu-ga
```

Node showed 57% CPU in `kubectl top node` (with 2 cores, qemu-ga consuming
one full core).

_____________________________________________________________________

[Analysis]

# Step 1: strace — identified the busy loop

```
strace -p 970
write(4, "\377{\"return\": 35553302}\n", 22) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "\377{\"return\": 35553302}\n", 22) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "\377{\"return\": 35553302}\n", 22) = -1 EAGAIN (Resource temporarily unavailable)
... (repeating infinitely)
```

File descriptor 4 = virtio-serial channel to Proxmox host. `EAGAIN` = write
buffer full, operation would block. qemu-ga has no sleep/backoff — it immediately
retries, creating an infinite busy loop at 100% CPU.

```
┌─────────────────┐         virtio-serial         ┌─────────────────┐
│   VM (guest)    │  ←───── channel buffer ─────→ │  Proxmox (host) │
│   qemu-ga       │         (FULL/STUCK)          │   not reading   │
└─────────────────┘                               └─────────────────┘
         │
         ▼
    write() → EAGAIN → retry immediately → 100% CPU busy loop
```

# Step 2: Confirmed root cause on second occurrence (master1, 2026-04-18)

strace on second occurrence:
```
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
... (infinite loop)
```

journalctl showing the trigger was a guest-ping:
```
Apr 18 19:09:57 k8s-master1.lab.local qemu-ga[970]: info: guest-ping called
```

Proxmox socket status during issue:
```
lsof /var/run/qemu-server/1010.qga
# Shows: kvm process LISTENING but not actively reading
```

The chain: Proxmox sends `guest-ping` → qemu-ga processes it → tries to write
response `{"return": {}}` → virtio-serial buffer full (Proxmox not reading fast
enough) → `write()` returns `EAGAIN` → qemu-ga retries without backoff → 100%
CPU.

Self-recovery observed: issue lasted ~4 minutes (19:09:57 to 19:14:18). Buffer
eventually drained when Proxmox resumed reading.

# Step 3: Normal vs stuck behavior

Normal (from strace):
```
poll() → wait for data
read(4, ...) → nothing to read
clock_nanosleep() → sleep 100ms
repeat (low CPU)
```

Stuck (from strace):
```
write(4, "{\"return\": {}}\n") → EAGAIN
write(4, "{\"return\": {}}\n") → EAGAIN
... (infinite, no sleep, 100% CPU)
```

# Step 4: Trigger investigation — INCONCLUSIVE

Proxmox logs around first occurrence:
```
Apr 17 22:30:36 - shutdown VM 1022 (worker3) - remediation test
Apr 17 22:30:50 - VM 1022 qga command 'guest-ping' failed - timeout
Apr 17 22:31:20 - VM 1010 qga command 'guest-ping' failed - timeout (master1)
Apr 17 22:31:23 - VM 1012 qga command 'guest-ping' failed - timeout (master3)
```

Tested theories:

| Theory | Test | Result |
|--------|------|--------|
| SSH connections trigger it | Opened 3 SSH sessions simultaneously | Not reproduced |
| VM operations trigger it | Correlated with worker3 shutdown | Partial correlation but not consistent |
| VNC console triggers it | VNC opened AFTER issue started | VNC was for investigation, not trigger |
| Proxmox host load | Checked systemd-logind suspend spam | Unrelated |

What I know for certain:
1. Bug is in qemu-ga — no backoff on EAGAIN (confirmed via strace)
2. Only affects K8s VMs — FreeIPA on same host is fine
3. Timing-based — can't reproduce on demand
4. Self-recovers sometimes (~4 min)
5. Proxmox not actively reading socket during issue

# Proxmox host IO delay correlation

First occurrence: qemu-ga loop started ~22:30, IO delay spike of 38.54% at 23:39.
The qemu-ga loop likely CAUSES host IO delay (not the other way around) — millions
of `write()` syscalls per second = VM exits to KVM hypervisor = host overwhelmed.

# Third occurrence (master1 + master2, 2026-04-18 22:36)

During DR Test 2. master1 recovered in ~2 min, master2 in ~8 min. Both
self-recovered.

strace on master2:
```
write(4, "{\"return\": {}}\n", 15) = -1 EAGAIN (Resource temporarily unavailable)
... (infinite loop)
```

Proxmox logs (VM 1011 = master2):
```
22:39:37 vncproxy:1011 started
22:39:41 VM 1011 qga command 'guest-ping' failed - got timeout
```

Did NOT block the DR test — workers were still recovered successfully.

_____________________________________________________________________

[Final Root Cause]
qemu-ga bug: no exponential backoff when `write()` returns `EAGAIN` on the
virtio-serial channel. When Proxmox stops reading the socket (reason unknown),
the buffer fills up and qemu-ga enters an infinite busy loop. The trigger that
causes Proxmox to stop reading remains unidentified.

_____________________________________________________________________

[Final Solution]

# Workaround (immediate)

```
systemctl restart qemu-guest-agent
```

Kills the stuck process, reconnects virtio-serial, clears buffer, CPU returns
to normal:
```
kubectl top node
NAME                    CPU(cores)   CPU(%)
k8s-master3.lab.local   192m         9%      # Was 57% (1098m)
```

# Mitigation: increased master CPU cores

Changed masters from 2 to 4 cores:
```
qm set 1010 --cores 4  # master1
qm set 1011 --cores 4  # master2
qm set 1012 --cores 4  # master3
```

With 4 cores, qemu-ga spike impacts ~25% total CPU instead of ~50%. Control plane
stays responsive during the issue.

# Monitoring alerts implemented

File: `kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml`

| Alert | Threshold | Duration |
|-------|-----------|----------|
| KubernetesNodeHighCPU | > 85% | 5 min |
| KubernetesNodeCriticalCPU | > 95% | 2 min |
| KubernetesNodeHighLoad | Load > 2x CPUs | 5 min |
| KubernetesNodeHighSystemCPU | > 30% system | 5 min |

`KubernetesNodeHighSystemCPU` specifically targets the symptom (39.8% system CPU
from repeated syscalls in busy loop).

The bug is in qemu-ga code — should implement exponential backoff on EAGAIN:
```c
// Current (buggy): immediate retry = busy loop
while (write(fd, buf, len) == -1 && errno == EAGAIN) { }

// Should be: exponential backoff
int backoff_ms = 10;
while (write(fd, buf, len) == -1 && errno == EAGAIN) {
    usleep(backoff_ms * 1000);
    backoff_ms = min(backoff_ms * 2, 1000);
}
```

# Evidence to capture on next occurrence

```bash
# IMMEDIATELY when detected (before self-recovery):

# 1. On affected VM
strace -p $(pgrep qemu-ga) -o /tmp/qemu-ga-stuck.txt &
sleep 10 && kill %1

# 2. On Proxmox host
journalctl -u pvedaemon --since "5 min ago" > /tmp/pvedaemon.log
lsof /var/run/qemu-server/*.qga > /tmp/qga-sockets.txt
cat /proc/loadavg > /tmp/host-load.txt

# 3. Check if qemu-ga loop causes host CPU/IO pressure
top -b -n 1 -p $(pgrep -f "kvm.*<VMID>") > /tmp/kvm-process-cpu.txt
```

Verified: Workaround confirmed effective. Monitoring alerts active. Waiting for
next occurrence to capture more evidence.

_____________________________________________________________________

[Risk Level] HIGH

Node CPU maxed out, can affect control plane responsiveness. Self-recovers in
2-8 minutes. Trigger unknown — can't prevent, only detect and react.

_____________________________________________________________________

[References]
- disaster-recovery/remediation-design-decisions.md — related remediation context
- kubernetes/dev/deployments/apps/monitoring/custom-alerts.yaml — monitoring alerts
