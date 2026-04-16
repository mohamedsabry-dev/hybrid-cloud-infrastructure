# Full NAS Shutdown DR Test
# Date: 2026-04-16
# Result: IN PROGRESS

---

## Objective

Power off NAS completely to test the most realistic major storage disaster scenario.
Compare behavior between different storage classes and mount options.

---

## Storage Classes Comparison

| StorageClass | Mount Type | Timeout | Retries | Expected Behavior |
|--------------|------------|---------|---------|-------------------|
| **nfs-retain** | `soft` | 3s (timeo=30) | 3 | Fast fail with I/O error |
| **nfs-delete** | `soft` | 3s (timeo=30) | 3 | Fast fail with I/O error |
| **nfs-database** | `hard` + `intr` | 60s (timeo=600) | 5 | Hangs until NFS recovers (interruptible) |

---

## Apps and Their Storage Configuration

| App | Namespace | StorageClass | Mount Type | Expected on NAS Down |
|-----|-----------|--------------|------------|---------------------|
| WordPress | apps | nfs-retain | `soft` | Fast I/O error → readiness fail → endpoint removed |
| MariaDB | database | nfs-database | `hard` | **Hangs** until NFS recovers |
| Grafana | monitoring | nfs-retain | `soft` | Fast I/O error → CrashLoopBackOff |
| Prometheus | monitoring | nfs-retain | `soft` | Fast I/O error → storage errors |
| Loki | monitoring | nfs-retain | `soft` | Fast I/O error → storage errors |
| Alertmanager | monitoring | nfs-retain | `soft` | Fast I/O error → storage errors |

---

## Non-NFS Components (Should Survive)

| Component | Namespace | NFS Dependency |
|-----------|-----------|----------------|
| Ingress-nginx | ingress-nginx | None |
| Vault Agent | vault | None |
| Flux controllers | flux-system | None |
| CoreDNS | kube-system | None |
| etcd | kube-system | None |

---

## Pre-Test Baseline

### Network Architecture Note
```
Masters: NO storage interface (only eth0 with 10.0.61.x for management)
Workers: eth0 (10.0.64.x management) + eth1 (10.0.40.x storage)

Worker1: 10.0.40.201
Worker2: 10.0.40.202
Worker3: 10.0.40.203
```

### NAS Exports
```bash
[root@k8s-worker1 ~]# showmount -e 10.0.40.120
Export list for 10.0.40.120:
/volume1/k8s-prod     10.0.40.103,10.0.40.102,10.0.40.101
/volume1/k8s-dev      10.0.40.203,10.0.40.202,10.0.40.201
/volume1/Backups      10.0.40.100,10.0.40.110
/volume1/prod-storage 10.0.40.100
/volume1/dev-storage  10.0.40.110
/volume1/shared-iso   10.0.40.110,10.0.40.100
```

### Pod Status
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS    RESTARTS   AGE    IP              NODE
wordpress-5f649b595f-jwcnk   2/2     Running   0          24m    10.244.62.8     k8s-worker1.lab.local
wordpress-5f649b595f-n65mm   2/2     Running   0          122m   10.244.207.68   k8s-worker2.lab.local
wordpress-5f649b595f-tpzrj   2/2     Running   0          121m   10.244.29.174   k8s-worker3.lab.local

[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS    RESTARTS        AGE     IP               NODE
mariadb-0   2/2     Running   12 (160m ago)   2d23h   10.244.207.125   k8s-worker2.lab.local

[root@k8s-master1 ~]# kubectl get pods -n monitoring -o wide
NAME                                                        READY   STATUS    NODE
alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running   k8s-worker1.lab.local
kube-prometheus-stack-grafana-5f6554dcf5-lrvqq              4/4     Running   k8s-worker2.lab.local
kube-prometheus-stack-grafana-5f6554dcf5-mqbk5              4/4     Running   k8s-worker1.lab.local
kube-prometheus-stack-grafana-5f6554dcf5-pbbn6              4/4     Running   k8s-worker3.lab.local
loki-0                                                      2/2     Running   k8s-worker2.lab.local
prometheus-kube-prometheus-stack-prometheus-0               2/2     Running   k8s-worker3.lab.local
```

### Pod Placement Summary
| App | Replicas | Node(s) | StorageClass |
|-----|----------|---------|--------------|
| WordPress | 3 | worker1, worker2, worker3 | nfs-retain (soft) |
| MariaDB | 1 | worker2 | nfs-database (hard) |
| Grafana | 3 | worker1, worker2, worker3 | nfs-retain (soft) |
| Prometheus | 1 | worker3 | nfs-retain (soft) |
| Loki | 1 | worker2 | nfs-retain (soft) |
| Alertmanager | 1 | worker1 | nfs-retain (soft) |

### PVC Status
```bash
[root@k8s-master1 ~]# kubectl get pvc -A
NAMESPACE    NAME                                            STATUS   CAPACITY   STORAGECLASS
apps         wordpress-data                                  Bound    15Gi       nfs-retain
database     mariadb-data-mariadb-0                          Bound    15Gi       nfs-database
monitoring   alertmanager-kube-prometheus-stack-...          Bound    5Gi        nfs-retain
monitoring   kube-prometheus-stack-grafana                   Bound    5Gi        nfs-retain
monitoring   prometheus-kube-prometheus-stack-...            Bound    20Gi       nfs-retain
monitoring   storage-loki-0                                  Bound    50Gi       nfs-retain
```

### WordPress Accessibility
```bash
[root@k8s-master1 ~]# curl -I http://wordpress-dev.lab.local
HTTP/1.1 200 OK
Server: nginx/1.26.3
Date: Thu, 16 Apr 2026 21:46:11 GMT
Content-Type: text/html; charset=UTF-8
```

### Non-NFS Components Status
```bash
[root@k8s-master1 ~]# kubectl get pods -n ingress-nginx
NAME                                        READY   STATUS    RESTARTS   AGE
ingress-nginx-controller-7d4c58858f-c9wrl   1/1     Running   0          55m
ingress-nginx-controller-7d4c58858f-d782c   1/1     Running   0          55m
ingress-nginx-controller-7d4c58858f-lcxbl   1/1     Running   0          55m

[root@k8s-master1 ~]# kubectl get pods -n vault
NAME                                    READY   STATUS    RESTARTS        AGE
vault-agent-injector-5877589b57-4h2ts   1/1     Running   9 (106m ago)    5d2h
vault-agent-injector-5877589b57-cwh5f   1/1     Running   6 (3h40m ago)   2d23h

[root@k8s-master1 ~]# flux get kustomization
NAME              REVISION             SUSPENDED    READY    MESSAGE
apps              dev@sha1:c35ae2a9    False        True     Applied revision: dev@sha1:c35ae2a9
flux-system       dev@sha1:c35ae2a9    False        True     Applied revision: dev@sha1:c35ae2a9
infrastructure    dev@sha1:c35ae2a9    False        True     Applied revision: dev@sha1:c35ae2a9
```

### CSI Controllers
```bash
[root@k8s-master1 ~]# kubectl get pods -o wide -A | grep csi
csi-nfs-controller-8455c76c5f-99nbm   5/5   Running   k8s-worker2.lab.local
csi-nfs-controller-8455c76c5f-snggk   5/5   Running   k8s-worker1.lab.local
csi-nfs-node-dgfgf                    3/3   Running   k8s-worker1.lab.local
csi-nfs-node-g6cng                    3/3   Running   k8s-worker2.lab.local
csi-nfs-node-gkdlg                    3/3   Running   k8s-worker3.lab.local
```

---

## Test Execution

### Step 1: Power Off NAS

Method: (Proxmox / Synology UI / SSH)
Time:

```bash
# Verify NAS unreachable after shutdown
ping 10.0.40.120
showmount -e 10.0.40.120
```

---

### Step 2: Monitor Pod Behavior

```bash
# Watch all affected pods
kubectl get pods -n apps -w
kubectl get pods -n database -w
kubectl get pods -n monitoring -w
```

---

## During Outage Observations

### WordPress (soft mount - nfs-retain)

**Expected:** Fast I/O error → readiness fail → removed from endpoints
**Actual:**
```
(record pod status and behavior)
```

### MariaDB (hard mount - nfs-database)

**Expected:** Hangs until NFS recovers (processes stuck in D state)
**Actual:**
```
(record pod status and behavior)
```

### Grafana (soft mount - nfs-retain)

**Expected:** Fast I/O error → CrashLoopBackOff
**Actual:**
```
(record pod status and behavior)
```

### Prometheus (soft mount - nfs-retain)

**Expected:** Storage errors
**Actual:**
```
(record pod status and behavior)
```

### Loki (soft mount - nfs-retain)

**Expected:** Storage errors
**Actual:**
```
(record pod status and behavior)
```

### Non-NFS Components

**Expected:** All UP
```bash
kubectl get pods -n ingress-nginx
kubectl get pods -n vault
flux get kustomization
```
**Actual:**
```
(record output)
```

---

## Kernel Level Observations

```bash
# Check dmesg on a worker node for NFS errors
ssh root@k8s-worker1 'dmesg | grep -i nfs | tail -30'
```
```
(record output)
```

---

## Step 3: Power On NAS (Recovery)

Time NAS powered on:
Time NAS fully booted:

```bash
# Verify NAS exports available
showmount -e 10.0.40.120
```

---

## Recovery Observations

### Soft Mount Apps Recovery

| App | Auto-Recovered | Time to Recover | Manual Action Needed |
|-----|----------------|-----------------|---------------------|
| WordPress | | | |
| Grafana | | | |
| Prometheus | | | |
| Loki | | | |
| Alertmanager | | | |

### Hard Mount Apps Recovery

| App | Auto-Recovered | Time to Recover | Manual Action Needed |
|-----|----------------|-----------------|---------------------|
| MariaDB | | | |

### Stale Mount Check

```bash
# Check for stale mounts on each worker
ssh root@k8s-worker1 'mount | grep nfs'
ssh root@k8s-worker2 'mount | grep nfs'
ssh root@k8s-worker3 'mount | grep nfs'
```
```
(record output)
```

---

## Post-Recovery Verification

### All Pods Healthy
```bash
kubectl get pods -n apps
kubectl get pods -n database
kubectl get pods -n monitoring
```
```
(record output)
```

### WordPress Accessible
```bash
curl -I http://wordpress-dev.lab.local
```
```
(record output)
```

### Grafana Accessible
```bash
curl -I http://grafana-dev.lab.local
```
```
(record output)
```

### Data Integrity Check
```bash
# Check MariaDB data
kubectl exec -it mariadb-0 -n database -- mysql -u root -p -e "SHOW DATABASES;"

# Check WordPress can write
# (upload a test image via WordPress admin)
```

---

## Findings Summary

### Soft Mount Behavior (nfs-retain, nfs-delete)
```
(summary of findings)
```

### Hard Mount Behavior (nfs-database)
```
(summary of findings)
```

### Recovery Times
| Component | Outage Duration | Recovery Time | Auto/Manual |
|-----------|-----------------|---------------|-------------|
| | | | |

### Issues Found
```
(list any issues)
```

### Recommendations
```
(list any recommendations)
```

---

## Related Documentation

- `disaster-recovery/single-worker-nfs-down.md` - Single worker NFS interface down test
- `disaster-recovery/nginx-dr-test.md` - NGINX layer failures test
- `kubernetes/dev/deployments/infrastructure/storage/storageclass.yaml` - Storage class definitions

---

## Test Commands Reference

```bash
# Pre-test baseline
showmount -e 10.0.40.120
kubectl get pods -A -o wide | grep -E "wordpress|mariadb|grafana|prometheus|loki|alertmanager"
kubectl get pvc -A
curl -I http://wordpress-dev.lab.local

# During outage monitoring
kubectl get pods -n apps -w
kubectl get pods -n database -w
kubectl get pods -n monitoring -w
kubectl get endpoints wordpress -n apps

# Kernel NFS errors
ssh root@k8s-worker1 'dmesg | grep -i nfs | tail -30'

# Recovery verification
showmount -e 10.0.40.120
kubectl get pods -A | grep -v Running
curl -I http://wordpress-dev.lab.local
```
