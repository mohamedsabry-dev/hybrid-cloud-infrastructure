DR Test: Root Filesystem Full (/) — Worker Node Disk Pressure to Total Failure
Date: 2026-05-03
Result: PASS — kubelet self-healing validated, monitoring blind spot found
_____________________________________________________________________

[Info]
Domain: Linux / Kubernetes / Disk Pressure / Eviction / Remediation
Environment: DEV — k8s-worker3.lab.local (VM 1022, pve-prod)
  Rocky Linux 10.1, 4 CPU, 7 GiB RAM, 17 GiB root disk
Triggered by: Production-realistic DR test — disk full is the most
  common silent killer in Linux environments. Wanted to test the full
  chain: disk pressure → kubelet behavior → pod eviction → node failure
  → remediation recovery → alerting.

_____________________________________________________________________

[Planned Scope]

Fill the root filesystem on worker3 to 100% using dd. Observe what
breaks at each stage — kubelet response, pod eviction order, monitoring
behavior, node status. Then reboot at 100% and see if the node can
recover. Test the full observability stack: Grafana dashboards, Loki
logs, kube-events, Alertmanager email alerts, remediation pod auto-heal.

I planned to have separate linux test1, test2 vms for such risk corruption
but want to do it a bit aggressive on worker since want to make the DR
practice today cover k8s observability.

_____________________________________________________________________

[Pre-Test Findings]

Finding 1 — /var is not a separate partition:

Checked Grafana "Disk Space Used" panel for worker3. Only these
filesystems are monitored:
  /         4.72 GiB (available)
  /boot     361 MiB
  /run      1.28 GiB
  /run/credentials/*   1 MiB each

/var does not appear as a mount point. Confirmed with df -h — /var is
just a directory under /, not its own partition.

  ```
  [root@k8s-worker3 var]# du -sh /var
  9.5G    /var
  [root@k8s-worker3 var]# df -h /
  Filesystem           Size  Used Avail Use% Mounted on
  /dev/mapper/rl-root   17G   13G  4.9G  72% /
  ```

/var eats 9.5 GiB of the 13 GiB used on /. That's 73% of disk usage
from one directory — containerd images, kubelet state, logs.

In production, /var is usually its own partition so a runaway log or
container filling /var can't kill the OS. The golden image uses Rocky
Linux default partitioning which lumps everything under /.

Need to fix on golden image level and almost all vms if possible.
I often see production vms at my company separate them — it makes
sense now.


Finding 2 — No /var alerting:

Prometheus monitors / as one block. No granular alert for /var/log or
/var/lib/containers growing. You'd only notice when / hits threshold —
by then it could already be too late.

See: troubleshooting/kubernetes/reference/60-disk-full-monitoring-gaps.md

_____________________________________________________________________

[Pre-State]

  ```
  [root@k8s-master1 ~]# kubectl top nodes
  NAME                    CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
  k8s-master1.lab.local   122m         6%       2212Mi          48%
  k8s-master2.lab.local   114m         5%       2301Mi          50%
  k8s-master3.lab.local   144m         7%       2634Mi          57%
  k8s-worker1.lab.local   143m         3%       4261Mi          64%
  k8s-worker2.lab.local   103m         2%       3317Mi          50%
  k8s-worker3.lab.local   60m          1%       1807Mi          27%
  ```

Grafana node-exporter dashboard for worker3:
  CPU Busy: 2.0%, Sys Load: 1.8%, RAM Used: 17.4%
  Root FS Used: 71.9%, RootFS Total: 17 GiB

Loki queries open for monitoring:
  {job="kube-events"}
  {namespace="kube-system", pod=~"kube-apiserver.*"}
  {namespace="kube-system", pod=~"etcd.*"}
  {node_name="k8s-worker3.lab.local"}

Disk state:
  ```
  /dev/mapper/rl-root   17G   13G  4.9G  72% /
  /dev/sdb2            960M  599M  362M  63% /boot
  ```

12 pods on worker3:
  ```
  apps          wordpress-6c8c669587-5r4lp              2/2  Running
  default       test-sched-1a                           1/1  Running
  default       test-sched-1b                           1/1  Running
  default       test-sched-1c                           1/1  Running
  default       test-sched-2a                           1/1  Running
  kube-system   calico-node-gtg6l                       1/1  Running
  kube-system   csi-nfs-node-f4jgw                      3/3  Running
  kube-system   kube-proxy-gxwm7                        1/1  Running
  monitoring    event-exporter-57769d9b74-vzqw4          1/1  Running
  monitoring    kube-prometheus-stack-prometheus-node-exporter-fqj87  1/1  Running
  monitoring    loki-canary-bqnd4                       1/1  Running
  monitoring    promtail-fnjgw                          1/1  Running
  ```

The test-sched pods are leftovers from the scheduler DR test. Kept
them to see if they'd land in eviction — they have default priority 0.

Event exporter is 1 replica on worker3. I expect it to go down which
will make me not able to see the logging of events from loki but only
from cli. Will scale it up to 2 after the test using flux with regular
push PR flow.

Proxmox backup + snapshot taken before test.

_____________________________________________________________________

[Test 1 — Fill disk: 5 GiB (target 100%)]

Action:
  ```
  dd if=/dev/zero of=/var/fill-disk bs=1M count=5000
  ```

Result:
  ```
  5000+0 records in
  5000+0 records out
  5242880000 bytes (5.2 GB, 4.9 GiB) copied, 29.2965 s, 179 MB/s
  [root@k8s-worker3 var]# df -h /
  Filesystem           Size  Used Avail Use% Mounted on
  /dev/mapper/rl-root   17G   17G  6.7M 100% /
  ```

Hit 100%. Then within seconds:
  ```
  /dev/mapper/rl-root   17G  9.6G  7.4G  57% /
  ```

Dropped from 100% to 57%. Kubelet self-healed.

Kube-events from Loki:
  ```
  20:41:47 EvictionThresholdMet    "Attempting to reclaim ephemeral-storage"
  20:41:54 NodeHasDiskPressure     "Node k8s-worker3.lab.local status is now: NodeHasDiskPressure"
  ```

Kubelet journal shows what happened — image garbage collection:
  ```
  20:42:03 image_gc_manager.go:528 "Removing image to free bytes" (×30 images)
  20:42:13 eviction_manager.go:388 "Eviction manager: able to reduce resource
           pressure without evicting pods." resourceName="ephemeral-storage"
  ```

Kubelet purged ~30 unused cached container images. That was enough to
free space without evicting any pods. The fill-disk file still exists:
  ```
  [root@k8s-worker3 var]# ls -lh /var/fill-disk
  -rw-r--r--. 1 root root 4.9G May  3 20:41 /var/fill-disk
  ```

Grafana graph confirmed: spike to 98.1% then sharp drop back.

All pods still Running, no eviction, no rescheduling. API server and
etcd logs showed nothing — they didn't notice.

What this tells me:
  Kubelet's first defense is image GC — clean unused images before
  touching any pods. It worked because there were enough stale cached
  images to free space. But now those images are gone, so the next
  fill won't have this safety net.

_____________________________________________________________________

[Test 2 — Fill disk again: 7.5 GiB (no cached images left)]

After round 1, kubelet purged all unused images. Now 7.4 GiB free
with no image cache to sacrifice.

Action:
  ```
  dd if=/dev/zero of=/var/fill-disk2 bs=1M count=7500
  ```

Result — disk at 96%:
  ```
  /dev/mapper/rl-root   17G   17G  747M  96% /
  ```

This time kubelet couldn't self-heal with image GC alone.

Pod eviction cascade — events from Loki (chronological):

  ```
  20:50:32 ReconciliationSucceeded  Kustomization/apps finished (Flux still working)
  20:50:51 SuccessfulDelete         "Deleted pod: wordpress-6c8c669587-s8r5w"
  20:50:58 Unhealthy                WordPress readiness probe failed: "dial tcp: connect: invalid argument"
  20:51:08 ExceededGracePeriod      loki-canary — container runtime couldn't kill within grace period
  20:51:17 ReconciliationSucceeded  Kustomization/infrastructure finished
  20:51:38 EvictionThresholdMet     "Attempting to reclaim ephemeral-storage"
  20:51:45 FailedDaemonPod          node-exporter DaemonSet — "will try to kill it"
  ```

Pods on worker3 after eviction:
  ```
  default    test-sched-1a       0/1  Unknown
  default    test-sched-1b       0/1  Completed
  default    test-sched-1c       0/1  Completed
  default    test-sched-2a       0/1  ContainerStatusUnknown
  kube-system  calico-node       1/1  Running           ← critical pod, protected
  kube-system  csi-nfs-node      3/3  Running           ← critical pod, protected
  kube-system  kube-proxy        1/1  Running           ← critical pod, protected
  monitoring   event-exporter    0/1  ContainerStatusUnknown
  monitoring   node-exporter     0/1  Evicted
  monitoring   loki-canary       0/1  Evicted
  monitoring   promtail          0/1  Evicted
  ```

Event exporter rescheduled to worker2:
  ```
  event-exporter-57769d9b74-xq7sz  1/1  Running  0  3m21s  k8s-worker2.lab.local
  ```

Node status — still Ready at this point:
  ```
  k8s-worker3.lab.local   Ready    <none>   37d   v1.35.3
  ```

Proxmox showed memory at 98.23% (6.88 GiB of 7.00 GiB) — disk
pressure cascaded into memory pressure.

Systemd state on worker3: degraded, 1 failed unit.

Kubelet stuck in eviction loop — only critical pods left:
  ```
  20:58:12 eviction_manager.go:392 "must evict pod(s) to reclaim" resourceName="ephemeral-storage"
  20:58:12 eviction_manager.go:410 "pods ranked for eviction" pods=["calico-node","csi-nfs-node","kube-proxy"]
  20:58:12 eviction_manager.go:616 "cannot evict a critical pod" pod="kube-system/calico-node-gtg6l"
  20:58:12 eviction_manager.go:616 "cannot evict a critical pod" pod="kube-system/csi-nfs-node-f4jgw"
  20:58:12 eviction_manager.go:616 "cannot evict a critical pod" pod="kube-system/kube-proxy-gxwm7"
  20:58:12 eviction_manager.go:444 "unable to evict any pods from the node"
  ```

Kubelet is stuck: it needs to reclaim space, the only pods left are
critical (kube-system), and it refuses to evict them. This loop
repeats every 10 seconds.

Eviction describe output:
  ```
  Warning  Evicted  kubelet  The node was low on resource: ephemeral-storage.
  Threshold quantity: 2727346284, available: 432908Ki. Container test-sched-1a
  was using 20Ki, request is 0, has larger consumption of ephemeral-storage.
  ```

Finding 3 — Monitoring blind spot:

I didn't receive any alert saying mem is high or disk usage high.
But i can understand this because the prom can't get any data from
worker3 — node-exporter got evicted first.

Disk pressure kills the monitoring agent first (node-exporter is a
DaemonSet, not a critical pod), which means the alert for "disk full"
can never fire because the thing that reports disk usage is already dead.

The fix: an absent metric alert — "alert when node-exporter stops
reporting for node X for more than Y minutes." Silence itself becomes
the signal.

_____________________________________________________________________

[Test 3 — Fill remaining 4% + reboot at 100%]

Action:
  ```
  dd if=/dev/zero of=/var/fill-disk3 bs=1M count=1000
  dd: error writing '/var/fill-disk3': No space left on device
  747+0 records in / 746+0 records out

  [root@k8s-worker3 var]# df -h /
  Filesystem           Size  Used Avail Use% Mounted on
  /dev/mapper/rl-root   17G   17G  236K 100% /
  ```

236 bytes left. Completely full. Rebooted.

Post-reboot — node booted but is a zombie:
  ```
  [root@k8s-worker3 ~]# df -h /
  /dev/mapper/rl-root   17G   17G   28K 100% /

  [root@k8s-worker3 ~]# touch /tmp/test-write
  touch: cannot touch '/tmp/test-write': No space left on device
  ```

Node booted because /boot is a separate partition (362M, not full) and
the kernel + systemd load into memory. But the OS is completely
non-functional — can't write to disk anywhere.

Kubelet crash-looping:
  ```
  Active: activating (auto-restart) (Result: exit-code) since Sun 2026-05-03 21:05:31
  Process: 1955 ExecStart=/usr/bin/kubelet (code=exited, status=1/FAILURE)
  ```

Root cause — containerd is dead:
  ```
  E0503 21:07:24 run.go:72 "command failed" err="failed to run Kubelet:
  validate service connection: validate CRI v1 runtime API for endpoint
  \"unix:///var/run/containerd/containerd.sock\": rpc error: code =
  Unimplemented desc = unknown service runtime.v1.RuntimeService"
  ```

Cascade: disk 100% → containerd can't start → kubelet can't connect
to CRI → kubelet crash-loops → node NotReady.

Cluster view:
  ```
  k8s-worker3.lab.local   NotReady   <none>   37d   v1.35.3
  ```

_____________________________________________________________________

[Recovery — Remediation Auto-Heal]

I deleted the fill files from worker3 before the remediation pod
triggered, but didn't get a chance to manually restart services.

The remediation pod detected worker3 NotReady and auto-rebooted it
via Proxmox API:

  ```
  --- Health check at 2026-05-03 18:09:20 UTC ---
  k8s-worker1.lab.local: Healthy
  k8s-worker2.lab.local: Healthy
  k8s-worker3.lab.local: UNHEALTHY! (Node NotReady)

  --- Remediating 1 unhealthy node(s) ---
  [Attempt 1] Remediating k8s-worker3.lab.local (VM 1022)
    -> VM 1022 status: running
    -> Rebooting VM 1022
    -> Alert sent: reboot - initiated
  ```

Proxmox task viewer confirmed: VM 1022 Reboot, task type qmreboot,
user k8s-pve@pve!remediation (API Token), duration 2s.

5 minutes later — recovery confirmed:
  ```
  --- Health check at 2026-05-03 18:14:21 UTC ---
  k8s-worker1.lab.local: Healthy
  k8s-worker2.lab.local: Healthy
  k8s-worker3.lab.local: Recovered! Resetting counter.
    -> Alert sent: recovery - node is healthy again
  ```

Because the fill files were deleted before the reboot, the node came
back with clean disk (24% used, 13 GiB free).

Post-recovery — all nodes Ready, DaemonSets recreated:
  ```
  kube-system   calico-node-gtg6l          1/1  Running  17 (5m29s ago)
  kube-system   csi-nfs-node-f4jgw         3/3  Running  51 (5m29s ago)
  kube-system   kube-proxy-gxwm7           1/1  Running  4  (5m29s ago)
  monitoring    node-exporter-78bvd        1/1  Running  0   5m19s
  monitoring    loki-canary-mmxm2          1/1  Running  0   5m19s
  monitoring    promtail-rjcr5             1/1  Running  0   5m19s
  ```

Stale orphaned pods from eviction (Unknown/ContainerStatusUnknown)
stayed until manually force-deleted — k8s doesn't auto-clean these.

Post-recovery disk state:
  ```
  [root@k8s-worker3 ~]# du -ah /var | sort -rh | head -10
  1.4G    /var
  1.3G    /var/lib
  1.2G    /var/lib/containerd
  837M    /var/lib/containerd/io.containerd.snapshotter.v1.overlayfs
  328M    /var/lib/containerd/io.containerd.content.v1.content
  ```

/var went from 9.5 GiB (pre-test) to 1.4 GiB — kubelet's image GC
in round 1 purged all cached images permanently.

_____________________________________________________________________

[Alerts Received]

Email 1 — Firing:
  alertname=RemediationAction, action=reboot, node=k8s-worker3.lab.local
  severity=warning
  "Self-healing action 'reboot' was performed on node k8s-worker3.lab.local.
  Result: initiated"

Email 1 — Resolved (same email):
  alertname=KubeNodeEviction, eviction_signal=imagefs.available
  alertname=KubeNodeEviction, eviction_signal=nodefs.available
  "Node k8s-worker3.lab.local is evicting Pods due to [imagefs/nodefs].available"

Email 2 — Recovery:
  alertname=RemediationAction, action=recovery, node=k8s-worker3.lab.local
  severity=info
  "Self-healing action 'recovery' was performed on node k8s-worker3.lab.local.
  Result: node is healthy again"

Email 2 — Resolved:
  Both KubeNodeEviction alerts resolved
  RemediationAction recovery resolved

Alert chain worked end-to-end: eviction → reboot → recovery → resolved.

What was missing: no alert for "disk is filling up" — node-exporter
dies before the threshold fires. Silence = no signal unless we add
an absent metric alert.

_____________________________________________________________________

[Findings]

1. Kubelet's first defense is image garbage collection — it purged ~30
   cached images (~3.5 GiB) and resolved disk pressure without evicting
   any pods. This is built-in resilience, but it's a one-shot defense.
   Once images are gone, there's nothing left to clean.

2. Kubelet evicts pods by priority — monitoring DaemonSets first
   (node-exporter, promtail, loki-canary), then app pods (WordPress,
   event-exporter), then test pods. kube-system critical pods
   (calico-node, csi-nfs-node, kube-proxy) are protected and will
   never be evicted even under disk pressure.

3. MONITORING BLIND SPOT: Node-exporter is evicted before the "disk
   full" alert can fire. The monitoring agent dies before it can
   report the condition it should alert on. Fix: absent metric alert
   ("node-exporter stopped reporting for >5 minutes").
   See: troubleshooting/kubernetes/reference/60-disk-full-monitoring-gaps.md

4. At 100% disk, the node boots but containerd can't start →
   kubelet crash-loops → node goes NotReady. The cascade:
   disk full → containerd dead → kubelet CRI failure → crash-loop →
   NotReady. Linux boots because /boot is separate, but the OS is
   non-functional (can't write to /tmp, can't create container
   sandboxes, can't write logs).

5. /var is not a separate partition in the golden image. /var eats
   73% of root disk (9.5 GiB of 13 GiB used). In production, /var
   should be its own partition so container growth can't kill the OS.
   See: troubleshooting/linux/6-var-not-separate-partition.md

6. Remediation auto-heal worked end-to-end — detected NotReady in
   the next 5-minute health check cycle, called Proxmox API qmreboot,
   node recovered in ~5 minutes total. BUT: if the fill files hadn't
   been deleted, the node would boot back at 100% → same crash-loop →
   remediation reboots again → infinite reboot loop. The remediation
   pod doesn't know WHY a node is NotReady — it just reboots it.

7. Event exporter (1 replica) was on worker3 and went down during
   eviction. New pod rescheduled to worker2, so event logging had a
   brief gap but not total loss. Scale to 2 replicas for HA.

8. Stale evicted pods (Unknown/ContainerStatusUnknown) don't auto-clean
   after node recovery. Need manual force-delete.

9. Disk pressure cascaded into memory pressure — Proxmox showed memory
   at 98.23% while disk was at 96%. The two pressure types compound.

_____________________________________________________________________

[Fixes To Apply]

| Fix | Priority | Ticket |
|-----|----------|--------|
| Separate /var partition in golden image | HIGH | TS-LNX-006 |
| Absent metric alert (node-exporter silence) | HIGH | TS-K8S-060 |
| Scale event-exporter to 2 replicas | MEDIUM | TS-K8S-060 |
| Add /var granular disk alerting | MEDIUM | TS-LNX-006 |
| Proxmox memory monitoring script | LOW | TS-PVE-022 |

_____________________________________________________________________

[Notes]

- API server and etcd showed zero impact throughout — worker node
  disk pressure is completely invisible to the control plane.
- Flux reconciliation continued working throughout all phases.
- WordPress was evicted from worker3 and rescheduled to another worker
  automatically (ReplicaSet created new pod).
- The test-sched pods with default priority 0 were evicted as expected.
- Need python script to monitor proxmox layer node abnormality like
  cpu, io already exist, add another one for mem, but it will be
  risky to let it take action — need to think about later.
- Why did the node survive at 100% disk? My first thought was that
  the 7 GiB RAM saved it — Linux "moved writes to memory" when disk
  was full, and since nothing was consuming memory it had room to
  survive. Wrong. Linux doesn't redirect disk writes to RAM. The node
  stayed alive because /run is tmpfs (memory-backed) — systemd could
  still write PID files and sockets there, so SSH and basic services
  kept working. The 98% memory Proxmox showed was mostly page cache
  (same misleading metric from TS-PVE-016), not disk-to-RAM fallback.
  That said, RAM size does matter indirectly: if this was a 1-1.5 GiB
  VM instead of 7 GiB, the tmpfs mounts would have less headroom and
  the node might not have stayed SSH-able. More RAM = more tmpfs room
  = more survivability. But containerd and kubelet died regardless
  because they write to /var (real disk), and no amount of RAM fixes
  that. The system was alive but k8s was dead.
  Why did Proxmox show 98% memory though? Suspect most of it was Linux
  page cache (same misleading metric from TS-PVE-016 — Linux caches
  file reads aggressively and Proxmox counts it as "used"). The rest
  could be real pressure from crash-looping services — kubelet restarting
  every few seconds, containerd failing to start, eviction manager
  running in a tight loop — all that churn consumes memory for process
  stacks and kernel buffers. Can't confirm the split without in-guest
  MemAvailable at the time, which we didn't have (node-exporter was
  already evicted).

_____________________________________________________________________

[References]
- troubleshooting/kubernetes/reference/60-disk-full-monitoring-gaps.md
- troubleshooting/linux/6-var-not-separate-partition.md
- troubleshooting/proxmox/reference/22-proxmox-memory-monitoring.md
- worker-2of3-down.md — remediation auto-recovery path comparison
- scheduler-failure-full-kill.md — event-exporter deployed after that test
