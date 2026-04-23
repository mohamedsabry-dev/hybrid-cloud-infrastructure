# ETCD Single Node Failure & Recovery
# Date: 2026-04-11
# Result: PASS

---

## Scope

Test etcd cluster resilience when one master loses etcd.
Verify cluster survives with 2/3 quorum.
Test recovery via cluster sync (not S3 restore).

---

## Test A: Stop etcd Static Pod (Quorum Test)

**Test Time:** 2026-04-11 16:36

> **Note:** In kubeadm clusters, etcd runs as a static pod (not systemd service). To stop it, move the manifest file instead of using systemctl.

### Step 1: Pre-test cluster health

```bash
[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
d52dc5d621c3892f, started, k8s-master3.lab.local, https://10.0.61.12:2380, https://10.0.61.12:2379, false
```

**Member IDs:**
- master1: 2699402e05a84d4b (10.0.61.10)
- master2: 4c17d04fdb863468 (10.0.61.11)
- master3: d52dc5d621c3892f (10.0.61.12) <- TARGET

### Step 2: Stop etcd on master3

```bash
[k8s_admin@k8s-master3 ~]$ sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
```

### Step 3: Verify cluster survives with 2/3 quorum

```bash
[root@k8s-master1 ~]# etcdctl endpoint health --cluster
https://10.0.61.11:2379 is healthy: successfully committed proposal: took = 8.443437ms
https://10.0.61.10:2379 is healthy: successfully committed proposal: took = 7.932162ms
https://10.0.61.12:2379 is unhealthy: failed to commit proposal: context deadline exceeded
Error: unhealthy cluster

[root@k8s-master1 ~]# kubectl get nodes
NAME                    STATUS     ROLES           AGE   VERSION
k8s-master1.lab.local   Ready      control-plane   15d   v1.35.3
k8s-master2.lab.local   Ready      control-plane   15d   v1.35.3
k8s-master3.lab.local   NotReady   control-plane   15d   v1.35.3
k8s-worker1.lab.local   Ready      <none>          15d   v1.35.3
k8s-worker2.lab.local   Ready      <none>          15d   v1.35.3
k8s-worker3.lab.local   Ready      <none>          15d   v1.35.3
```

**Observations:**
- etcd quorum maintained (2/3 nodes = majority)
- master3 shows NotReady (expected - lost API server connectivity to local etcd)
- Workers briefly showed NotReady during failover (~5 seconds), then self-healed
- kubectl commands continue working (cluster operational)

### Resource Impact on Surviving Masters

| Node | Memory Before | Memory During | Delta |
|------|---------------|---------------|-------|
| master1 | ~80% | 88.76% (2.22/2.50 GiB) | +8% |
| master2 | ~80% | 87.96% (2.20/2.50 GiB) | +8% |
| master3 | ~80% | 81.10% (2.03/2.50 GiB) | -etcd stopped |

**Key Finding:** Surviving masters absorbed load from failed node, causing memory spike from ~80% to ~88%. In production, ensure masters have headroom for failover scenarios.

### Side Effects Observed

- kubectl commands had brief delay (~2-3s) during failover
- Flux kustomize-controller re-acquired leader lease
- Grafana storage migrations triggered on pod restart
- Loki rejected old log entries (>3h behind - normal after restart)

### Step 4: Restore etcd on master3

```bash
[k8s_admin@k8s-master3 ~]$ sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

**Result:** CLUSTER SURVIVED with 2/3 etcd nodes. Quorum maintained, workloads continued.

---

## Test B: Delete etcd Data (Manual Recovery via Cluster Sync)

> **Note:** This tests single-node recovery where the node syncs from existing cluster (not S3 restore). S3 restore is for full cluster recovery.

### Step 1: Delete etcd data on master3

```bash
# etcd already stopped (manifest in /tmp from Test A)
[k8s_admin@k8s-master3 ~]$ sudo rm -rf /var/lib/etcd
```

### Step 2: Verify cluster still running (2/3 quorum)

```bash
[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
d52dc5d621c3892f, started, k8s-master3.lab.local, https://10.0.61.12:2380, https://10.0.61.12:2379, false
```

### Step 3: Remove broken member from cluster

```bash
[root@k8s-master1 ~]# etcdctl member remove d52dc5d621c3892f
Member d52dc5d621c3892f removed from cluster abaa19f50fe773e1

[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
```

### Step 4: Re-add master3 as new member

```bash
[root@k8s-master1 ~]# etcdctl member add k8s-master3.lab.local --peer-urls=https://10.0.61.12:2380
Member e0a1c396a5ca70ba added to cluster abaa19f50fe773e1

ETCD_NAME="k8s-master3.lab.local"
ETCD_INITIAL_CLUSTER="k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://10.0.61.12:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
```

**New member ID:** e0a1c396a5ca70ba (different from original d52dc5d621c3892f)

### Step 5: Edit etcd.yaml and restore static pod

```bash
# Verify initial-cluster-state is "existing" (required for rejoining)
[k8s_admin@k8s-master3 ~]$ sudo cat /tmp/etcd.yaml | grep 'initial-cluster-state'
    - --initial-cluster-state=existing

# Move manifest back to start etcd
[k8s_admin@k8s-master3 ~]$ sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

### Step 6: Verify etcd recovery

```bash
[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
e0a1c396a5ca70ba, started, k8s-master3.lab.local, https://10.0.61.12:2380, https://10.0.61.12:2379, false

[root@k8s-master1 ~]# etcdctl endpoint health --cluster
https://10.0.61.11:2379 is healthy: successfully committed proposal: took = 8.529608ms
https://10.0.61.12:2379 is healthy: successfully committed proposal: took = 9.00107ms
https://10.0.61.10:2379 is healthy: successfully committed proposal: took = 8.846662ms
```

**Note:** New member ID `e0a1c396a5ca70ba` differs from original `d52dc5d621c3892f` - this is expected when re-adding a member.

### Step 7: Node still NotReady - restart kubelet

```bash
# Node showed NotReady even with healthy etcd
[root@k8s-master1 ~]# kubectl get nodes
k8s-master3.lab.local   NotReady   control-plane   15d   v1.35.3

# Restart kubelet on master3
[k8s_admin@k8s-master3 ~]$ sudo systemctl restart kubelet
```

### Step 8: Full recovery verified

```bash
[root@k8s-master1 ~]# kubectl get nodes
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   15d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   15d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   15d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          15d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          15d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          15d   v1.35.3

[root@k8s-master1 ~]# kubectl get pods -A -o wide | grep master3
kube-system   calico-node-dpvkz                               1/1     Running   ...   k8s-master3.lab.local
kube-system   etcd-k8s-master3.lab.local                      1/1     Running   ...   k8s-master3.lab.local
kube-system   kube-apiserver-k8s-master3.lab.local            1/1     Running   ...   k8s-master3.lab.local
kube-system   kube-controller-manager-k8s-master3.lab.local   1/1     Running   ...   k8s-master3.lab.local
kube-system   kube-scheduler-k8s-master3.lab.local            1/1     Running   ...   k8s-master3.lab.local
```

**Workload Recovery:**
```bash
# Remediation pod rescheduled to master1 during outage
[root@k8s-master1 ~]# kubectl get pod -n remediation -o wide
NAME                           READY   STATUS    AGE   NODE
remediation-56bdddfcd7-kw6zk   2/2     Running   24m   k8s-master1.lab.local
```

---

## Summary

**Test Duration:** ~25 minutes (16:36 - 17:02)

**What We Tested:**
1. etcd single node failure (manifest removal)
2. etcd data deletion and cluster re-sync
3. Member removal and re-addition
4. Full node recovery

**Key Findings:**

| Finding | Details |
|---------|---------|
| Quorum maintained | 2/3 etcd nodes kept cluster operational |
| Brief worker blip | Workers went NotReady for ~5 seconds during failover, self-healed |
| Memory spike | Surviving masters jumped from ~80% to ~88% RAM |
| kubectl delay | Commands had 2-3s latency during failover |
| Pod migration | Remediation pod rescheduled from master3 to master1 |
| Terminating pods | Stuck pods auto-cleaned after node recovered |
| Kubelet restart required | Node stayed NotReady until kubelet restarted |

---

## Recovery Procedure (Single Node etcd Failure)

1. Stop etcd: `mv /etc/kubernetes/manifests/etcd.yaml /tmp/`
2. Delete data: `rm -rf /var/lib/etcd`
3. Remove member: `etcdctl member remove <ID>`
4. Re-add member: `etcdctl member add <name> --peer-urls=<url>`
5. Edit manifest: `--initial-cluster-state=existing`
6. Restore manifest: `mv /tmp/etcd.yaml /etc/kubernetes/manifests/`
7. Restart kubelet: `systemctl restart kubelet`

**Important Notes:**
- S3 snapshot restore is for **full cluster recovery** (all nodes dead)
- Single node failure uses **cluster sync** (node downloads data from leader)
- Member ID changes after re-add - this is normal
- Always verify `--initial-cluster-state=existing` before rejoining

---

## If etcd.yaml Manifest is Lost

If the manifest file itself is missing (not just moved), recover it using one of these methods:

**Option 1: Copy from another master (fastest)**
```bash
# From healthy master, copy manifest
scp /etc/kubernetes/manifests/etcd.yaml k8s-master3:/tmp/

# On broken node, edit node-specific values:
sudo nano /tmp/etcd.yaml
# Change these to match the broken node:
#   --name=k8s-master3.lab.local
#   --initial-advertise-peer-urls=https://10.0.61.12:2380
#   --listen-peer-urls=https://10.0.61.12:2380
#   --listen-client-urls=https://127.0.0.1:2379,https://10.0.61.12:2379
#   --advertise-client-urls=https://10.0.61.12:2379
#   --initial-cluster-state=existing

sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

**Option 2: Regenerate via kubeadm**
```bash
# Requires kubeadm config to exist
kubeadm init phase etcd local --config=/etc/kubernetes/kubeadm-config.yaml
# Then edit --initial-cluster-state=existing
```

**Option 3: Restore from Proxmox backup**
```bash
# Restore latest backup to temporary VMID
qmrestore /mnt/pve/nas-prod-data/dump/vzdump-qemu-1012-*.vma.zst 9912 --storage local-lvm

# Start temp VM, SSH in, copy the file
scp root@temp-vm:/etc/kubernetes/manifests/etcd.yaml /tmp/

# Copy to broken node, edit node-specific values, restore
# Then delete temp VM
qm destroy 9912
```

Or restore the entire VM from Proxmox backup:
```bash
# Stop broken VM and restore from backup
qm stop 1012
qmrestore /mnt/pve/nas-prod-data/dump/vzdump-qemu-1012-*.vma.zst 1012 --force
qm start 1012
# Then rejoin etcd cluster (member add + set existing)
```

---

## Lessons Learned

1. **kubeadm etcd is a static pod** - use `mv manifest` not `systemctl stop`
2. **Single node failure → cluster sync** - no S3 restore needed, node syncs from leader
3. **S3 restore is for full cluster failure** - when all etcd nodes are dead
4. **Memory headroom matters** - surviving masters spike ~8% during failover
5. **Kubelet restart often needed** - node may stay NotReady after etcd recovery
6. **Member ID changes on re-add** - this is expected behavior
7. **`--initial-cluster-state=existing`** - critical for rejoining existing cluster

---

## Issues Encountered

1. Tried `systemctl stop etcd` - doesn't exist in kubeadm (static pod)
2. Changed `initial-cluster-state` wrong direction initially
3. Node stayed NotReady after etcd healthy - required kubelet restart
4. Terminating pods stuck until node fully recovered

---

## Post-Test Verification

All nodes Ready after test:
```bash
[root@k8s-master1 ~]# kubectl get nodes -o wide
NAME                    STATUS   ROLES           AGE   VERSION
k8s-master1.lab.local   Ready    control-plane   15d   v1.35.3
k8s-master2.lab.local   Ready    control-plane   15d   v1.35.3
k8s-master3.lab.local   Ready    control-plane   15d   v1.35.3
k8s-worker1.lab.local   Ready    <none>          15d   v1.35.3
k8s-worker2.lab.local   Ready    <none>          15d   v1.35.3
k8s-worker3.lab.local   Ready    <none>          15d   v1.35.3
```

- All 6 nodes: Ready
- All pods: Running/Completed
- etcd: 3/3 healthy

---

## Result: PASS

- Cluster survived single node etcd failure (2/3 quorum)
- Full recovery via cluster sync successful
- No data loss
- All nodes Ready after recovery
