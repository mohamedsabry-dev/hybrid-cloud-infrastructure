# TS-K8S-002 | 2026-03-28 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / Calico CNI / BGP Peering
Sub-techs: IP autodetection, multi-NIC, BGP mesh, IPIP tunnel, calicoctl
Environment: DEV & Prod k8s clusters | Calico v3.27.0
Discovered during: Testing nginx deployment with NFS persistent storage
Related: TS-K8S-003 (NFS hard mount), TS-K8S-004-005, TS-K8S-006 (NFS storage guide)
Re-opened: No

_____________________________________________________________________

[Issue Description]
While testing a new nginx deployment with NFS storage, I noticed master nodes couldn't
reach pod IPs on workers. External NodePort access worked fine, pod-to-pod worked fine,
but anything originating from a master to a pod IP on a worker timed out.

```
Masters: 10.0.61.x (K8s network only)
         │
         │ BGP works (same L3 reachability)
         ↓
Workers: eth0: 10.0.64.x (K8s network) ← BGP should use this
         eth1: 10.0.40.x (Storage network) ← BGP was using this (WRONG)
```

How I spotted it — NodePort worked but direct pod IP didn't:

```
curl http://10.0.64.12:30080/    → Hello from NFS!     (WORKS)
curl http://10.244.207.69:80     → ^C (timeout)         (BROKEN)
ping 10.244.207.69               → 100% packet loss     (BROKEN)
```

_____________________________________________________________________

[Analysis]

# Step 1: Check IP routes on master

Command: ip route | grep 10.244

Output:
```
10.244.14.128/26 via 10.0.61.11 dev tunl0 proto bird onlink
10.244.25.192/26 via 10.0.61.12 dev tunl0 proto bird onlink
blackhole 10.244.43.128/26 proto bird
10.244.43.136 dev cali6b2a024016f scope link
```

Routes only exist to other master nodes (10.0.61.x). No routes to worker pod
subnets (10.244.62.x, 10.244.207.x, 10.244.29.x). BGP isn't exchanging routes
with workers.

# Step 2: Verify IPPool config is correct

Command: kubectl get ippool -o yaml

Output:
```
spec:
  ipipMode: Always
  vxlanMode: Never
  cidr: 10.244.0.0/16
```

IPPool is fine. Tunnel mode is correct. Problem is somewhere else.

# Step 3: Install calicoctl for BGP debugging

```
curl -L https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-amd64 -o /usr/local/bin/calicoctl
chmod +x /usr/local/bin/calicoctl
```

# Step 4: Check BGP peering status — found the root cause

Command: calicoctl node status

Output:
```
IPv4 BGP status
+--------------+-------------------+-------+----------+-------------+
| PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+--------------+-------------------+-------+----------+-------------+
| 10.0.61.11   | node-to-node mesh | up    | 17:47:22 | Established |
| 10.0.61.12   | node-to-node mesh | up    | 17:46:46 | Established |
| 10.0.40.201  | node-to-node mesh | start | 17:45:35 | Connect     |
| 10.0.40.202  | node-to-node mesh | start | 17:45:35 | Connect     |
| 10.0.40.203  | node-to-node mesh | start | 17:45:35 | Connect     |
+--------------+-------------------+-------+----------+-------------+
```

There it is. Workers are peering via 10.0.40.x (storage network) instead of
10.0.64.x (K8s network). The BGP sessions are stuck in "Connect" because
masters (10.0.61.x) have no route to the storage VLAN (10.0.40.x) — they're
on different L3 segments with no cross-route.

# Step 5: Confirm worker interfaces

Command: ip a (on worker1)

Output:
```
eth0: 10.0.64.10/24   ← K8s network (correct for BGP)
eth1: 10.0.40.201/24  ← Storage/NFS network (wrong for BGP)
tunl0: 10.244.62.0/32 ← Pod network tunnel
```

# Step 6: Check IP autodetection setting

Command: kubectl get daemonset calico-node -n kube-system -o yaml | grep -A2 IP_AUTODETECTION

Output: (empty — no autodetection configured)

No IP_AUTODETECTION_METHOD set. Calico was using the default `first-found`, which
picked eth1 (storage network) instead of eth0 (K8s network).

_____________________________________________________________________

[Final Root Cause]
When the cluster was first built, workers had only one NIC (eth0 — K8s network).
Calico's default `first-found` autodetection worked perfectly because there was
only one interface to choose from.

I later added eth1 (10.0.40.x) on workers for direct NFS storage access. After
that change, Calico pods restarted and `first-found` picked eth1 instead of eth0.
BGP peering broke because masters (10.0.61.x) couldn't reach the storage VLAN
(10.0.40.x) — different L3 segments, no route between them.

The issue was invisible until I tested something that required master-to-pod
connectivity (direct pod IP curl). NodePort and pod-to-pod traffic worked fine
because they don't depend on BGP peering from the master side.

_____________________________________________________________________

[Final Solution]

# Step 1: Set explicit IP autodetection

Command: kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD="cidr=10.0.64.0/24,10.0.61.0/24"

This tells Calico: only use IPs from the K8s network (workers 10.0.64.x, masters 10.0.61.x).

# Step 2: Wait for rollout

```
kubectl rollout status daemonset/calico-node -n kube-system
Waiting for daemon set "calico-node" rollout to finish: 1 out of 6 new pods have been updated...
...
daemon set "calico-node" successfully rolled out
```

# Step 3: Verify BGP peering fixed

Command: calicoctl node status

Output (dev):
```
+--------------+-------------------+-------+----------+-------------+
| PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+--------------+-------------------+-------+----------+-------------+
| 10.0.61.11   | node-to-node mesh | up    | 18:05:08 | Established |
| 10.0.61.12   | node-to-node mesh | up    | 18:05:43 | Established |
| 10.0.64.12   | node-to-node mesh | up    | 18:05:08 | Established |
| 10.0.64.11   | node-to-node mesh | up    | 18:06:18 | Established |
| 10.0.64.10   | node-to-node mesh | up    | 18:06:46 | Established |
+--------------+-------------------+-------+----------+-------------+
```

Output (prod — applied same fix):
```
+--------------+-------------------+-------+----------+-------------+
| PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+--------------+-------------------+-------+----------+-------------+
| 10.0.51.10   | node-to-node mesh | up    | 18:32:41 | Established |
| 10.0.51.12   | node-to-node mesh | up    | 18:32:39 | Established |
| 10.0.54.10   | node-to-node mesh | up    | 18:32:41 | Established |
| 10.0.54.11   | node-to-node mesh | up    | 18:32:40 | Established |
| 10.0.54.12   | node-to-node mesh | up    | 18:32:40 | Established |
+--------------+-------------------+-------+----------+-------------+
```

All peers on correct interfaces. All sessions Established.

# Step 4: Verify pod connectivity

Command: curl http://10.244.207.69:80

Output: Hello from NFS!

# Prevention: updated cluster init playbook

Added IP autodetection config to `ansible/{dev,prod}/playbooks/k8s/k8s_init.yml`
right after Calico apply, so any future cluster rebuild gets it automatically:

```yaml
- name: Config IP Autodetection for multi-NIC nodes
  ansible.builtin.command:
    cmd: kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD="cidr=10.0.64.0/24,10.0.61.0/24"
```

Also created a standalone `calicoctl.yml` playbook for installing calicoctl on
masters (both dev and prod).

Verified: Yes — both clusters, all BGP sessions Established on correct interfaces.

_____________________________________________________________________

[Risk Level] LOW

DaemonSet restart causes brief pod network disruption (~30s per node during rolling
update), but the fix is straightforward and the alternative (broken BGP) is worse.

_____________________________________________________________________

[References]
- ansible/{dev,prod}/playbooks/k8s/k8s_init.yml — cluster init with Calico autodetection
- ansible/{dev,prod}/playbooks/k8s/calicoctl.yml — calicoctl install playbook
- TS-K8S-003 — NFS hard mount issue (discovered in same testing session)
