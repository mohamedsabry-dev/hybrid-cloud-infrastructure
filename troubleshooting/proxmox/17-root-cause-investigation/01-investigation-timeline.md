# TS-PVE-017 Investigation Timeline

**Date**: 2026-04-23/24 (overnight session)
**Duration**: ~8 hours continuous (~23:15 to ~07:30 local, EEST)
**Investigator**: Sabry
**Outcome**: Root cause CONFIRMED — zero IO isolation on shared NVMe + K8s cascade dynamics
**Theories tested**: 12 (10 eliminated, 2 confirmed)
**Total investigation time on theories**: ~6.2 hours

_____________________________________________________________________

## Investigation Overview

Random IO spikes (40%+ PSI, lasting 5-15 minutes, 2-5 times/week for 2+ weeks) on the dev Proxmox host. The incident night started with a 49.7% PSI spike at 01:41 local. Over 8 hours, I tested 12 theories, eliminated 10, and confirmed the root cause: shared consumer NVMe with zero per-VM IO isolation combined with K8s cascade dynamics. The definitive proof came from empirical reproduction: CPU stress on all 3 masters (80% host CPU) produced 0% IO spike, while concurrent LIST operations produced instant 57% IO delay.

_____________________________________________________________________

## Theory 1: Lid Switch / Logind Suspend Storm

**Timeframe**: ~23:15 to ~00:00 local (~45 min)
**Verdict**: SYMPTOM ONLY — downstream effect of IO stall, not cause

### Why Suspected
Kernel logs during the 01:41 spike showed bursts of `systemd-logind: Lockdown: hibernation is restricted` messages — 10 at spike time vs baseline of 2 per 30-minute tick. Correlation seemed strong.

### Investigation

Two-week histogram of logind bursts:
```bash
journalctl -k --since "2 weeks ago" --no-pager | \
  grep "Lockdown: systemd-logind" | \
  awk '{print $1, $2, $3}' | cut -c1-12 | uniq -c | sort -rn | head -20
```
```
     28 Apr 23 21:16
     22 Apr 23 21:17
     20 Apr 23 21:15
     15 Apr 23 14:13
     11 Apr 23 21:18
     10 Apr 24 01:43   ← matches tonight's 01:41 spike
      7 Apr 23 23:37
      2 Apr 24 01:45
      2 Apr 24 01:31
```

Logind config check:
```bash
grep -vE '^\s*#|^\s*$' /etc/systemd/logind.conf
```
Result: all defaults, no overrides. `HandleLidSwitch=suspend` in effect.

Lid switch device check:
```bash
evtest /dev/input/event0
```
```
Input device name: "Lid Switch"
Event code 0 (SW_LID) state 1
```

Kernel log for lid events:
```bash
journalctl -k --since "2 weeks ago" | grep -i "lid" | head -30
```
Result: only boot-time registration messages. No runtime lid state changes logged.

### Evidence For
- Bursts of logind messages correlated with IO spikes (10 events at 01:43, 81 events during Apr 23 21:15-21:18 cluster)
- Pattern: baseline 2/30min, bursts during spikes

### Evidence Against
- My pushback: "the lid is closed all day, why happen only once each 4 days"
- 10-28 failed suspend calls cannot cause 49% PSI IO pressure — each failed suspend is just a dbus call + log write
- No lid state-change events captured in kernel logs during spikes

### What Eliminated It
I wasn't convinced. The correlation was real but the magnitude was wrong — a few hundred log lines don't generate 49% IO pressure. Later understanding confirmed: logind bursts are a MARKER of the system being IO-stalled (timers queue up during stall, fire at once when IO unblocks), not the cause.

### Pivot
My pushback "im not convinced at all, I very suspect either kernel issue or disk issue" redirected the investigation to systematic hardware/OS elimination.

_____________________________________________________________________

## Theory 2: Disk Hardware Failure

**Timeframe**: ~00:00 to ~00:30 local (~30 min)
**Verdict**: RULED OUT

### Why Suspected
High IO latency during spikes could indicate failing NVMe — bad sectors, controller issues, or wear.

### Investigation

SMART health:
```bash
smartctl -a /dev/nvme0n1 | grep -iE 'critical|media_errors|error_log|percentage_used|unsafe_shutdown|temperature'
```
Result: all healthy. No media errors, no critical warnings.

Kernel IO error scan:
```bash
journalctl -k --since "2 weeks ago" --no-pager | \
  grep -iE 'ata[0-9]|scsi|nvme|blk_update|i/o error|medium error|sense key|buffer i/o|end_request|reset|link down|timeout|aborted' | head -50
```
Result: empty — no IO errors in 2 weeks.

Task hang check:
```bash
journalctl -k --since "2 weeks ago" --no-pager | \
  grep -iE 'blocked for more than|hung_task|task .* blocked|khungtaskd' | head -50
```
Result: empty — no blocked tasks.

### What Eliminated It
SMART healthy, kernel logs clean, no IO errors, no blocked tasks, no controller resets. The NVMe hardware was fine — the issue was HOW it was being used (shared with no isolation), not whether it was broken.

_____________________________________________________________________

## Theory 3: Kernel Bug

**Timeframe**: ~00:00 to ~00:15 local (~15 min)
**Verdict**: RULED OUT

### Why Suspected
PVE kernel 6.17.9-1 could have a bug causing IO stalls.

### Investigation

```bash
uname -a
journalctl -k --since "2 weeks ago" --no-pager | \
  grep -iE 'bug:|oops|warning:|call trace|kernel panic|hardware error|mce:|edac|uncorrected|machine check|rcu_sched|soft lockup|nmi watchdog' | head -50
```

MCE check:
```bash
journalctl -k --since "2 weeks ago" | grep -iE 'mce|corrected error|thermal' | head
```

EDAC memory error counters:
```bash
cat /sys/devices/system/edac/mc/mc*/ce_count 2>/dev/null
cat /sys/devices/system/edac/mc/mc*/ue_count 2>/dev/null
```

### What Eliminated It
No oopses, no BUGs, no MCEs, no soft lockups, no call traces, no kernel panics. Kernel was healthy.

_____________________________________________________________________

## Theory 4: ZFS Issue

**Timeframe**: ~00:15 to ~00:25 local (~10 min)
**Verdict**: RULED OUT

### Why Suspected
ZFS ARC pressure, txg_sync stalls, or scrub interference could cause IO spikes.

### Investigation

```bash
pvesm status
zpool status
zpool iostat -v 2 5
```
```
pvesm: local-lvm = lvmthin (active, 250GB)
zpool status: no pools available
zpool iostat: no pools available
```

### What Eliminated It
No ZFS pools exist. Storage is LVM-thin on single NVMe, not ZFS. The ZFS module was loaded (kernel taint from PVE default) but completely unused. This eliminated the entire class of ZFS-specific theories.

### Key Discovery
The `pvesm status` output revealed the storage layout — LVM-thin pool on single NVMe. Combined with `lsblk`, this showed 15+ VM disks sharing one NVMe queue. This architectural fact became central to the final root cause.

_____________________________________________________________________

## Theory 5: TS-K8S-038 qemu-ga Occurrence #4

**Timeframe**: ~00:45 to ~01:30 local (~45 min)
**Verdict**: RULED OUT for this occurrence

### Why Suspected
qemu-ga logs on master1 showed a 5-minute gap in guest-ping responses, similar to the pattern documented in TS-K8S-038 (3 prior occurrences of EAGAIN busy loop).

```
Apr 24 01:33:03 qemu-ga: info: guest-ping called   ← last before gap
Apr 24 01:38:30 qemu-ga: info: guest-ping called   ← resumes (5-min gap)
Apr 24 01:39:26 qemu-ga: info: guest-ping called   ← duplicate timestamp (buffer drain)
```

Initially declared "occurrence #4" with over-confidence.

### Investigation

qemu-ga CPU check:
```bash
ps -eo pid,%cpu,comm | grep qemu-ga
```
```
  994  0.0 qemu-ga
```
CRITICAL: qemu-ga at 0.0% CPU. If TS-K8S-038 were active, it would be at 98%.

etcd slow-apply timing (from crictl logs):
```
22:26:15 UTC  FIRST slow-apply warnings (1.15s delays)
22:29:42 UTC  Brief slow operations (100-200ms)
22:31:07 UTC  ReadIndex timeout, 650ms applies
22:33:03 UTC  qemu-ga LAST ping before gap   ← 7 MINUTES AFTER etcd trouble started
22:33:48 UTC  ReadIndex timeout (2nd)
22:33:49 UTC  CASCADE: dozens of apply warnings, up to 2.04s
22:38:30 UTC  qemu-ga resumes
```

pvedaemon logs from host:
```
Apr 24 01:39:10 pve-dev pvedaemon: VM 1010 qga command 'guest-ping' failed - got timeout
```

### Evidence Against
1. qemu-ga CPU was 0% — never captured at high (previous occurrences had strace showing 98% CPU)
2. etcd slowness began at 22:26:15 UTC — **7 minutes BEFORE** qemu-ga gap at 22:33:03 UTC
3. Causality is OPPOSITE of TS-K8S-038 theory (etcd slow → qemu-ga gap, not qemu-ga → etcd slow)
4. No strace evidence of EAGAIN loop

### What Eliminated It
The timeline ordering proved causality was reversed. In TS-K8S-038, qemu-ga busy loop starves the VM, which then causes etcd issues. Here, etcd was already slow 7 minutes before qemu-ga went silent. The qemu-ga gap was a SYMPTOM of the VM being IO-starved, not the cause.

Note: occurrences 1-3 in TS-K8S-038 had captured strace evidence (`write() = -1 EAGAIN`) and 98% CPU. Those remain legitimate. This was a different failure mode.

### My Correction
Had to acknowledge: "I was too confident saying 'this is definitely TS-K8S-038 occurrence #4.' Your instinct 'I don't know which caused the other' was the right call."

_____________________________________________________________________

## Theory 6: Host Storage Stall

**Timeframe**: ~01:00 to ~01:20 local (~20 min)
**Verdict**: RULED OUT

### Why Suspected
Something on the Proxmox host could cause multi-second IO stall, freezing VMs.

### Investigation

```bash
journalctl -k --since "2026-04-24 01:20" --until "2026-04-24 01:50" | \
  grep -iE 'blocked|hung|timeout|error|reset|nvme|ata|scsi'
```
Result: only logind lockdown messages — no storage errors.

```bash
dmesg -T | grep -E 'Apr 24 01:2|Apr 24 01:3|Apr 24 01:4'
```
Result: clean.

### What Eliminated It
Host kernel was completely clean during the spike window. No IO errors, no blocked tasks, no storage issues. The host OS wasn't stalling — the VMs were generating the IO pressure themselves.

_____________________________________________________________________

## Theory 7: VM Memory Starvation

**Timeframe**: ~01:20 to ~02:20 local (~60 min)
**Verdict**: CONTRIBUTOR (not root cause alone)

### Why Suspected
VM memory inspection revealed drastically undersized K8s masters.

### Investigation

Inside master1:
```bash
free -h
```
```
             total     used     free   shared  buff/cache  available
Mem:         2.2Gi    1.5Gi     83Mi     44Mi      722Mi      621Mi
Swap:           0B       0B       0B
```

```bash
cat /proc/meminfo | grep -iE 'MemAvailable|SwapTotal|Committed'
```
```
MemAvailable:     635724 kB
SwapTotal:             0 kB
Committed_AS:    4714148 kB   ← 213% overcommit!
```

VM configuration:
```bash
qm monitor 1010
# info balloon
```
```
balloon: 0
memory: 2560      ← 2.5 GB hard allocated
```

kube-apiserver restart evidence:
```
restartCount: 86
lastState.terminated.exitCode: 137 (OOMKilled)
```

### Evidence For
- 2.5 GB total RAM for a K8s master running etcd + apiserver + scheduler + controller-manager + kubelet + calico + containerd
- 0 swap — no safety net
- 213% memory overcommit inside VM
- 86 apiserver OOMKills
- Only 621 MB actually available
- Minimum recommended: 4 GB. Production (my other cluster): 4 GB

### Evidence Against
This was the configuration for weeks of stable operation. If memory alone were the cause, it would have failed from day one.

### Why CONTRIBUTOR Not Root Cause
Memory starvation makes the cluster MORE VULNERABLE to cascade triggers — less page cache for etcd, more likely to OOM, less headroom to absorb perturbations. But memory alone didn't explain "worked for weeks, failed today."

Applied partial fix: masters 2.5 GB → 3 GB, workers 3.25 GB → 3 GB (net +750 MB to host allocation).

_____________________________________________________________________

## Theory 8: Host RAM Overcommit

**Timeframe**: ~01:30 to ~02:00 local (~30 min)
**Verdict**: CONTRIBUTOR (not root cause alone)

### Why Suspected
Host-level memory inspection revealed overcommitment.

### Investigation

```bash
free -h
qm list | awk 'NR>1 {sum+=$4} END {print "Total allocated VM RAM:", sum, "MB"}'
```
```
             total     used     free   shared  buff/cache  available
Mem:          22Gi     18Gi    780Mi    136Mi      4.1Gi      4.3Gi
Swap:        8.0Gi    3.8Mi    8.0Gi

Total allocated VM RAM: 23808 MB
```

### Evidence For
- 24 GB allocated to VMs on 22 GB host
- Host available: only 4.3 GB
- Swap touched: 3.8 MB (host has been under pressure)
- Possible only because KSM deduplication + not all VMs at full allocation

### Evidence Against
Same configuration ran stably for weeks. No recent change.

### Why CONTRIBUTOR Not Root Cause
Host overcommit reduces the overall system headroom. When VMs are memory-starved AND the host is overcommitted AND NVMe is shared — three amplifying factors. But overcommit alone didn't cause the spikes.

_____________________________________________________________________

## Theory 9: SSSD Restart Cascade

**Timeframe**: ~02:45 to ~03:25 local (~40 min)
**Verdict**: RULED OUT

### Why Suspected
SSSD restarted at 02:51:35, and pod cascade began 57 seconds later. SSSD is the FreeIPA/LDAP client — during reconnect, NSS lookups block, which could cause kubectl exec probes to hang.

### Investigation

```bash
systemctl status sssd
```
```
sssd.service - active (running) since Fri 2026-04-24 02:51:35 EEST; 30s ago
Started sssd.service
GSSAPI client step 1 [x3]
GSSAPI client step 2
```

Timeline correlation:
```
02:51:35  sssd restart (GSSAPI/Kerberos auth)
02:52:32  kustomize-controller first failure (connection refused)
02:52:39  pods start restart cascade
02:52:52  calico-kube-controllers exit 255 (killed by liveness)
02:53:00  host PSI peaks 54%
```

### Evidence For
57-second window from SSSD restart to cascade. calico-node's exec probes could hang on NSS lookups during SSSD reconnect.

### What Eliminated It
My own correction: "only this node, it was hung from the morning and I didn't know, I just started it now and this happened."

master1 was hung since morning. I rebooted it at ~02:51. The SSSD restart was normal VM boot behavior, not a mid-operation restart. The 02:53 spike was master1's rejoin storm (etcd resync + full LIST from all controllers), not SSSD-related.

_____________________________________________________________________

## Theory 10: Prometheus Scrape Storm

**Timeframe**: ~03:00 to ~03:10 local (~10 min)
**Verdict**: RULED OUT as trigger

### Why Suspected
Prometheus continuously scrapes all pods and nodes. Could fan-out cause spikes?

### My Own Question
"Do u think prometheus scraping data from all node cluster + all pods same time cause this? But it's scraping all the day, why only few spikes?"

The question contained its own answer — if Prometheus were the cause, spikes would be continuous, not random.

### Investigation

```bash
kubectl -n monitoring logs prometheus-kube-prometheus-stack-prometheus-0 \
  -c prometheus | grep -E "starting|Start listening" | tail
```
```
time=2026-04-23T12:17:23.707Z level=INFO msg="Start listening for connections" address=0.0.0.0:9090
```

Prometheus start time: Apr 23 15:17 local (UTC 12:17). Had been running 10+ hours before either spike. No restart before spikes.

### What Eliminated It
Prometheus was running continuously since morning. No restart correlated with spikes. Prometheus may AMPLIFY cascade (retry-when-apiserver-briefly-slow) but didn't initiate it.

_____________________________________________________________________

## The Breakthrough Question (~05:40 local)

Between theories 10 and 11, the investigation was stuck. The cluster was in sustained cascade (40-67% PSI for 40+ minutes). kube-scheduler CrashLoopBackOff on 2 masters, kube-controller-manager CrashLoopBackOff, csi-nfs-controller at 88 restarts, Flux controllers crashing.

Then I asked: **"It was running stable over weeks, why this time now exactly today it dying?"**

This broke the investigation open. Previous framing treated the cluster as "always broken." The correct framing: "was stable for weeks AND NOW BROKEN." If hardware were the root cause, it would have been broken from day one. Something specific happened today.

This redirected from "what's wrong with the hardware" to "what cascade dynamics are sustaining the failure."

_____________________________________________________________________

## The Scale-to-0 Breakthrough (~06:00 local)

The cascade was self-sustaining — restarts caused IO load, IO load caused probe failures, probe failures caused restarts. Only way to test: remove the load.

### Commands
```bash
kubectl -n apps scale deployment wordpress --replicas=0
kubectl -n flux-system scale deployment helm-controller --replicas=0
kubectl -n flux-system scale deployment kustomize-controller --replicas=0
kubectl -n flux-system scale deployment notification-controller --replicas=0
kubectl -n flux-system scale deployment source-controller --replicas=0
kubectl -n monitoring scale statefulset loki --replicas=0
kubectl -n monitoring scale statefulset alertmanager-kube-prometheus-stack-alertmanager --replicas=0
kubectl -n monitoring scale statefulset prometheus-kube-prometheus-stack-prometheus --replicas=0
kubectl -n monitoring scale deployment kube-prometheus-stack-grafana --replicas=0
kubectl -n monitoring scale deployment kube-prometheus-stack-operator --replicas=0
kubectl -n monitoring scale deployment kube-prometheus-stack-kube-state-metrics --replicas=0
kubectl -n monitoring patch daemonset promtail \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'
kubectl -n monitoring patch daemonset kube-prometheus-stack-prometheus-node-exporter \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"disabled":"true"}}}}}'
kubectl -n remediation scale deployment remediation --replicas=0
```

### Result
IO pressure dropped to baseline within ~5 minutes. Control plane stopped crashing. Restart counts stopped growing. Cluster became quiet.

This proved:
1. Cascade dynamics, NOT resource exhaustion
2. The hardware CAN run the cluster (same hardware was fine after scale-down)
3. Restart loops were sustaining the cascade
4. Not hardware, not memory, not etcd, not any specific component

### Sequential Reintroduction (validated order)
Each component scaled back with 5-minute waits. ALL started with 0 restarts:
1. Prometheus → 2/2 Running in 27s
2. Grafana → 4/4 Running in 3m49s
3. Loki → 2/2 Running
4. Node-exporter → 6 pods in 5 seconds
5. Promtail → 6 pods in 14 seconds ("they was never that fast")
6. kube-state-metrics → 1/1 Running in 13s (previously 13+ restarts CrashLoopBackOff)
7. prometheus-operator → 1/1 Running in 60s
8. Flux controllers → all Running, 0 restarts

Final cluster state:
```
NAME                    CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
k8s-master1.lab.local   136m         3%       1790Mi          58%
k8s-master2.lab.local   177m         4%       2134Mi          70%
k8s-master3.lab.local   138m         3%       1729Mi          56%
k8s-worker1.lab.local   91m          4%       1631Mi          69%
k8s-worker2.lab.local   87m          4%       1815Mi          77%
k8s-worker3.lab.local   73m          3%       1659Mi          70%
```

_____________________________________________________________________

## Theory 11a: CPU Stress (qemu-ga) Causes Cascade

**Timeframe**: ~06:30 to ~07:00 local (~30 min)
**Verdict**: RULED OUT by empirical stress test

### Why Suspected
After connecting qemu-ga (TS-K8S-038) to cascade dynamics, the theory was: qemu-ga CPU spike → master CPU-starved → probes fail → cascade.

### Test 1: CPU Stress on Single Master

```bash
# On master1
for i in 1 2 3 4; do yes > /dev/null & done
sleep 180
killall yes
```

(Ran twice accidentally, creating 13 yes processes)

`top` on master1:
```
PID    USER      %CPU  %MEM  COMMAND
12245  k8s_adm+  35.2  0.1   yes
12246  k8s_adm+  33.6  0.1   yes
...13 yes processes...
2234   root       4.7  5.3   etcd        ← still running fine
2215   root       4.0 18.1   kube-apiserver  ← still running fine
1955   root       1.7  3.1   kubelet     ← still running fine
```

Result: "No spike on server and cluster stable despite this."

### Test 2: CPU Stress on ALL 3 Masters Simultaneously

```bash
# On all 3 masters at once
timeout 300 bash -c 'for i in 1 2 3 4; do yes > /dev/null & done; wait'
```

Proxmox host:
```
CPU usage: 80.46% of 16 CPU(s)
Load average: 8.17, 4.78, 3.31
IO Pressure: ~0%    ← ZERO!
```

### What This Proved
CPU stress on ALL 3 masters simultaneously (80% host CPU) produced ZERO IO spike. Linux's CPU scheduler fairly distributes CPU time — etcd still got 4.7%, apiserver 4.0%. CPU exhaustion alone does NOT trigger cascade.

### My Insight
"Despite the load avg increase and cpu increase much but the IO never moved, which actually tell us not the cpu overload the quem cause make us IO issue but the concurrent spam of requests."

_____________________________________________________________________

## Theory 11b: Request/IO Spam Causes Cascade — CONFIRMED

**Timeframe**: ~07:00 to ~07:20 local (~20 min)
**Verdict**: CONFIRMED — root cause mechanism

### Why Suspected
If CPU stress doesn't cascade, what about IO/request pressure? When controllers restart, they do full LIST operations against apiserver → etcd, which generates IO (not CPU).

### Test: LIST Operation Spam on All 3 Masters

```bash
for i in {1..100}; do
  kubectl get pods -A --output=json > /dev/null &
  kubectl get events -A --output=json > /dev/null &
done
```

200 concurrent requests per master × 3 masters = 600 concurrent LIST operations.

### IMMEDIATE DRAMATIC RESULT

Proxmox host:
```
CPU usage: 35.91% of 16 CPU(s)       ← LESS than CPU stress test
IO delay: 57.58%                      ← MASSIVE
Load average: 32.99, 16.10, 8.07
RAM usage: 88.29%
SWAP: 5.68%
```

iostat:
```
avg-cpu:  %user   %nice %system %iowait  %steal   %idle
          41.57    0.00    1.52   45.08    0.00   11.82

Device     r/s     rkB/s    r_await   aqu-sz    %util
dm-23      198.50  12922    1312.43   260.52    100%
dm-24      150.50   9582    1496.95   225.29    100%
dm-25      151.50   6432    1239.59   187.80    100%
dm-3       507     29010    1345.70   700.06    100%
nvme0n1    508.50  29018    1343.14   685.82    90.55%
```

KVM processes:
```
490523  kvm  367.2%  ← master1
491286  kvm  305.3%  ← master2
490587  kvm  250.0%  ← master3
490657  kvm   17.9%  ← worker (normal)
```

### Key Numbers
- NVMe read latency: **1343ms** (vs 1-3ms normal — 400x increase)
- Queue depth: **700** operations queued
- Disk utilization: **90-100%** on all master devices
- IO delay: **57.58%** (vs 0% during CPU stress!)

### The Definitive Comparison
| Test | Host CPU | IO PSI | NVMe Latency | Cascade? |
|------|----------|--------|--------------|----------|
| CPU stress × 3 masters | 80.46% | ~0% | normal | No |
| LIST spam × 3 masters | 35.91% | 57.58% | 1343ms | YES |

CPU stress used MORE CPU but caused ZERO IO problems. Request spam used LESS CPU but caused CATASTROPHIC IO. The mechanism is IO contention through etcd fsync/reads, not CPU starvation.

_____________________________________________________________________

## Theory 12: No IO Isolation Architecture — CONFIRMED

**Timeframe**: ~07:10 to ~07:25 local (~15 min)
**Verdict**: CONFIRMED — architectural root cause

### Why Suspected
The LIST spam test showed ALL master disk devices saturated from concurrent requests. What about a SINGLE VM?

### Test: Configmap Write Storm from ONE VM

```bash
for i in {1..1000}; do
  kubectl create configmap stress-test-$i \
    --from-literal=data="$(head -c 10000 /dev/urandom | base64)" &
done
```

1000 configmaps × 10KB from a single master.

### Result
```
IO delay: 57.20%
NVMe latency: 302ms
Queue depth: 191
```

API errors from another master:
```
E0424 07:06:24 memcache.go:265] "Unhandled Error"
  err="couldn't get current server API group list: net/http: TLS handshake timeout"
```

SSH to other masters: hanging. VNC: unresponsive. One VM's IO storm broke the ENTIRE host.

### My Insight
"Which actually make a complete picture, that even if quem ran against 1 node, only one node and overwhelm it with IO, it completely overwhelm the whole cluster and the whole server physical which mean there is no actually isolation and 1 node crash can kill the server not just the node."

### Proxmox IO Throttle Discovery
Checked Proxmox GUI: Hardware → scsi0 → Edit → Bandwidth tab:
- Read limit (MB/s): **unlimited**
- Write limit (MB/s): **unlimited**
- Read limit (ops/s): **unlimited**
- Write limit (ops/s): **unlimited**

ALL unlimited. This is WHY one VM can nuke the host.

### What This Confirmed
The REAL architectural issue: Proxmox with LVM-thin on single consumer NVMe has ZERO IO QoS. No per-VM bandwidth limits, no per-VM IOPS limits. One VM can monopolize all NVMe bandwidth. The shared NVMe queue is a shared failure domain.

_____________________________________________________________________

## Pivot Points — Key Moments That Changed Direction

| # | Moment | What Changed |
|---|--------|-------------|
| 1 | "I'm not convinced at all, I suspect kernel or disk" | Redirected from logind theory to systematic hardware elimination |
| 2 | "I really don't know which caused the other" | Forced reconsideration of qemu-ga TS-K8S-038 causality |
| 3 | "My prod laptop don't face this issue" | Introduced prod comparison baseline |
| 4 | "It was running stable over weeks, why today?" | BROKE THE INVESTIGATION OPEN — shifted from "always broken" to "recently broken" |
| 5 | Scale-to-0 → instant IO drop | Proved cascade dynamics, not hardware |
| 6 | "They was never that fast" (promtail in 14s) | Confirmed healthy cluster runs all workloads fine |
| 7 | CPU stress × 3 masters → 0% IO | Eliminated CPU as cascade trigger |
| 8 | "Not the CPU overload but concurrent spam of requests" | My own insight that led to LIST spam test |
| 9 | LIST spam → instant 57% IO | Reproduced cascade on demand |
| 10 | Single VM write storm → host-wide IO delay | Proved zero IO isolation is the architectural issue |

_____________________________________________________________________

## Complete Theories Summary

| # | Theory | Status | Time | Key Evidence |
|---|--------|--------|------|-------------|
| 1 | Lid switch / logind storm | SYMPTOM ONLY | 45m | Correlated but too small to cause 49% PSI |
| 2 | Disk hardware failure | RULED OUT | 30m | SMART OK, kernel clean, no IO errors |
| 3 | Kernel bug | RULED OUT | 15m | No oopses, BUGs, MCEs, or soft lockups |
| 4 | ZFS issue | RULED OUT | 10m | No ZFS pools exist (LVM-thin used) |
| 5 | TS-K8S-038 qemu-ga #4 | RULED OUT | 45m | 0% CPU, etcd slow 7 min before gap |
| 6 | Host storage stall | RULED OUT | 20m | Host kernel clean during spike |
| 7 | VM memory starvation | CONTRIBUTOR | 60m | 2.5 GB / 0 swap / 86 OOM kills |
| 8 | Host RAM overcommit | CONTRIBUTOR | 30m | 24 GB VMs on 22 GB host |
| 9 | SSSD restart cascade | RULED OUT | 40m | Normal VM boot, not mid-op restart |
| 10 | Prometheus scrape storm | RULED OUT | 10m | Running 10+ hrs before spike |
| 11a | CPU stress → cascade | RULED OUT | 30m | 80% CPU, 0% IO, cluster stable |
| 11b | Request/IO spam → cascade | **CONFIRMED** | 20m | 57% IO delay, 1343ms latency |
| 12 | No IO isolation architecture | **CONFIRMED** | 15m | 1 VM write storm → host-wide IO |
| | **TOTAL** | | **370m / 6.2h** | |

_____________________________________________________________________

## Lessons Learned

### Investigation methodology
1. **Establish baseline before investigating deviation** — "it worked for weeks, why today?" was the single most valuable question
2. **User instinct often correct — LISTEN** — every pushback ("I'm not convinced", "why only sometimes") redirected toward truth
3. **Simple tests beat complex theories** — scale-to-0 took 5 minutes and gave definitive answer. Hours of theorizing couldn't replace it
4. **Multiple correlations don't prove causation** — logind bursts + IO spikes = strong correlation, zero causation
5. **Confidence should scale with evidence, not effort** — I was over-confident early. Effort spent ≠ certainty of conclusion

### System design insights
6. **Probe timeouts are critical parameters** — default 1-5s timeouts fail catastrophically on constrained hardware
7. **Sequential operations beat parallel** — always on constrained hardware
8. **Automation can hide problems** — remediation controller brought worker3 back without being asked
9. **GitOps has a timing dilemma** — Flux reverting manual changes during incident response = fighting the tool
10. **Dev and prod aren't always equivalent** — prod survives with 4 GB masters because it has more headroom
11. **IO isolation is often missing in consumer setups** — Proxmox LVM-thin on single NVMe has NO IO QoS by default
