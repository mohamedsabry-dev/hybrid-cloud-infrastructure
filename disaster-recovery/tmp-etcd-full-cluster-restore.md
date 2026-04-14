# ETCD Full Cluster Restore from S3
# Date: -
# Result: NOT TESTED

---

## Scope

Restore etcd cluster from S3 backup when all 3 etcd nodes are dead/corrupted.
This is the nuclear option - full cluster recovery.

---

## When to Use

- All 3 etcd nodes corrupted
- Cluster completely unrecoverable
- Need to restore to a known good state

---

## Procedure (Reference)

### Step 1: Download snapshot to all masters

```bash
# On each master node (master1, master2, master3)
aws s3 cp s3://hybrid-cloud-k8s-etcd-backup-prod/etcd-YYYYMMDD-HHMMSS.snap /tmp/
```

### Step 2: Stop etcd on all nodes

```bash
# On each master
sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/
sudo rm -rf /var/lib/etcd
```

### Step 3: Restore snapshot on each node

```bash
# On master1
etcdutl snapshot restore /tmp/etcd-YYYYMMDD-HHMMSS.snap \
  --data-dir=/var/lib/etcd \
  --name=k8s-master1.lab.local \
  --initial-cluster=k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380 \
  --initial-advertise-peer-urls=https://10.0.61.10:2380

# On master2
etcdutl snapshot restore /tmp/etcd-YYYYMMDD-HHMMSS.snap \
  --data-dir=/var/lib/etcd \
  --name=k8s-master2.lab.local \
  --initial-cluster=k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380 \
  --initial-advertise-peer-urls=https://10.0.61.11:2380

# On master3
etcdutl snapshot restore /tmp/etcd-YYYYMMDD-HHMMSS.snap \
  --data-dir=/var/lib/etcd \
  --name=k8s-master3.lab.local \
  --initial-cluster=k8s-master1.lab.local=https://10.0.61.10:2380,k8s-master2.lab.local=https://10.0.61.11:2380,k8s-master3.lab.local=https://10.0.61.12:2380 \
  --initial-advertise-peer-urls=https://10.0.61.12:2380
```

### Step 4: Fix permissions and restore etcd manifests

```bash
# On each master
sudo chown -R root:root /var/lib/etcd

# Edit etcd.yaml to set --initial-cluster-state=existing
sudo sed -i 's/--initial-cluster-state=new/--initial-cluster-state=existing/' /tmp/etcd.yaml

# Restore manifest
sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/
```

### Step 5: Verify cluster recovery

```bash
etcdctl member list
etcdctl endpoint health --cluster
kubectl get nodes
```

---

## Important Notes

- All nodes must restore from the SAME snapshot
- --initial-cluster must list ALL members
- --name must match the node's hostname
- Run restore on all nodes BEFORE starting any etcd

---

## TODO: Test This Scenario

- [ ] Create test cluster or use dev
- [ ] Take fresh backup
- [ ] Simulate full cluster failure
- [ ] Execute restore procedure
- [ ] Verify cluster and workloads recover
- [ ] Document timing and any issues
