# TS-K8S-056 | 2026-04-30 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Container Runtime / Cgroup Configuration
Sub-techs: containerd v2.2.2, kubelet, cgroup drivers, systemd vs cgroupfs,
           runc, kubeadm, Rocky Linux 10, cgroup v2
Environment: DEV + PROD k8s clusters | 3 masters (kubeadm) + 3 workers each
Severity: MEDIUM
Discovered during: DR Test session — investigating TS-K8S-055 (apiserver-etcd
                   gRPC warnings), checking containerd config after a Google
                   search suggested cgroup mismatch as a possible cause
Related: TS-K8S-055 (apiserver-etcd gRPC warnings — may or may not be connected),
         TS-K8S-051 (worker1 rollout restart storm — potential past impact),
         TS-PVE-017 (Proxmox disk IO config — kept cluster stable during this fix)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Kubelet is configured with `cgroupDriver: systemd` but containerd is
using `SystemdCgroup = false` (cgroupfs). Two different cgroup managers
controlling the same cgroup tree on every node in both clusters.

Cluster has been running 34 days with this mismatch. No obvious crash,
but this is exactly the kind of issue that hides until the cluster is
under pressure.

_____________________________________________________________________

[Analysis]

# How I found it

Was investigating TS-K8S-055 (apiserver-to-etcd gRPC connection warnings).
Googled the error, one result mentioned checking containerd's
`SystemdCgroup` setting as a potential cause. Checked it and found the
mismatch.

# What is a cgroup driver and why does it matter

Linux cgroups control how resources (CPU, memory) are allocated and
limited for processes. There are two ways to manage the cgroup tree:

- **systemd** — systemd creates and manages the cgroup hierarchy.
  This is the modern standard on Rocky, Ubuntu 22+, any distro using
  cgroup v2. Kubelet tells systemd "create a cgroup here for this pod"
  and systemd owns the lifecycle.

- **cgroupfs** — the container runtime writes directly to the cgroup
  filesystem (`/sys/fs/cgroup/...`). Older approach, bypasses systemd
  entirely.

When kubelet uses systemd and containerd uses cgroupfs, you get two
managers operating on the same cgroup tree without knowing about each
other. Systemd creates cgroups in `slice:prefix:name` format.
cgroupfs creates them as filesystem paths like `/kubepods/burstable/pod.../`.

Under normal load, both work independently and things look fine. Under
pressure — memory exhaustion, high pod churn, node resource contention —
they can conflict:

- Systemd might clean up a cgroup it doesn't recognize (containerd
  created it directly)
- OOM killer decisions are based on inconsistent accounting
- Resource limits might not apply correctly
- Pod eviction decisions by kubelet use systemd's view, but actual
  usage tracked by cgroupfs is different

Kubernetes docs explicitly state: the cgroup driver must match between
kubelet and the container runtime.

# Evidence of the mismatch

```
[root@k8s-master1 ~]# cat /var/lib/kubelet/config.yaml | grep cgroupDriver
cgroupDriver: systemd

[root@k8s-master1 ~]# containerd config dump | grep SystemdCgroup
            SystemdCgroup = false
```

Rocky Linux 10 uses cgroup v2 with systemd as default manager.
Kubelet is correctly set to systemd. Containerd was left at its
default (cgroupfs) — likely missed during initial cluster setup.

# Why was this missed — the idempotency lock

Went to check my setup playbook (`k8s_setup.yml`) to see if I forgot
the fix. Found the fix was already there:

```yaml
- name: Generate containerd default config
  ansible.builtin.shell: |
    containerd config default > /etc/containerd/config.toml
  args:
    creates: /etc/containerd/config.toml

- name: Enable systemd cgroup driver
  ansible.builtin.replace:
    path: /etc/containerd/config.toml
    regexp: 'SystemdCgroup = false'
    replace: 'SystemdCgroup = true'
```

The playbook has the correct fix. But it never ran. Here's why:

`dnf install containerd.io` (the install step before this) ships a
minimal `/etc/containerd/config.toml` as part of the package:

```
disabled_plugins = ["cri"]
# (everything else commented out, no SystemdCgroup anywhere)
```

The next task — `containerd config default > /etc/containerd/config.toml` —
has `creates: /etc/containerd/config.toml`. This is an Ansible
idempotency guard: "only run if this file doesn't exist." But the
file already exists from the package install. So the full default
config (which contains `SystemdCgroup = false`) was never generated.

Then the `replace` task runs — searches for `SystemdCgroup = false`
in the minimal config. It's not there. Replace does nothing silently.

Tested this on a fresh LXC container to confirm:
```
[root@CT100 ~]# dnf install containerd.io -y
[root@CT100 ~]# cat /etc/containerd/config.toml
disabled_plugins = ["cri"]
# (minimal config, no SystemdCgroup)
```

Package creates the file first → `creates:` guard skips the full
config generation → replace has nothing to match → mismatch slips
through.

Fix: kept the `creates:` guard in place — it's not wrong, it prevents
the playbook from overwriting manual config customizations on re-runs.
The real issue was the `replace` task silently doing nothing when the
string wasn't in the file.

Replaced the `replace` task with `blockinfile` — this adds the
SystemdCgroup block to whatever config file exists (minimal or full),
instead of searching for a string that might not be there:

```yaml
- name: Enable systemd cgroup driver
  ansible.builtin.blockinfile:
    path: /etc/containerd/config.toml
    block: |
      [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
        SystemdCgroup = true
    marker: "# {mark} ANSIBLE MANAGED - SystemdCgroup"
  notify: Restart containerd
```

The marker wraps the block with `# BEGIN/END ANSIBLE MANAGED` comments
so Ansible knows what it owns — run the playbook 10 times, still one
block. Keeps manual changes outside the markers untouched.

# containerd v2 config structure

First attempt used the old containerd v1 config path:
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
```

This produced warnings — wrong path for containerd v2.2.2:
```
WARN Ignoring unknown key in TOML for plugin
error="strict mode: fields in the document are missing in the target struct"
key="containerd runtimes runc options" plugin=io.containerd.grpc.v1.cri
```

Correct path for containerd v2:
```toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = true
```

Found the correct path by checking the effective config:
```
[root@k8s-master1 ~]# containerd config dump | grep -B 20 SystemdCgroup
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
    ...
    SystemdCgroup = false
```

# Potential past impact — TS-K8S-051

TS-K8S-051: after a cluster-wide rollout restart, worker1 hit ~70% CPU
for 39 minutes. 14 pods all restarting simultaneously on 2 cores, calico
probes timing out, pod start times ballooning from seconds to minutes.

The cgroup mismatch could have made that worse than it needed to be.
Under that kind of pod churn pressure, inconsistent cgroup accounting
means CPU throttling decisions and pod priority enforcement are based
on wrong numbers. The 40-minute recovery time might have been shorter
with aligned cgroup drivers.

Doesn't prove the mismatch caused TS-K8S-051, but the conditions
match where this type of issue makes things worse.

_____________________________________________________________________

[Final Root Cause]
containerd's default `SystemdCgroup = false` was never changed during
initial cluster setup. Kubelet was correctly set to `systemd` by
kubeadm, but the containerd config step was missed. Every node in both
clusters has been running with mismatched cgroup drivers for 34 days.

_____________________________________________________________________

[Final Solution]

Add to `/etc/containerd/config.toml`:
```toml
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
  SystemdCgroup = true
```

Then restart both containerd and kubelet:
```bash
systemctl restart containerd
systemctl restart kubelet
```

Both restarts are needed:
- containerd restart → makes containerd use systemd cgroup driver
- kubelet restart → makes kubelet recreate pod sandboxes with systemd
  format cgroup paths (`slice:prefix:name`)

Without the kubelet restart, kubelet still sends old cgroupfs-format
paths (`/kubepods/burstable/pod.../...`) to containerd, which now
expects systemd format. runc throws:
```
expected cgroupsPath to be of format "slice:prefix:name" for systemd
cgroups, got "/kubepods/burstable/pod.../..." instead
```

# Rollout approach — dev cluster

One node at a time. Manual — not Ansible — because control plane
components restart and I need to verify between each node.

Masters: apply fix, restart containerd + kubelet, verify pods restart.
Other 2 masters hold quorum during the restart.

Workers: cordon → drain → apply fix → restart → uncordon. Workloads
move to other workers during the fix.

Order: master1 → master2 → master3 → worker1 → worker2

# Dev cluster progress

Master1 — DONE
- Applied config, restarted containerd
- Pods failed with "expected cgroupsPath to be of format slice:prefix:name"
- Restarted kubelet → pods recreated with correct cgroup paths
- All pods Running:
```
etcd-k8s-master1.lab.local                      1/1     Running
kube-apiserver-k8s-master1.lab.local            1/1     Running
kube-controller-manager-k8s-master1.lab.local   1/1     Running
kube-scheduler-k8s-master1.lab.local            1/1     Running
```
- Verified: `containerd config dump | grep SystemdCgroup` → true

Master2 — DONE
Master3 — DONE

Worker1 — DONE (with drain)
- Cordoned and drained worker1 before applying fix
- Drain evicted: wordpress, notification-controller, source-controller,
  ingress-nginx, csi-nfs-controller, metrics-server, grafana, prometheus
- DaemonSets (calico-node, csi-nfs-node, kube-proxy, node-exporter,
  loki-canary, promtail) stayed on worker1 as expected
- Several pods went Pending — worker2 couldn't absorb everything:
  wordpress, notification-controller, csi-nfs-controller, metrics-server
- Worker2 under pressure: 25% CPU, 78% memory (normally ~10% CPU)
- Worker1 idle at 3% CPU, 44% memory with only DaemonSets
- Applied fix, restarted containerd + kubelet, uncordoned
- Pending pods scheduled back to worker1

Finding: 2-worker dev cluster cannot survive a full single-worker drain.
Worker2 (4GB) doesn't have enough resources to run both workers' workloads.
Good to know before planning DR eviction tests.

During the drain, worker2 struggled — some pods bounced between
absorbing and crashing. Evidence after uncordoning worker1:

```
csi-nfs-controller on worker2:  3/5  Error  45 restarts
source-controller on worker2:   0/1  Running  3 restarts
helm-controller on worker2:     1/1  Running  23 restarts
kustomize-controller:           1/1  Running  21 restarts
kube-state-metrics:             1/1  Running  25 restarts
prometheus-operator:            1/1  Running  16 restarts
```

Worker2 metrics went unknown during the pressure (`kubectl top` showed
`<unknown>`) — metrics-server couldn't scrape it. After worker1 came
back online and took its pods back, worker2 was still settling.

Worker1 after uncordon: 5% CPU, 59% memory — healthy, absorbing pods
back normally.

The full eviction/drain test will be done properly on the prod cluster
later — prod has 3 workers with more resources, which gives a more
realistic test of whether the cluster can survive a single-worker drain
under normal conditions. Dev's 2 workers with 4GB each is too tight
for meaningful drain testing.

Note on IO impact: the drain + mass pod reschedule on dev caused the
Proxmox host to hit ~30% IO delay — the known limitation from the
physical host's disk throughput. The IO limits from TS-PVE-017 kept
the delay capped at a manageable level instead of cascading into a
full IO storm. Without those limits from the earlier fix, this
operation could have triggered the same kind of cascade we saw before.
The IO watchdog (TS-PVE-017) earned its keep here.

Worker2 — DONE (direct restart, no drain)
- Applied fix directly since worker1 was back and healthy
- containerd + kubelet restart caused the usual pod bounce
- Worker2 hit 22% CPU during restart settling, Proxmox host IO spiked
  to ~35% avg during the worker1 drain, dropped to ~30% after worker2
  restart but never fully settled — IO stayed elevated (~30%) for an
  extended period. Host and cluster stayed functional throughout but
  the IO pressure was noticeable. The IO limits from TS-PVE-017 kept
  it from cascading into a full storm, but this operation hit the host
  harder than expected.
- All pods back to Running after stabilization

Dev cluster: ALL NODES FIXED (config applied, restarts done)

Ansible playbook run against dev to re-apply config with markers:
- worker2: SSH timed out — IO pressure from the earlier operations
  made SSH unresponsive despite the node being functional. IO dropped
  from 50% to 30% but stayed elevated.
- worker3: unreachable (shutdown — expected, not part of active cluster)
  needs to be booted, config applied, then shut back down to avoid drift.
- master1, master2, master3, worker1: playbook applied successfully

Post-fix node status:
```
k8s-master1.lab.local   Ready   4% CPU    73% mem
k8s-master2.lab.local   Ready   4% CPU    71% mem
k8s-master3.lab.local   Ready   4% CPU    65% mem
k8s-worker1.lab.local   Ready   4% CPU    60% mem
k8s-worker2.lab.local   Ready   22% CPU   69% mem  (settling from restart)
```

# Prod cluster progress

Created a separate playbook (`update-containerd-config.yml`) to push
the config change via Ansible — same `blockinfile` with markers. The
config update is identical across all nodes, no reason to edit it
manually 6 times.

The restart stays manual — one node at a time, verify between each.
Ansible pushes config, I restart and watch.

Before running the playbook, I'll clean up the dev nodes first —
remove the manually added block (which has no Ansible markers) and
let the playbook re-add it with proper markers. No impact since
containerd already knows the config from the earlier restart. This
keeps all nodes — dev and prod — consistent with the same Ansible-
managed block. No drift between "manually fixed" and "playbook fixed."

# Dev cluster — remaining cleanup

Playbook couldn't reach worker2 (SSH timed out — IO still at 30%,
never settled) and worker3 (shutdown, expected). The manual fix is
already applied on both active nodes but without Ansible markers —
need the playbook to run clean so all nodes are consistent.

Plan: shutdown the dev cluster, boot worker2 and worker3, run the
playbook against them, shutdown worker3 again, then bring the cluster
back up. Quick cycle — the config change doesn't need containerd
running, just the file written.

# The IO reality on dev

The hardware limitation on dev is undeniable. We survived the host
with the fixes from TS-PVE-017 — kept the cluster responsive, kubectl
worked with delay — but can't deny the IO situation. If a storm starts
in a different way than what the `io-storm.sh` script in the proxmox
folder watches for, we're exposed. This situation was caused by pod
bounce across workers, not a specific condition the watchdog tracks.
So it sadly can't be automatically solved.

The IO watchdog handles what it was built for — runaway VMs and the
known cascade patterns. But this situation was caused by pod bounce,
not a specific condition the script tracks. Can't write a rule for
"legitimate cluster operation that just happens to hammer the disk."
It's sadly not something that can be automatically solved.

We just survived the host. That's about it.

# Prod cluster progress

Config pushed to all prod nodes via `update-containerd-config.yml`
playbook. Rolling restart — one node at a time with verification.

Monitored the cluster during restarts using Loki:
```
{namespace="kube-system"} |~ "error|Error|failed|Failed"
```

Watched the error stream throughout — only the known pre-existing
errors appeared:
- TS-K8S-055 gRPC apiserver-etcd warnings (suspended, not addressing now)
- VolumeSnapshotClass/Content CRD watch failures (CSI snapshotter, pre-existing)

No new errors from the cgroup fix restarts. Cluster stayed stable.

Master1 — DONE
Master2 — DONE
Master3 — DONE

Worker1 — DONE (with drain — proper eviction test)

This is the drain test that dev couldn't give us. Dev has 2 workers
with 4GB each — draining one crushed the other (worker2 bounced pods,
csi-nfs-controller errored, metrics-server went unknown, 78% memory).
Prod has 3 workers with real resources — this is the meaningful test.

Cordon + drain worker1. Drain evicted all non-DaemonSet workloads.
DaemonSets stayed on worker1 as expected (calico-node, csi-nfs-node,
kube-proxy, node-exporter, loki-canary, promtail).

Workloads distributed cleanly across worker2 and worker3:
```
worker2 absorbed:
  wordpress replica         — Running
  kustomize-controller      — Running
  notification-controller   — Running
  ingress-nginx (2 replicas)— Running
  csi-nfs-controller        — Running
  metrics-server replica    — Running
  prometheus-operator       — Running
  prometheus                — Running
  loki                      — Running
  mariadb                   — Running

worker3 absorbed:
  wordpress (2 replicas)    — Running
  helm-controller           — Running
  source-controller         — Running
  ingress-nginx replica     — Running
  csi-nfs-controller replica— Running
  metrics-server replica    — Running
  grafana                   — Running
  kube-state-metrics        — Running
  calico-kube-controllers   — Running
  python-lab                — Running
```

All pods Running. No Pending. No crashes. No restarts from the drain.
No memory pressure on either absorbing worker. Night and day compared
to the dev drain where worker2 nearly fell over.

Applied fix on worker1 (containerd + kubelet restart), uncordoned.
Pods scheduled back normally.

Worker2 — DONE (with drain)

Drained worker2. Eviction was smooth — worker1 (freshly uncordoned,
almost idle at 1% CPU) and worker3 split the load cleanly:

```
worker1 absorbed:
  wordpress replica           — Running
  mariadb                     — Running
  kustomize-controller        — Running
  notification-controller     — Running
  ingress-nginx (2 replicas)  — Running
  csi-nfs-controller          — Running
  metrics-server replica      — Running
  prometheus-operator         — Running
  prometheus                  — Running
  loki                        — Running

worker3 absorbed (already had):
  wordpress (2 replicas)      — Running
  helm-controller             — Running
  source-controller           — Running
  ingress-nginx replica       — Running
  csi-nfs-controller replica  — Running
  metrics-server replica      — Running
  grafana                     — Running
  kube-state-metrics          — Running
  calico-kube-controllers     — Running
  python-lab                  — Running
```

All pods Running within seconds. Zero Pending. Zero crashes. The
eviction was so smooth it's almost boring — which is exactly what you
want. Compare this to the dev drain where worker2 was bouncing pods,
csi-nfs erroring out at 3/5, metrics going unknown, 78% memory, and
the whole thing took 40 minutes to settle.

A cluster on good hardware is much healthier for the mind to work
with rather than this sad dev server. On dev I'm babysitting the
host the whole time — watching IO, waiting for SSH to respond,
hoping pods don't bounce. On prod, drain a node and move on.
That's it. That's the difference.

IO impact comparison — prod host hit 0.35% IO during the drain
operation. Dev host hit 35-55% doing the same thing. Two orders of
magnitude difference for the same operation. The dev hardware is
the bottleneck, not the workload.

Restarts pushed via Ansible ad-hoc instead of SSH login/logout per node:
```bash
ansible -i inventory/inventory.ini <hostname> -m shell -a "systemctl restart containerd && systemctl restart kubelet" -b
```

Worker3 — DONE (with drain)

Same smooth eviction as worker2 — worker1 and worker2 absorbed
the load, all pods Running, no pressure.

Prod cluster: ALL NODES FIXED
- Config pushed via `update-containerd-config.yml` playbook
- Rolling restarts with cordon/drain for workers
- Loki monitored throughout — no new errors
- All nodes verified: `containerd config dump | grep SystemdCgroup` → true

_____________________________________________________________________

[Risk Level] MEDIUM

The mismatch has been running for 34 days without catastrophic failure.
But under resource pressure (memory exhaustion, mass pod restarts, DR
tests), the dual-manager conflict can cause unpredictable behavior:
wrong pods evicted, incorrect resource limits, longer recovery times.

Fix requires restarting containerd + kubelet per node, which restarts
all containers on that node. Rolling approach keeps cluster available
throughout.

_____________________________________________________________________

[References]
- TS-K8S-055 — apiserver-etcd gRPC warnings (found this while investigating that)
- TS-K8S-051 — worker1 rollout restart storm (potential past impact from this mismatch)
- TS-PVE-017 — Proxmox disk IO config (IO limits kept cluster stable during drain operation)
- k8s docs: container runtime must use same cgroup driver as kubelet
- containerd v2 config: `plugins.'io.containerd.cri.v1.runtime'` (not v1 `io.containerd.grpc.v1.cri`)
- ansible/dev/playbooks/k8s/k8s_setup.yml — playbook fix (kept `creates:` guard, switched `replace` to `blockinfile`)
- ansible/prod/playbooks/k8s/k8s_setup.yml — mirrored same fix from dev
- ansible/dev/playbooks/k8s/update-containerd-config.yml — standalone playbook for pushing SystemdCgroup config
- ansible/prod/playbooks/k8s/update-containerd-config.yml — mirrored from dev
- Verified root cause on fresh LXC: `dnf install containerd.io` creates minimal config before playbook runs
- Versions: containerd v2.2.2, k8s v1.35.3, Rocky Linux 10
