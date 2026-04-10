# TS-K8S-002 | 2026-03-28 | RESOLVED

## 1. Context
- System: Calico CNI / BGP Peering / Multi-NIC Configuration
- Environment: k8s-dev cluster (also applied to prod)
- Related components: Calico DaemonSet, Worker nodes with dual NICs, NFS storage network
- Discovered during: Testing nginx deployment with NFS persistent storage
- Related: Case 3 (NFS Hard Mount), Case 4-5, Case 6 (NFS Storage Guide)

**Network Topology:**
```
Masters: 10.0.61.x (K8s network only)
         │
         │ BGP works (same L3 reachability)
         ↓
Workers: eth0: 10.0.64.x (K8s network) <-- BGP should use this
         eth1: 10.0.40.x (Storage network) <-- BGP was using this (WRONG)
```

## 2. Issue
- Symptom: Master nodes could not reach pod network on worker nodes
- Error: BGP peering via wrong interface (eth1/10.0.40.x storage network instead of eth0/10.0.64.x K8s network)
- Impact: Pods unreachable from master nodes; ClusterIP services timeout

**How Issue Was Discovered:**

While testing a new nginx deployment with NFS persistent storage:

```bash
# Deployed nginx-test with 3 replicas in testing namespace
kubectl get pods -n testing -o wide
# NAME                        IP              NODE
# nginx-test-f7454685-95llg   10.244.207.69   k8s-worker2
# nginx-test-f7454685-gnkpl   10.244.29.136   k8s-worker3
# nginx-test-f7454685-l8bv6   10.244.62.31    k8s-worker1
```

External NodePort access worked:
```bash
curl http://10.0.64.12:30080/
# Hello from NFS!  <-- WORKS
```

But master node could not reach pods directly:
```bash
curl http://10.244.207.69:80
# ^C (timeout, no response)

ping 10.244.207.69
# 3 packets transmitted, 0 received, 100% packet loss
```

**Symptom Matrix:**

| Test | Expected | Actual |
|------|----------|--------|
| External -> NodePort | Work | WORKS |
| Pod -> Service DNS | Work | WORKS |
| Master -> ClusterIP | Work | TIMEOUT |
| Master -> Pod IP | Work | TIMEOUT |
| Master -> localhost:30080 | Work | TIMEOUT |

## 3. Analysis

### Step 1: Check IP Routes on Master

```bash
[root@k8s-master1 ~]# ip route | grep 10.244
10.244.14.128/26 via 10.0.61.11 dev tunl0 proto bird onlink
10.244.25.192/26 via 10.0.61.12 dev tunl0 proto bird onlink
blackhole 10.244.43.128/26 proto bird
10.244.43.136 dev cali6b2a024016f scope link
```

**Finding:** Routes only exist to other master nodes (10.0.61.x), NOT to worker nodes.

Missing routes for:
- 10.244.62.x (worker1 pods)
- 10.244.207.x (worker2 pods)
- 10.244.29.x (worker3 pods)

---

### Step 2: Check Calico IPPool Configuration

```bash
[root@k8s-master1 ~]# kubectl get ippool -o yaml
spec:
  ipipMode: Always      # Correct - IP-in-IP enabled
  vxlanMode: Never
  cidr: 10.244.0.0/16
```

**Finding:** IPPool config is correct. Issue is not tunnel mode.

---

### Step 3: Install Calicoctl for Deeper Investigation

```bash
curl -L https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-amd64 -o /usr/local/bin/calicoctl
chmod +x /usr/local/bin/calicoctl
```

---

### Step 4: Check BGP Peering Status (KEY DISCOVERY)

```bash
[root@k8s-master1 ~]# calicoctl node status
Calico process is running.

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

**ROOT CAUSE FOUND:**

Workers peering via WRONG interface:
- 10.0.40.201 (worker1 eth1 - storage network) - WRONG
- 10.0.40.202 (worker2 eth1 - storage network) - WRONG
- 10.0.40.203 (worker3 eth1 - storage network) - WRONG

Should be:
- 10.0.64.10 (worker1 eth0 - K8s network)
- 10.0.64.11 (worker2 eth0 - K8s network)
- 10.0.64.12 (worker3 eth0 - K8s network)

---

### Step 5: Verify Worker Network Interfaces

```bash
[root@k8s-worker1 ~]# ip a
eth0: 10.0.64.10/24   <-- K8s network (correct for BGP)
eth1: 10.0.40.201/24  <-- Storage/NFS network (wrong for BGP)
tunl0: 10.244.62.0/32 <-- Pod network tunnel
```

---

### Step 6: Check Current IP Autodetection Setting

```bash
[root@k8s-master1 ~]# kubectl get daemonset calico-node -n kube-system -o yaml | grep -A2 IP_AUTODETECTION
[root@k8s-master1 ~]#   <-- EMPTY - no autodetection configured!
```

**Finding:** No IP_AUTODETECTION_METHOD set. Calico using default `first-found` which picked eth1 (wrong interface).

## 4. Root Cause

### Why This Wasn't an Issue Initially

When the cluster was first built, worker nodes had **only one network interface** (eth0 - K8s network). Calico's default IP autodetection worked perfectly because there was only one interface to choose from.

**The issue only appeared after adding a second interface for NFS storage access.**

### Timeline of Events:

1. **Initial cluster setup (Day 1):** Workers had only eth0 (10.0.64.x)
2. **Calico installed:** Default autodetection found eth0 correctly - NO ISSUES
3. **Cluster worked fine** for initial period
4. **Infrastructure change:** Added eth1 (10.0.40.x) on workers for direct NFS storage access
5. **After adding eth1:** Calico pods restarted and `first-found` autodetection picked eth1 instead of eth0
6. **Issue discovered today:** While testing nginx deployment with PVC, noticed master couldn't reach pod network
7. **Result:** BGP peering failed between masters (10.0.61.x) and workers (10.0.40.x) because:
   - Different subnets with no L3 route for BGP
   - Storage VLAN (10.0.40.x) not meant for K8s traffic

### Why Calico Picked Wrong Interface:

Calico's default `IP_AUTODETECTION_METHOD=first-found` iterates through interfaces and picks the first valid non-local IP. After adding eth1, interface enumeration order changed, causing eth1 (10.0.40.x) to be selected.

## 5. Solution

### Step 1: Configure IP Autodetection Method

```bash
[root@k8s-master1 ~]# kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD="cidr=10.0.64.0/24,10.0.61.0/24"
daemonset.apps/calico-node env updated
```

This tells Calico: "Only use IPs from 10.0.64.0/24 (workers) or 10.0.61.0/24 (masters)"

### Step 2: Wait for Rollout

```bash
[root@k8s-master1 ~]# kubectl rollout status daemonset/calico-node -n kube-system
Waiting for daemon set "calico-node" rollout to finish: 1 out of 6 new pods have been updated...
Waiting for daemon set "calico-node" rollout to finish: 2 out of 6 new pods have been updated...
Waiting for daemon set "calico-node" rollout to finish: 3 out of 6 new pods have been updated...
Waiting for daemon set "calico-node" rollout to finish: 4 out of 6 new pods have been updated...
Waiting for daemon set "calico-node" rollout to finish: 5 out of 6 new pods have been updated...
Waiting for daemon set "calico-node" rollout to finish: 5 of 6 updated pods are available...
daemon set "calico-node" successfully rolled out
```

### Step 3: Verify BGP Peering Fixed

```bash
[root@k8s-master1 ~]# calicoctl node status
Calico process is running.

IPv4 BGP status
+--------------+-------------------+-------+----------+-------------+
| PEER ADDRESS |     PEER TYPE     | STATE |  SINCE   |    INFO     |
+--------------+-------------------+-------+----------+-------------+
| 10.0.61.11   | node-to-node mesh | up    | 18:05:08 | Established |
| 10.0.61.12   | node-to-node mesh | up    | 18:05:43 | Established |
| 10.0.64.12   | node-to-node mesh | up    | 18:05:08 | Established |
| 10.0.64.11   | node-to-node mesh | up    | 18:06:18 | Established |
| 10.0.64.10   | node-to-node mesh | up    | 18:06:46 | Established |
+--------------+-------------------+-------+----------+-------------+

Also Repeat for Prod
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

All peers now on CORRECT interfaces (10.0.64.x for workers).

### Step 4: Verify Pod Connectivity

```bash
[root@k8s-master1 ~]# curl http://10.244.207.69:80
Hello from NFS!
```

Master can now reach pod network directly.

### Prevention Measures Implemented

**Updated Cluster Init Playbook:**

File: `ansible/dev/playbooks/k8s/k8s_init.yml`

Added after Calico apply:

```yaml
    - name: Config IP Autodetection for multi-NIC nodes
      ansible.builtin.command:
        cmd: kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD="cidr=10.0.64.0/24,10.0.61.0/24"

    - name: Install Calico Ctl
      ansible.builtin.get_url:
        url: https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-amd64
        dest: /usr/local/bin/calicoctl
        mode: '0755'
```

**Created Quick-Fix Playbook:**

File: `ansible/dev/playbooks/k8s/calicoctl.yml`

```yaml
---
- name: Setup Calico Ctl tool on all k8s_masters
  hosts: k8s_masters
  become: yes
  tasks:
    - name: Install Calico Ctl
      ansible.builtin.get_url:
        url: https://github.com/projectcalico/calico/releases/latest/download/calicoctl-linux-amd64
        dest: /usr/local/bin/calicoctl
        mode: '0755'
```

Same playbook mirrored to prod: `ansible/prod/playbooks/k8s/calicoctl.yml`

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Calico DaemonSet restart causes brief pod network disruption (~30s per node during rolling update)

## 7. Impact After Fix
- Observed: All BGP peers established on correct interfaces
- Master nodes can reach pod IPs directly
- ClusterIP services working correctly
- Fix applied to both dev and prod clusters

## 8. Notes

### Verification Commands

Use these to verify Calico health after any network changes:

```bash
# Check BGP peer status
calicoctl node status

# Check IP autodetection is set
kubectl get daemonset calico-node -n kube-system -o yaml | grep -A2 IP_AUTODETECTION

# Check routes to all pod subnets
ip route | grep 10.244

# Test pod connectivity from master
kubectl get pods -A -o wide | head -5
curl http://<POD_IP>:<PORT>
```

### Lessons Learned

1. **Always set IP_AUTODETECTION_METHOD** when nodes have multiple NICs
2. **Test pod connectivity from masters** after infrastructure changes
3. **Install calicoctl** on masters for BGP debugging
4. **Document network topology** - which interface for which purpose

### Related Files

- `ansible/dev/playbooks/k8s/k8s_init.yml` - Cluster init with Calico config
- `ansible/dev/playbooks/k8s/calicoctl.yml` - Calicoctl install playbook
- `ansible/prod/playbooks/k8s/calicoctl.yml` - Prod mirror
- `kubernetes/dev/deployments/apps/testing/nginx-test.yml` - Test deployment used to discover issue

### References

- Calico IP Autodetection: https://docs.tigera.io/calico/latest/networking/ipam/ip-autodetection
- Calico BGP: https://docs.tigera.io/calico/latest/networking/configuring/bgp

## 9. Workaround (if any)
> Temporarily use NodePort access instead of direct pod IP access. Not recommended - fix the IP autodetection instead.
