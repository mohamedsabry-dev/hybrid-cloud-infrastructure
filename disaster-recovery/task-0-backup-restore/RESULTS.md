# Task 0: Backup & Restore — Test Results

**Execution Date:** 2026-04-11
**Executed By:** Sabry
**Environment:** dev + prod (both)

---

## Contents

```
Task 0: Backup & Restore
├── Scenario 0.0 — Full Environment Backup
│   ├── pve-dev (VMs + LXCs)
│   └── pve-prod (VMs + LXCs)
│
├── Scenario 0.1 — ETCD Backup to S3
│   ├── Trigger manual backup
│   ├── Verify dev cluster backup
│   ├── Verify prod cluster backup
│   └── Vault agent integration
│
├── Scenario 0.2 — ETCD Single Node Failure & Recovery
│   ├── Test A: Stop etcd (quorum test)
│   ├── Test B: Delete data + cluster sync recovery
│   ├── Test C: S3 backup validation
│   ├── Summary & insights
│   └── Recovery procedures
│
├── Reference: Full Cluster Restore from S3 (not tested)
│
├── Summary
│   ├── Results table
│   ├── Lessons learned
│   └── Issues encountered
│
├── Post-Test Verification
│   ├── Dev cluster health
│   └── Prod cluster health
│
└── Additional Backup Systems (not tested)
    ├── Proxmox config — validated in TS-PVE-007
    ├── VM restore — validated in TS-TF-010
    ├── Vault Raft — deferred (LXC snapshot tradeoff)
    ├── Router backups — already used in real scenario
    └── NAS — RAID 1, USB backup planned
```

---

## Scenario 0.0 — Full Environment Backup

**Status:** [x] PASS / [ ] FAIL / [ ] SKIPPED

### pve-dev Backup

**Proxmox Backup Job:**
- Start Time: Apr 11 14:11:36
- End Time: Apr 11 14:21:25
- Duration: ~10 minutes
- Storage: nas-dev-data
- Status: OK

**VMs Backed Up:**

| VMID | Name | Status |
|------|------|--------|
| 1001 | freeipa | OK |
| 1010 | k8s-master1 | OK |
| 1011 | k8s-master2 | OK |
| 1012 | k8s-master3 | OK |
| 1020 | k8s-worker1 | OK |
| 1021 | k8s-worker2 | OK |
| 1022 | k8s-worker3 | OK |
| 9000 | rocky10-golden-image | OK (shutdown - TF template) |
| 9001 | rocky10-golden-template | OK (shutdown - TF template) |

**LXCs Backed Up:**

| CTID | Name | Status |
|------|------|--------|
| 2001 | ansible | OK |
| 2002 | local-runner | OK |
| 2003 | ex-nginx | OK |
| 2004 | vault1 | OK |
| 2005 | vault2 | OK |
| 2006 | vault3 | OK |
| 9010 | rocky10-lxc-golden | OK (shutdown - TF template) |

### pve-prod Backup

**Proxmox Backup Job:**
- Start Time: Apr 11 12:19:28
- End Time: Apr 11 12:29:37
- Duration: ~10 minutes
- Storage: nas-prod-data
- Status: OK

**VMs Backed Up:**

| VMID | Name | Status |
|------|------|--------|
| 1001 | freeipa | OK |
| 1010 | k8s-master1 | OK |
| 1011 | k8s-master2 | OK |
| 1012 | k8s-master3 | OK |
| 1020 | k8s-worker1 | OK |
| 1021 | k8s-worker2 | OK |
| 1022 | k8s-worker3 | OK |
| 9000 | rocky10-golden-image | OK (shutdown - TF template) |
| 9001 | rocky10-golden-template | OK (shutdown - TF template) |

**LXCs Backed Up:**

| CTID | Name | Status |
|------|------|--------|
| 2001 | ansible | OK |
| 2002 | local-runner | OK |
| 2003 | ex-nginx | OK |
| 2004 | vault1 | OK |
| 2005 | vault2 | OK |
| 2006 | vault3 | OK |
| 9010 | rocky10-lxc-golden | OK (shutdown - TF template) |

**Evidence (pve-dev):**
```bash
root@pve-dev:~# ls -lh /mnt/pve/nas-dev-data/dump/ | grep 2026_04_11

# LXCs (427M-1.2G each)
vzdump-lxc-2001-2026_04_11-14_18_45.tar.zst  427M
vzdump-lxc-2002-2026_04_11-14_19_00.tar.zst  1.2G
vzdump-lxc-2003-2026_04_11-14_19_32.tar.zst  290M
vzdump-lxc-2004-2026_04_11-14_19_44.tar.zst  452M
vzdump-lxc-2005-2026_04_11-14_19_59.tar.zst  451M
vzdump-lxc-2006-2026_04_11-14_20_14.tar.zst  456M
vzdump-lxc-9010-2026_04_11-14_21_15.tar.zst  223M

# VMs (1.4G-6.6G each)
vzdump-qemu-1001-2026_04_11-14_11_36.vma.zst  1.6G
vzdump-qemu-1010-2026_04_11-14_12_50.vma.zst  3.5G
vzdump-qemu-1011-2026_04_11-14_13_44.vma.zst  3.6G
vzdump-qemu-1012-2026_04_11-14_14_33.vma.zst  3.3G
vzdump-qemu-1020-2026_04_11-14_15_15.vma.zst  6.6G
vzdump-qemu-1021-2026_04_11-14_16_26.vma.zst  6.2G
vzdump-qemu-1022-2026_04_11-14_17_32.vma.zst  6.3G
vzdump-qemu-9000-2026_04_11-14_20_30.vma.zst  1.4G
vzdump-qemu-9001-2026_04_11-14_20_52.vma.zst  1.4G
```

**Evidence (pve-prod):**
```bash
root@pve-prod:~# ls -lh /mnt/pve/nas-prod-data/dump/ | grep 2026_04_11

# LXCs
vzdump-lxc-2001-2026_04_11-12_26_49.tar.zst  326M
vzdump-lxc-2002-2026_04_11-12_27_03.tar.zst  1.2G
vzdump-lxc-2003-2026_04_11-12_27_38.tar.zst  265M
vzdump-lxc-2004-2026_04_11-12_27_49.tar.zst  424M
vzdump-lxc-2005-2026_04_11-12_28_03.tar.zst  591M
vzdump-lxc-2006-2026_04_11-12_28_19.tar.zst  424M
vzdump-lxc-9010-2026_04_11-12_29_28.tar.zst  223M

# VMs
vzdump-qemu-1001-2026_04_11-12_19_28.vma.zst  1.7G
vzdump-qemu-1010-2026_04_11-12_20_38.vma.zst  3.0G
vzdump-qemu-1011-2026_04_11-12_21_28.vma.zst  3.3G
vzdump-qemu-1012-2026_04_11-12_22_17.vma.zst  3.4G
vzdump-qemu-1020-2026_04_11-12_23_10.vma.zst  6.3G
vzdump-qemu-1021-2026_04_11-12_24_27.vma.zst  5.6G
vzdump-qemu-1022-2026_04_11-12_25_37.vma.zst  5.9G
vzdump-qemu-9000-2026_04_11-12_28_33.vma.zst  1.5G
vzdump-qemu-9001-2026_04_11-12_29_01.vma.zst  1.5G
```

**Notes:**
- Golden images (9000, 9001, 9010) are shutdown templates used for Terraform provisioning
- Both environments backed up successfully before DR testing begins
- Dev has double backups (10:52 + 14:11) due to mid-backup crash incident (TS-PVE-015)
- Total backup size: ~35GB dev, ~30GB prod

---

## Scenario 0.1 — ETCD Backup & Restore (Local + S3)

**Status:** [x] PASS / [ ] FAIL / [ ] SKIPPED

### Step 1: Trigger Manual Backup

**Command:**
```bash
kubectl create job --from=cronjob/etcd-backup etcd-backup-dr-test -n etcd-backup
```

**Output:**
```
job.batch/etcd-backup-dr-test created
```

### Step 2: Verify Backup (Dev Cluster)

**Job Logs:**
```
=== etcd Backup Started ===
Timestamp: Sat Apr 11 14:11:01 UTC 2026
Backup name: etcd-20260411-141101.snap
Taking etcd snapshot...
Snapshot saved at /backup/etcd-20260411-141101.snap
-rw------- 1 root root 38M Apr 11 14:11 /backup/etcd-20260411-141101.snap

Verifying snapshot...
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
| e7ce2d02 |  2883121 |       2863 |      39 MB |
+----------+----------+------------+------------+

Loading AWS credentials...
Uploading to S3...
upload: backup/etcd-20260411-141101.snap to s3://hybrid-cloud-k8s-etcd-backup-dev/etcd-20260411-141101.snap
=== Backup Complete ===
Local: /backup/etcd-20260411-141101.snap
S3: s3://hybrid-cloud-k8s-etcd-backup-dev/etcd-20260411-141101.snap

Remaining local backups:
-rw------- 1 root root 38M Apr 10 14:11 etcd-20260410-141119.snap
-rw------- 1 root root 38M Apr 11 14:11 etcd-20260411-141101.snap
```

### Step 3: Verify Backup (Prod Cluster)

**Job Logs:**
```
=== etcd Backup Started ===
Timestamp: Sat Apr 11 14:10:28 UTC 2026
Backup name: etcd-20260411-141028.snap
Taking etcd snapshot...
Snapshot saved at /backup/etcd-20260411-141028.snap
-rw------- 1 root root 35M Apr 11 14:10 /backup/etcd-20260411-141028.snap

Verifying snapshot...
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
| f316b33d |  1559350 |       2471 |      37 MB |
+----------+----------+------------+------------+

Loading AWS credentials...
Uploading to S3...
upload: backup/etcd-20260411-141028.snap to s3://hybrid-cloud-k8s-etcd-backup-prod/etcd-20260411-141028.snap
=== Backup Complete ===
Local: /backup/etcd-20260411-141028.snap
S3: s3://hybrid-cloud-k8s-etcd-backup-prod/etcd-20260411-141028.snap

Remaining local backups:
-rw------- 1 root root 35M Apr 10 17:01 etcd-20260410-170134.snap
-rw------- 1 root root 35M Apr 10 18:00 etcd-20260410-180015.snap
-rw------- 1 root root 35M Apr 11 08:39 etcd-20260411-083959.snap
-rw------- 1 root root 35M Apr 11 08:40 etcd-20260411-084001.snap
-rw------- 1 root root 35M Apr 11 08:40 etcd-20260411-084017.snap
-rw------- 1 root root 35M Apr 11 12:00 etcd-20260411-120009.snap
-rw------- 1 root root 35M Apr 11 14:10 etcd-20260411-141028.snap
```

### Vault Agent Integration (Loki Evidence)

Vault agent successfully injected AWS credentials:
```
2026-04-11T14:10:26.897Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2026-04-11T14:10:26.898Z [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
2026-04-11T14:10:26.898Z [INFO]  agent: sinks finished, exiting
```

### Summary

| Cluster | Snapshot | Size | Keys | Revision | S3 Bucket |
|---------|----------|------|------|----------|-----------|
| Dev | etcd-20260411-141101.snap | 39 MB | 2863 | 2883121 | hybrid-cloud-k8s-etcd-backup-dev |
| Prod | etcd-20260411-141028.snap | 37 MB | 2471 | 1559350 | hybrid-cloud-k8s-etcd-backup-prod |

### Step 4: Restore from Local Snapshot

**Status:** SKIPPED (backup verification complete, restore tested separately if needed)

**Notes:**
- Vault Agent version mismatch warning (1.21.2 vs 1.21.4) - informational only, does not affect functionality
- AWS credentials successfully injected via Vault
- Both local and S3 backups verified
- Backup retention working (keeping multiple snapshots)

---

## Scenario 0.2 — ETCD Single Node Failure & Recovery

**Status:** [x] PASS / [ ] FAIL / [ ] SKIPPED

**Objective:** Test etcd cluster resilience when one master loses etcd, then recover.

### Test A: Stop etcd Static Pod (Quorum Test)

**Environment:** prod cluster (10.0.61.x)
**Test Time:** 2026-04-11 16:36

> **Note:** In kubeadm clusters, etcd runs as a static pod (not systemd service). To stop it, move the manifest file instead of using systemctl.

**Step 1: Pre-test cluster health (all healthy)**
```bash
[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
d52dc5d621c3892f, started, k8s-master3.lab.local, https://10.0.61.12:2380, https://10.0.61.12:2379, false
```

**Member IDs:**
- master1: 2699402e05a84d4b (10.0.61.10)
- master2: 4c17d04fdb863468 (10.0.61.11)
- master3: d52dc5d621c3892f (10.0.61.12) ← TARGET

**Step 2: Stop etcd on master3 (move static pod manifest)**
```bash
[k8s_admin@k8s-master3 ~]$ sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
```

**Step 3: Verify cluster survives with 2/3 quorum**
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

**Resource Impact on Surviving Masters:**

| Node | Memory Before | Memory During | Delta |
|------|---------------|---------------|-------|
| master1 | ~80% | 88.76% (2.22/2.50 GiB) | +8% |
| master2 | ~80% | 87.96% (2.20/2.50 GiB) | +8% |
| master3 | ~80% | 81.10% (2.03/2.50 GiB) | -etcd stopped |

**Side Effects Observed:**
- kubectl commands had brief delay (~2-3s) during failover
- Flux kustomize-controller re-acquired leader lease
- Grafana storage migrations triggered on pod restart
- Loki rejected old log entries (>3h behind - normal after restart)
- kube-prometheus-stack HelmRelease showed terminal error (pre-existing issue, unrelated to test)

**Key Finding:** Surviving masters absorbed load from failed node, causing memory spike from ~80% to ~88%. In production, ensure masters have headroom for failover scenarios.

**Step 4: Restore etcd on master3**
```bash
[k8s_admin@k8s-master3 ~]$ sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

**Step 5: Verify auto-rejoin**
```bash
(paste output after restore here)
```

**Result:** CLUSTER SURVIVED with 2/3 etcd nodes. Quorum maintained, workloads continued.

---

### Test B: Delete etcd Data (Manual Recovery via Cluster Sync)

> **Note:** This tests single-node recovery where the node syncs from existing cluster (not S3 restore). S3 restore is for full cluster recovery - tested separately in Test C.

**Step 1: Delete etcd data on master3**
```bash
# etcd already stopped (manifest in /tmp from Test A)
[k8s_admin@k8s-master3 ~]$ sudo rm -rf /var/lib/etcd
```

**Step 2: Verify cluster still running (2/3 quorum)**
```bash
[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
d52dc5d621c3892f, started, k8s-master3.lab.local, https://10.0.61.12:2380, https://10.0.61.12:2379, false
```

**Step 3: Remove broken member from cluster**
```bash
[root@k8s-master1 ~]# etcdctl member remove d52dc5d621c3892f
Member d52dc5d621c3892f removed from cluster abaa19f50fe773e1

[root@k8s-master1 ~]# etcdctl member list
2699402e05a84d4b, started, k8s-master1.lab.local, https://10.0.61.10:2380, https://10.0.61.10:2379, false
4c17d04fdb863468, started, k8s-master2.lab.local, https://10.0.61.11:2380, https://10.0.61.11:2379, false
```

**Step 4: Re-add master3 as new member**
```bash
[root@k8s-master1 ~]# etcdctl member add k8s-master3.lab.local --peer-urls=https://10.0.61.12:2380
Member e0a1c396a5ca70ba added to cluster abaa19f50fe773e1

ETCD_NAME="k8s-master3.lab.local"
ETCD_INITIAL_CLUSTER="k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://10.0.61.12:2380"
ETCD_INITIAL_CLUSTER_STATE="existing"
```

**New member ID:** e0a1c396a5ca70ba (different from original d52dc5d621c3892f)

**Step 5: Edit etcd.yaml and restore static pod**
```bash
# Verify initial-cluster-state is "existing" (required for rejoining)
[k8s_admin@k8s-master3 ~]$ sudo cat /tmp/etcd.yaml | grep 'initial-cluster-state'
    - --initial-cluster-state=existing

# Move manifest back to start etcd
[k8s_admin@k8s-master3 ~]$ sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

**Step 6: Verify etcd recovery**
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

**Note:** New member ID `e0a1c396a5ca70ba` differs from original `d52dc5d621c3892f` — this is expected when re-adding a member.

**Step 7: Node still NotReady — restart kubelet**
```bash
# Node showed NotReady even with healthy etcd
[root@k8s-master1 ~]# kubectl get nodes
k8s-master3.lab.local   NotReady   control-plane   15d   v1.35.3

# Restart kubelet on master3
[k8s_admin@k8s-master3 ~]$ sudo systemctl restart kubelet
```

**Step 8: Full recovery verified**
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

### Scenario 0.2 Summary & Insights

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

**Recovery Procedure (Single Node etcd Failure):**

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
- Member ID changes after re-add — this is normal
- Always verify `--initial-cluster-state=existing` before rejoining

**If etcd.yaml Manifest is Lost:**

If the manifest file itself is missing (not just moved), recover it using one of these methods:

*Option 1: Copy from another master (fastest)*
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

*Option 2: Regenerate via kubeadm*
```bash
# Requires kubeadm config to exist
kubeadm init phase etcd local --config=/etc/kubernetes/kubeadm-config.yaml
# Then edit --initial-cluster-state=existing
```

*Option 3: Extract from Proxmox backup (recommended with VM backups)*
```bash
# Restore latest backup to temporary VMID
qmrestore /mnt/pve/nas-prod-data/dump/vzdump-qemu-1012-*.vma.zst 9912 --storage local-lvm

# Start temp VM, SSH in, copy the file
scp root@temp-vm:/etc/kubernetes/manifests/etcd.yaml /tmp/

# Copy to broken node, edit node-specific values, restore
# Then delete temp VM
qm destroy 9912
```

Or even simpler — just restore the entire VM from Proxmox backup:
```bash
# Stop broken VM and restore from backup
qm stop 1012
qmrestore /mnt/pve/nas-prod-data/dump/vzdump-qemu-1012-*.vma.zst 1012 --force
qm start 1012
# Then rejoin etcd cluster (member add + set existing)
```

*Option 4: Full rejoin via kubeadm (last resort)*
```bash
# Only if everything else fails
kubeadm reset -f
kubeadm join <endpoint>:6443 --token <token> \
  --control-plane --certificate-key <key>
```

---

### Test C: Verify S3 Backup Download (Non-Destructive)

**Status:** PASS

**Step 1: Download snapshot from S3**
```bash
# Downloaded from S3 to local Mac, then uploaded to master1
sabry@Mac % aws s3 cp s3://hybrid-cloud-k8s-etcd-backup-dev/etcd-20260411-141101.snap ~/Downloads/
sabry@Mac % scp etcd-20260411-141101.snap k8s_admin@k8s-master1-dev:/tmp
```

**Step 2: Validate snapshot**
```bash
# First attempt - etcdctl snapshot status (FAILED in etcd 3.6)
[root@k8s-master1 ~]# etcdctl snapshot status /tmp/etcd-20260411-141101.snap --write-out=table
# Shows help text only - command moved to etcdutl in etcd 3.6

# Download etcdutl to validate
[root@k8s-master1 ~]# ETCD_VER=v3.6.6
[root@k8s-master1 ~]# curl -L https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz | tar xz
[root@k8s-master1 ~]# ./etcd-${ETCD_VER}-linux-amd64/etcdutl snapshot status /tmp/etcd-20260411-141101.snap --write-out=table
+----------+----------+------------+------------+---------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE | VERSION |
+----------+----------+------------+------------+---------+
| e7ce2d02 |  2883121 |        952 |      39 MB |   3.6.0 |
+----------+----------+------------+------------+---------+
```

**Comparison with Original Backup:**

| Field | Backup Job Log | S3 Validation | Match? |
|-------|----------------|---------------|--------|
| HASH | e7ce2d02 | e7ce2d02 | ✓ YES |
| REVISION | 2883121 | 2883121 | ✓ YES |
| SIZE | 39 MB | 39 MB | ✓ YES |
| KEYS | 2863 | 952 | Different* |

*Key count difference is due to etcdutl version counting keys differently (internal vs user keys). Hash match confirms file integrity.

**Notes:**
- etcd 3.6 moved `snapshot status` from etcdctl to etcdutl
- Snapshot is valid and ready for full cluster restore if needed
- S3 backup pipeline confirmed working end-to-end

---

### Full Cluster Restore from S3 (Reference Procedure)

> **Status:** NOT TESTED — documented for reference only. Use when all 3 etcd nodes are dead/corrupted.

**Step 1: Download snapshot to all masters**
```bash
# On each master node (master1, master2, master3)
aws s3 cp s3://hybrid-cloud-k8s-etcd-backup-prod/etcd-20260411-141028.snap /tmp/
```

**Step 2: Stop etcd on all nodes**
```bash
# On each master
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
sudo rm -rf /var/lib/etcd
```

**Step 3: Restore snapshot on each node**
```bash
# On master1
etcdutl snapshot restore /tmp/etcd-20260411-141028.snap \
  --data-dir=/var/lib/etcd \
  --name=k8s-master1.lab.local \
  --initial-cluster=k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380 \
  --initial-advertise-peer-urls=https://10.0.61.10:2380

# On master2
etcdutl snapshot restore /tmp/etcd-20260411-141028.snap \
  --data-dir=/var/lib/etcd \
  --name=k8s-master2.lab.local \
  --initial-cluster=k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380 \
  --initial-advertise-peer-urls=https://10.0.61.11:2380

# On master3
etcdutl snapshot restore /tmp/etcd-20260411-141028.snap \
  --data-dir=/var/lib/etcd \
  --name=k8s-master3.lab.local \
  --initial-cluster=k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380 \
  --initial-advertise-peer-urls=https://10.0.61.12:2380
```

**Step 4: Fix permissions and restore etcd manifests**
```bash
# On each master
sudo chown -R root:root /var/lib/etcd

# Edit etcd.yaml to set --initial-cluster-state=existing
sudo sed -i 's/--initial-cluster-state=new/--initial-cluster-state=existing/' /tmp/etcd.yaml

# Restore manifest
sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

**Step 5: Verify cluster recovery**
```bash
etcdctl member list
etcdctl endpoint health --cluster
kubectl get nodes
```

**Important Notes:**
- All nodes must restore from the SAME snapshot
- --initial-cluster must list ALL members
- --name must match the node's hostname
- Run restore on all nodes BEFORE starting any etcd

---

## Summary

| Scenario | Description | Status | Duration |
|----------|-------------|--------|----------|
| 0.0 | Full Proxmox Backup | PASS | ~10 min each env |
| 0.1 | ETCD Backup to S3 | PASS | ~2 min |
| 0.2 | ETCD Single Node Recovery | PASS | ~25 min |

**Overall Task 0 Status:** [x] PASS / [ ] FAIL

**Lessons Learned:**

1. **kubeadm etcd is a static pod** — use `mv manifest` not `systemctl stop`
2. **Single node failure → cluster sync** — no S3 restore needed, node syncs from leader
3. **S3 restore is for full cluster failure** — when all etcd nodes are dead
4. **Memory headroom matters** — surviving masters spike ~8% during failover
5. **Kubelet restart often needed** — node may stay NotReady after etcd recovery
6. **Member ID changes on re-add** — this is expected behavior
7. **`--initial-cluster-state=existing`** — critical for rejoining existing cluster

**Issues Encountered:**

1. Tried `systemctl stop etcd` — doesn't exist in kubeadm (static pod)
2. Changed `initial-cluster-state` wrong direction initially
3. Node stayed NotReady after etcd healthy — required kubelet restart
4. Terminating pods stuck until node fully recovered

**What Was NOT Tested (Future Work):**
- Full cluster S3 restore (all 3 etcd nodes dead)
- Cross-cluster restore (restore prod backup to dev)
- Point-in-time recovery (restore to specific revision)

---

---

## Post-Test Verification

**Timestamp:** 2026-04-11 17:37 EET

### Dev Cluster (10.0.61.x)

```bash
[root@k8s-master1 ~]# kubectl get nodes -o wide
NAME                    STATUS   ROLES           AGE   VERSION   INTERNAL-IP
k8s-master1.lab.local   Ready    control-plane   15d   v1.35.3   10.0.61.10
k8s-master2.lab.local   Ready    control-plane   15d   v1.35.3   10.0.61.11
k8s-master3.lab.local   Ready    control-plane   15d   v1.35.3   10.0.61.12
k8s-worker1.lab.local   Ready    <none>          15d   v1.35.3   10.0.64.10
k8s-worker2.lab.local   Ready    <none>          15d   v1.35.3   10.0.64.11
k8s-worker3.lab.local   Ready    <none>          15d   v1.35.3   10.0.64.12
```

- All 6 nodes: Ready
- All pods: Running/Completed
- etcd: 3/3 healthy
- vault-agent-injector: Running on master2

### Prod Cluster (10.0.51.x)

```bash
[root@k8s-master1 ~]# kubectl get nodes -o wide
NAME                    STATUS   ROLES           AGE   VERSION   INTERNAL-IP
k8s-master1.lab.local   Ready    control-plane   15d   v1.35.3   10.0.51.10
k8s-master2.lab.local   Ready    control-plane   15d   v1.35.3   10.0.51.11
k8s-master3.lab.local   Ready    control-plane   15d   v1.35.3   10.0.51.12
k8s-worker1.lab.local   Ready    <none>          15d   v1.35.3   10.0.54.10
k8s-worker2.lab.local   Ready    <none>          15d   v1.35.3   10.0.54.11
k8s-worker3.lab.local   Ready    <none>          15d   v1.35.3   10.0.54.12
```

- All 6 nodes: Ready
- All pods: Running/Completed
- etcd: 3/3 healthy
- vault-agent-injector: Running on master2

### Conclusion

Both clusters fully operational after Task 0 DR testing. No residual issues from etcd recovery test.

---

## Additional Backup Systems (Not Tested — Already Validated)

The following backup/restore scenarios were NOT tested during DR phase because they were already validated in real incidents or have documented decisions:

### Proxmox Config Backup & Restore

**Status:** Already tested in real incident

- Backup script: `proxmox/backup/backup-proxmox-config.sh` (scheduled via cron)
- Backups stored on NAS
- **Real incident validation:** See [TS-PVE-007](../../troubleshooting/proxmox/7-crontab-overwrite-recovery.md) — successfully restored Proxmox config from NAS backup after crontab was overwritten
- No need to retest

### VM/Node Backup & Restore from Proxmox

**Status:** Already tested in real incident

- Proxmox vzdump backups on NAS (nas-dev-data, nas-prod-data)
- **Real incident validation:** See [TS-TF-010](../../troubleshooting/terraform/10-cloud-init-ssh-host-key-regeneration.md) — restored node from Proxmox backup during cloud-init SSH key issue
- No need to retest

### Vault Raft Storage Backup

**Status:** Deferred — architectural tradeoff

**Decision:** Not using NAS mount for Vault Raft data because:
- Mounting Raft to NAS would prevent Proxmox LXC snapshots (limitation)
- Preferred to keep LXC snapshot capability

**Current redundancy:**
- 3-node Vault cluster (Raft consensus)
- LXC backups on NAS (vzdump)
- Raft data on separate mount point in Proxmox
- Can restore from multiple sources if needed

### Router Backup & Restore

**Status:** Already tested in real scenario (no ticket recorded)

**TP-Link ER605:**
- Backup location: `network/router/er605/backups/backup-ER605_UN_v2.20-2026-03-14-After-CleanUp.bin`
- Already used: Applied wrong config, reset router, restored from backup
- Files in `.gitignore` (contains sensitive IPs/keys)

**MikroTik:**
- Backup location: `network/router/mikrotik/backups/backup-after-acl-api-rules.backup`
- Files in `.gitignore` (contains sensitive data)

### NAS (Asustor) Backup

**Status:** Partially covered — improvement planned

**Current state:**
- RAID 1 on 2 disks (redundancy for disk failure)
- NAS config NOT backed up
- All data lives only on NAS (~150GB)

**Planned improvement:**
- Connect 256GB USB drive for external backup
- Use during downtime for internal data backup
- Total data < 150GB, fits on USB

---

*Completed: 2026-04-11 17:37*
