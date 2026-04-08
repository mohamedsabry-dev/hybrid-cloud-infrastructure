# Case 15: CSI NFS Controller Cannot Provision PVC - Master/Storage Network Isolation

## Status: RESOLVED
## Date: 2026-04-08
## Severity: High
## Environment: k8s-dev cluster (bare-metal kubeadm, 3 masters, 3 workers, Calico CNI, NFS CSI storage, ASUSTOR NAS)
## Related: Case 13 (CSI NFS Restart Stale Mount)

---

## 1. Issue Summary

New PVCs stuck in `Pending` state. Loki StatefulSet could not start because PVC provisioning failed with mount timeouts. Existing PVCs (Grafana, Prometheus, MariaDB) remained bound and functional.

**Root Cause:** CSI NFS controller pods were running on master nodes (10.0.61.x) which have no network connectivity to the NFS storage server (10.0.40.120). Workers have dedicated storage NICs on 10.0.40.x network.

**Resolution:** Added nodeAffinity to CSI controller deployment to force scheduling on worker nodes where storage network is accessible.

---

## 2. Symptoms Observed

### 2.1 PVC Stuck in Pending

```bash
kubectl get pvc -A
```
```
NAMESPACE    NAME              STATUS    STORAGECLASS   AGE
monitoring   storage-loki-0    Pending   nfs-retain     35m
default      test-pvc          Pending   nfs-retain     2m
```

Existing PVCs were Bound - only new provisioning failed.

### 2.2 Pod Pending Due to Unbound PVC

```bash
kubectl describe pod loki-0 -n monitoring
```
```
Events:
  Warning  FailedScheduling  default-scheduler  0/6 nodes are available: pod has unbound immediate PersistentVolumeClaims
```

### 2.3 CSI Controller Logs - Mount Timeout

```bash
kubectl logs -n kube-system csi-nfs-controller-xxx -c nfs
```
```
I0408 18:10:30.476564       1 controllerserver.go:509] internally mounting 10.0.40.120:/volume1/k8s-dev at /tmp/pvc-xxx
I0408 18:10:30.486034       1 mount_linux.go:270] Mounting cmd (mount) with arguments (-t nfs -o soft,timeo=30,retrans=3 10.0.40.120:/volume1/k8s-dev /tmp/pvc-xxx)
E0408 18:12:20.486007       1 utils.go:116] GRPC error: rpc error: code = Internal desc = failed to mount nfs server: mount volume 10.0.40.120:/volume1/k8s-dev to /tmp/pvc-xxx timeout after 110s
```

### 2.4 Workers Showing NFS Lock Issues

```bash
# On worker nodes
dmesg | grep -i nfs
```
```
NFS: 10.0.40.120: lost 2 locks
NFS: 10.0.40.120: lost 1 locks
```

### 2.5 ASUSTOR NFS Recovery Failure

```bash
# On ASUSTOR NAS
dmesg | tail -30
```
```
NFSD: unable to find recovery directory /var/lib/nfs/v4recovery
NFSD: Unable to initialize client recovery tracking! (-2)
NFSD: starting 90-second grace period
```

---

## 3. Diagnostic Commands

### 3.1 Check CSI Controller Location

```bash
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
```
```
csi-nfs-controller-xxx   5/5   Running   10.0.61.11   k8s-master2.lab.local
csi-nfs-controller-xxx   5/5   Running   10.0.61.10   k8s-master1.lab.local
```

**Problem:** Controllers on masters (10.0.61.x), NFS on 10.0.40.x - no route.

### 3.2 Verify StorageClass Mount Options

```bash
kubectl get storageclass nfs-retain -o yaml | grep -A10 mountOptions
```

### 3.3 Check PVC Events

```bash
kubectl describe pvc storage-loki-0 -n monitoring | tail -20
```

### 3.4 Test Network from Master to NFS

```bash
# From master node
ping -c 2 10.0.40.120
nc -zv 10.0.40.120 2049
```

### 3.5 Compare with Prod Cluster

```bash
# On prod - controllers on workers (working)
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
```

---

## 4. Network Architecture

| Node Type | Primary Network | Storage Network | NFS Access |
|-----------|-----------------|-----------------|------------|
| Masters   | 10.0.61.x       | None            | No         |
| Workers   | 10.0.64.x       | 10.0.40.20x     | Yes        |
| NFS Server| -               | 10.0.40.120     | -          |

CSI controller needs to mount NFS temporarily during provisioning to create subdirectories. If controller runs on masters without storage network access, provisioning fails.

---

## 5. Resolution

### 5.1 Add Node Affinity to CSI Controller

**File:** `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`

```yaml
spec:
  values:
    controller:
      replicas: 2
      priorityClassName: system-cluster-critical
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: DoesNotExist
    node:
      priorityClassName: system-node-critical
```

### 5.2 Apply and Verify

```bash
# Apply changes
flux reconcile helmrelease csi-driver-nfs -n kube-system --with-source

# Verify controllers moved to workers
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller

# Test PVC provisioning
kubectl get pvc test-nfs-delete
```

---

## 6. Additional Fixes Applied

### 6.1 NFSv3 with nolock (StorageClass)

To avoid NFSv4 state recovery issues and rpc.statd requirements:

```yaml
mountOptions:
  - nfsvers=3
  - nolock
  - soft
  - timeo=30
  - retrans=3
```

### 6.2 ASUSTOR NFS Recovery Directory

```bash
# On ASUSTOR
mkdir -p /var/lib/nfs/v4recovery
chmod 755 /var/lib/nfs/v4recovery
```

---

## 7. Architecture Options Comparison

| Approach | Pros | Cons |
|----------|------|------|
| **Controllers on workers** | No network changes, masters isolated, simple | Controllers share resources with workloads |
| **Open masters to storage** | Standard architecture, dedicated controller resources | Firewall changes, expanded attack surface |

**Decision:** Controllers on workers - matches network architecture where only workers have storage access.

---

## 8. Why It Worked Before

Existing PVCs (Grafana, Prometheus, MariaDB) were provisioned when:
- Controllers may have been scheduled on workers by chance
- Or network routing was temporarily available
- Or PVs were created during initial setup with different conditions

The CSI NFS Helm chart includes **default tolerations** for control-plane, allowing controllers to schedule on masters without explicit configuration.

---

## 9. Prevention

1. Always verify CSI controller placement matches storage network access
2. Explicitly configure node affinity for CSI controllers in network-segmented environments
3. Document network architecture (which nodes can access which storage)
4. Test PVC provisioning after cluster changes/reboots

---

## 10. Files Modified

- `kubernetes/dev/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/prod/deployments/infrastructure/storage/nfs-csi-driver.yaml`
- `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml` (NFSv3 + nolock)
