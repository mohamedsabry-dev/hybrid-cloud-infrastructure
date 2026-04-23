# Single Worker NFS Interface Down
# Date: 2026-04-13
# Result: PASS

---

## Pre-Test Baseline

**Date/Time:** 2026-04-13

**Cluster state:**
```
kubectl get pods -A -o wide
```
```
NAMESPACE       NAME                                                        READY   STATUS      RESTARTS       AGE     IP               NODE                    NOMINATED NODE   READINESS GATES
apps            wordpress-79f66bd68b-2jh6q                                  2/2     Running     0              91m     10.244.62.14     k8s-worker1.lab.local   <none>           <none>
apps            wordpress-79f66bd68b-dqstv                                  2/2     Running     0              91m     10.244.29.129    k8s-worker3.lab.local   <none>           <none>
apps            wordpress-79f66bd68b-sg58w                                  2/2     Running     0              91m     10.244.207.117   k8s-worker2.lab.local   <none>           <none>
database        mariadb-0                                                   2/2     Running     0              4h32m   10.244.29.134    k8s-worker3.lab.local   <none>           <none>
etcd-backup     etcd-backup-29598870-8tj9q                                  0/1     Completed   0              2d1h    10.0.61.12       k8s-master3.lab.local   <none>           <none>
etcd-backup     etcd-backup-29600310-4mm65                                  0/1     Completed   0              25h     10.0.61.11       k8s-master2.lab.local   <none>           <none>
etcd-backup     etcd-backup-29601750-l2wkc                                  0/1     Completed   0              74m     10.0.61.12       k8s-master3.lab.local   <none>           <none>
flux-system     helm-controller-844f6958dc-vmdsf                            1/1     Running     9 (11h ago)    4d10h   10.244.62.12     k8s-worker1.lab.local   <none>           <none>
flux-system     kustomize-controller-67486f5bfd-xjt7t                       1/1     Running     9 (11h ago)    4d10h   10.244.62.11     k8s-worker1.lab.local   <none>           <none>
flux-system     notification-controller-7f5d7cb966-nnq6g                    1/1     Running     5 (11h ago)    2d6h    10.244.207.70    k8s-worker2.lab.local   <none>           <none>
flux-system     source-controller-6d8d58659f-nf97c                          1/1     Running     9 (11h ago)    4d10h   10.244.62.51     k8s-worker1.lab.local   <none>           <none>
ingress-nginx   ingress-nginx-controller-7d4c58858f-4mjnt                   1/1     Running     6 (11h ago)    4d5h    10.244.207.127   k8s-worker2.lab.local   <none>           <none>
ingress-nginx   ingress-nginx-controller-7d4c58858f-pfpjh                   1/1     Running     7 (11h ago)    4d5h    10.244.62.61     k8s-worker1.lab.local   <none>           <none>
ingress-nginx   ingress-nginx-controller-7d4c58858f-wx4cv                   1/1     Running     3 (11h ago)    2d6h    10.244.207.116   k8s-worker2.lab.local   <none>           <none>
kube-system     calico-kube-controllers-9dff488b-jl2qq                      1/1     Running     30 (12h ago)   17d     10.244.43.183    k8s-master1.lab.local   <none>           <none>
kube-system     calico-node-756lw                                           1/1     Running     28 (11h ago)   16d     10.0.64.10       k8s-worker1.lab.local   <none>           <none>
kube-system     calico-node-7nzcf                                           1/1     Running     28 (11h ago)   16d     10.0.64.11       k8s-worker2.lab.local   <none>           <none>
kube-system     calico-node-dpvkz                                           1/1     Running     27 (12h ago)   16d     10.0.61.12       k8s-master3.lab.local   <none>           <none>
kube-system     calico-node-g6prh                                           1/1     Running     27 (12h ago)   16d     10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     calico-node-hrpcf                                           1/1     Running     34 (11h ago)   16d     10.0.64.12       k8s-worker3.lab.local   <none>           <none>
kube-system     calico-node-jp9m7                                           1/1     Running     27 (12h ago)   16d     10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     coredns-7777c888cd-4fnzm                                    1/1     Running     4 (11h ago)    2d5h    10.244.29.186    k8s-worker3.lab.local   <none>           <none>
kube-system     coredns-7777c888cd-xclvs                                    1/1     Running     10 (12h ago)   5d21h   10.244.14.161    k8s-master2.lab.local   <none>           <none>
kube-system     csi-nfs-controller-8455c76c5f-99nbm                         5/5     Running     32 (11h ago)   4d5h    10.0.64.11       k8s-worker2.lab.local   <none>           <none>
kube-system     csi-nfs-controller-8455c76c5f-snggk                         5/5     Running     23 (11h ago)   2d6h    10.0.64.10       k8s-worker1.lab.local   <none>           <none>
kube-system     csi-nfs-node-dgfgf                                          3/3     Running     21 (11h ago)   4d5h    10.0.64.10       k8s-worker1.lab.local   <none>           <none>
kube-system     csi-nfs-node-g6cng                                          3/3     Running     18 (11h ago)   4d5h    10.0.64.11       k8s-worker2.lab.local   <none>           <none>
kube-system     csi-nfs-node-gkdlg                                          3/3     Running     24 (11h ago)   4d5h    10.0.64.12       k8s-worker3.lab.local   <none>           <none>
kube-system     csi-nfs-node-nzmnx                                          3/3     Running     18 (12h ago)   4d5h    10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     csi-nfs-node-pgxkw                                          3/3     Running     18 (12h ago)   4d5h    10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     csi-nfs-node-q96fb                                          3/3     Running     19 (12h ago)   4d5h    10.0.61.12       k8s-master3.lab.local   <none>           <none>
kube-system     etcd-k8s-master1.lab.local                                  1/1     Running     30 (12h ago)   17d     10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     etcd-k8s-master2.lab.local                                  1/1     Running     30 (12h ago)   17d     10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     etcd-k8s-master3.lab.local                                  1/1     Running     3 (12h ago)    17d     10.0.61.12       k8s-master3.lab.local   <none>           <none>
kube-system     kube-apiserver-k8s-master1.lab.local                        1/1     Running     32 (12h ago)   17d     10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     kube-apiserver-k8s-master2.lab.local                        1/1     Running     33 (12h ago)   17d     10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     kube-apiserver-k8s-master3.lab.local                        1/1     Running     40 (12h ago)   17d     10.0.61.12       k8s-master3.lab.local   <none>           <none>
kube-system     kube-controller-manager-k8s-master1.lab.local               1/1     Running     32 (12h ago)   17d     10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     kube-controller-manager-k8s-master2.lab.local               1/1     Running     33 (12h ago)   17d     10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     kube-controller-manager-k8s-master3.lab.local               1/1     Running     30 (12h ago)   17d     10.0.61.12       k8s-master3.lab.local   <none>           <none>
kube-system     kube-proxy-6c4z6                                            1/1     Running     30 (12h ago)   17d     10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     kube-proxy-7sx59                                            1/1     Running     33 (11h ago)   17d     10.0.64.11       k8s-worker2.lab.local   <none>           <none>
kube-system     kube-proxy-8cgvz                                            1/1     Running     30 (12h ago)   17d     10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     kube-proxy-bq4vp                                            1/1     Running     39 (11h ago)   17d     10.0.64.12       k8s-worker3.lab.local   <none>           <none>
kube-system     kube-proxy-hqnmt                                            1/1     Running     30 (12h ago)   17d     10.0.61.12       k8s-master3.lab.local   <none>           <none>
kube-system     kube-proxy-pmm4p                                            1/1     Running     35 (11h ago)   17d     10.0.64.10       k8s-worker1.lab.local   <none>           <none>
kube-system     kube-scheduler-k8s-master1.lab.local                        1/1     Running     32 (12h ago)   17d     10.0.61.10       k8s-master1.lab.local   <none>           <none>
kube-system     kube-scheduler-k8s-master2.lab.local                        1/1     Running     33 (12h ago)   17d     10.0.61.11       k8s-master2.lab.local   <none>           <none>
kube-system     kube-scheduler-k8s-master3.lab.local                        1/1     Running     30 (12h ago)   17d     10.0.61.12       k8s-master3.lab.local   <none>           <none>
monitoring      alertmanager-kube-prometheus-stack-alertmanager-0           2/2     Running     14 (11h ago)   4d5h    10.244.62.35     k8s-worker1.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-grafana-76d659dc49-jzmk4              4/4     Running     31 (11h ago)   4d5h    10.244.62.58     k8s-worker1.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-kube-state-metrics-567d49447b-tq8sg   1/1     Running     9 (11h ago)    4d5h    10.244.62.57     k8s-worker1.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-operator-7479866ff6-2dsq8             1/1     Running     8 (11h ago)    4d5h    10.244.62.53     k8s-worker1.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-prometheus-node-exporter-8dffc        1/1     Running     8 (11h ago)    4d5h    10.0.64.12       k8s-worker3.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-prometheus-node-exporter-8dj6h        1/1     Running     6 (11h ago)    4d5h    10.0.64.11       k8s-worker2.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-prometheus-node-exporter-kk2ml        1/1     Running     7 (11h ago)    4d5h    10.0.64.10       k8s-worker1.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-prometheus-node-exporter-mkwcn        1/1     Running     6 (12h ago)    4d5h    10.0.61.10       k8s-master1.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-prometheus-node-exporter-th2qz        1/1     Running     6 (12h ago)    4d5h    10.0.61.11       k8s-master2.lab.local   <none>           <none>
monitoring      kube-prometheus-stack-prometheus-node-exporter-xcdmk        1/1     Running     6 (12h ago)    4d5h    10.0.61.12       k8s-master3.lab.local   <none>           <none>
monitoring      loki-0                                                      2/2     Running     13 (11h ago)   4d5h    10.244.207.66    k8s-worker2.lab.local   <none>           <none>
monitoring      loki-canary-56rnc                                           1/1     Running     6 (11h ago)    4d5h    10.244.207.119   k8s-worker2.lab.local   <none>           <none>
monitoring      loki-canary-fdm8f                                           1/1     Running     7 (11h ago)    4d5h    10.244.62.7      k8s-worker1.lab.local   <none>           <none>
monitoring      loki-canary-kgp8g                                           1/1     Running     8 (11h ago)    4d5h    10.244.29.185    k8s-worker3.lab.local   <none>           <none>
monitoring      prometheus-kube-prometheus-stack-prometheus-0               2/2     Running     8 (11h ago)    2d6h    10.244.29.182    k8s-worker3.lab.local   <none>           <none>
monitoring      promtail-54nsf                                              1/1     Running     7 (11h ago)    4d5h    10.244.62.56     k8s-worker1.lab.local   <none>           <none>
monitoring      promtail-9s5d9                                              1/1     Running     6 (11h ago)    4d5h    10.244.207.75    k8s-worker2.lab.local   <none>           <none>
monitoring      promtail-9vfn7                                              1/1     Running     8 (11h ago)    4d5h    10.244.29.180    k8s-worker3.lab.local   <none>           <none>
monitoring      promtail-bhbmn                                              1/1     Running     6 (12h ago)    4d5h    10.244.14.162    k8s-master2.lab.local   <none>           <none>
monitoring      promtail-nwmxd                                              1/1     Running     6 (12h ago)    4d5h    10.244.25.225    k8s-master3.lab.local   <none>           <none>
monitoring      promtail-vm2k5                                              1/1     Running     6 (12h ago)    4d5h    10.244.43.182    k8s-master1.lab.local   <none>           <none>
remediation     remediation-56bdddfcd7-t8fvv                                2/2     Running     2 (12h ago)    19h     10.244.14.163    k8s-master2.lab.local   <none>           <none>
vault           vault-agent-injector-5877589b57-4h2ts                       1/1     Running     3 (12h ago)    2d      10.244.43.181    k8s-master1.lab.local   <none>           <none>
vault           vault-agent-injector-5877589b57-vphh7                       1/1     Running     3 (12h ago)    2d      10.244.25.224    k8s-master3.lab.local   <none>           <none>
```

**PVC state:**
```
kubectl get pvc -A
```
```
NAMESPACE    NAME                                                                                                   STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   VOLUMEATTRIBUTESCLASS   AGE
apps         wordpress-data                                                                                         Bound    pvc-69f14fb9-0ca0-48ae-a84e-afa0a5ee8822   15Gi       RWX            nfs-retain     <unset>                 4d5h
database     mariadb-data-mariadb-0                                                                                 Bound    pvc-6b39c4df-eeea-4f60-a3f4-fa89da8f55ee   15Gi       RWO            nfs-database   <unset>                 4h36m
monitoring   alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0   Bound    pvc-a605bec9-80ce-4053-bae7-a67d9aab7816   5Gi        RWO            nfs-retain     <unset>                 8d
monitoring   kube-prometheus-stack-grafana                                                                          Bound    pvc-f640539b-d6ab-484f-8575-447d02c41788   5Gi        RWO            nfs-retain     <unset>                 4d5h
monitoring   prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0           Bound    pvc-5e8d9355-ec58-4781-bf03-fc630111d7b5   20Gi       RWO            nfs-retain     <unset>                 8d
monitoring   storage-loki-0                                                                                         Bound    pvc-aed20697-1f67-4485-89a7-a5c02dbc7dde   50Gi       RWO            nfs-retain     <unset>                 4d5h
```

**PV state (no Released PVs):**
```
NAME                                       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                                                                                             STORAGECLASS
pvc-5e8d9355-ec58-4781-bf03-fc630111d7b5   20Gi       RWO            Retain           Bound    monitoring/prometheus-kube-prometheus-stack-prometheus-db-prometheus-kube-prometheus-stack-prometheus-0           nfs-retain
pvc-69f14fb9-0ca0-48ae-a84e-afa0a5ee8822   15Gi       RWX            Retain           Bound    apps/wordpress-data                                                                                               nfs-retain
pvc-6b39c4df-eeea-4f60-a3f4-fa89da8f55ee   15Gi       RWO            Retain           Bound    database/mariadb-data-mariadb-0                                                                                   nfs-database
pvc-a605bec9-80ce-4053-bae7-a67d9aab7816   5Gi        RWO            Retain           Bound    monitoring/alertmanager-kube-prometheus-stack-alertmanager-db-alertmanager-kube-prometheus-stack-alertmanager-0   nfs-retain
pvc-aed20697-1f67-4485-89a7-a5c02dbc7dde   50Gi       RWO            Retain           Bound    monitoring/storage-loki-0                                                                                         nfs-retain
pvc-f640539b-d6ab-484f-8575-447d02c41788   5Gi        RWO            Retain           Bound    monitoring/kube-prometheus-stack-grafana                                                                          nfs-retain
```

**CSI controller location:**
```
kubectl get pods -n kube-system -o wide | grep csi-nfs-controller
```
```
csi-nfs-controller-8455c76c5f-99nbm   5/5   Running   k8s-worker2.lab.local (10.0.64.11)
csi-nfs-controller-8455c76c5f-snggk   5/5   Running   k8s-worker1.lab.local (10.0.64.10)
```

**Key pod placement summary:**
| Component | Node |
|-----------|------|
| WordPress replica 1 | worker1 |
| WordPress replica 2 | worker2 |
| WordPress replica 3 | worker3 |
| MariaDB-0 | worker3 |
| CSI controller 1 | worker1 |
| CSI controller 2 | worker2 |
| Prometheus | worker3 |
| Grafana | worker1 |
| Loki | worker2 |
| Alertmanager | worker1 |

**WordPress accessible:** YES
**MariaDB healthy:** YES
**Flux healthy:** YES

---

## Scenario 1 — Single Worker NFS Interface Down

**Worker affected:** k8s-worker1.lab.local (10.0.64.10 mgmt / 10.0.40.201 storage)
**NFS interface:** eth1 (10.0.40.201/24)
**Time started:** 2026-04-13 ~21:50 (timestamp from dmesg: 43808s uptime)
**Time restored:**

### Pods on worker1 (expected impact)
```
apps            wordpress-79f66bd68b-2jh6q          — NFS dependent (soft mount)
flux-system     helm-controller                     — NO NFS dependency
flux-system     kustomize-controller                — NO NFS dependency
flux-system     source-controller                   — NO NFS dependency
ingress-nginx   ingress-nginx-controller            — NO NFS dependency
kube-system     csi-nfs-controller (1 of 2)         — CSI provisioning (1 replica still on worker2)
kube-system     csi-nfs-node                        — Local NFS mounter
monitoring      alertmanager-0                      — NFS dependent (soft mount)
monitoring      grafana                             — NFS dependent (soft mount)
monitoring      kube-state-metrics                  — NO NFS dependency
monitoring      prometheus-operator                 — NO NFS dependency
monitoring      promtail                            — NO NFS dependency
```

### Pre-Outage NFS State on worker1

**NFS mounts (mount | grep nfs):**
```
# Grafana PVC - NFS v3, soft mount, 3s timeout
10.0.40.120:/volume1/k8s-dev/pvc-f640539b-d6ab-484f-8575-447d02c41788 → Grafana storage

# Alertmanager PVC - NFS v4.2, soft mount, 3s timeout
10.0.40.120:/volume1/k8s-dev/pvc-a605bec9-80ce-4053-bae7-a67d9aab7816 → Alertmanager storage

# WordPress PVC - NFS v3, soft mount, 3s timeout (RWX - shared across all WP pods)
10.0.40.120:/volume1/k8s-dev/pvc-69f14fb9-0ca0-48ae-a84e-afa0a5ee8822 → WordPress uploads
```

**Mount options explained:**
| Option | Meaning |
|--------|---------|
| `soft` | Returns error after timeout instead of hanging indefinitely |
| `timeo=30` | 3 second timeout (30 = 30 tenths of a second) |
| `retrans=3` | Retry 3 times before failing |
| `vers=3` / `vers=4.2` | NFS protocol version |
| `rsize/wsize=524288` | 512KB read/write block size |
| `proto=tcp` | Using TCP transport |
| `fatal_neterrors=none` | Network errors don't immediately fail |

**NAS exports visible (showmount -e 10.0.40.120):**
```
/volume1/k8s-dev      10.0.40.203,10.0.40.202,10.0.40.201  ← DEV workers
/volume1/k8s-prod     10.0.40.103,10.0.40.102,10.0.40.101  ← PROD workers
/volume1/Backups      10.0.40.100,10.0.40.110              ← Proxmox hosts
```

**Kernel NFS messages (dmesg | grep nfs):** Clean - no errors

**NFS interface identified:**
```
eth1: 10.0.40.201/24  ← This is the interface to take down
```

---

### During Outage (Kubernetes Level)

**Pod behavior on affected worker (worker1):**
```
apps        wordpress-79f66bd68b-2jh6q              2/2   Running              ← Still Running!
flux-system helm-controller                         1/1   Running              ← No NFS, unaffected
flux-system kustomize-controller                    1/1   Running              ← No NFS, unaffected
flux-system source-controller                       1/1   Running              ← No NFS, unaffected
ingress-nginx ingress-nginx-controller              1/1   Running              ← No NFS, unaffected
monitoring  alertmanager-0                          2/2   Running              ← Still Running (soft mount)
monitoring  grafana                                 3/4   CreateContainerError ← NFS FAILURE!
monitoring  kube-state-metrics                      1/1   Running              ← No NFS, unaffected
monitoring  prometheus-operator                     1/1   Running              ← No NFS, unaffected
```

**Key observation:** Grafana hit CreateContainerError (cannot mount NFS volume for container start).
WordPress and Alertmanager still show Running despite stale NFS mounts.

**Grafana failure sequence (from kubectl describe):**
```
1. Readiness probe failed: context deadline exceeded (NFS I/O hanging)
2. Liveness probe failed: HTTP 503 (Grafana couldn't serve health check)
3. Container killed by kubelet (liveness failure)
4. Container RESTART FAILED:
   Error: failed to stat "/var/lib/kubelet/pods/.../pvc-f640539b.../mount":
   input/output error
```
✅ **Soft mount working correctly** - returned I/O error instead of hanging forever.
❌ **Single replica problem** - Grafana down completely (1 replica on affected worker).

**Grafana status:** 503 Service Unavailable (no healthy backends)
**Root cause:** Container restart requires NFS volume stat → I/O error → CreateContainerError loop

**WordPress endpoints (still includes worker1 pod!):**
```bash
kubectl get endpoints wordpress -n apps
```
```
NAME        ENDPOINTS                                            AGE
wordpress   10.244.207.117:80,10.244.29.129:80,10.244.62.14:80   4d5h
            (worker2)          (worker3)          (worker1-stale NFS)
```
⚠️ **ISSUE:** Worker1 pod (10.244.62.14) still in endpoints despite NFS outage!

**Root cause analysis:**
```yaml
# BEFORE (problematic):
readinessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif  # ← Local file in container image
                                          # NOT on NFS mount!
volumeMounts:
  - mountPath: /var/www/html/wp-content  # ← Only wp-content is on NFS
```

The readiness probe checked a file baked into the container image, not the NFS mount.
Result: NFS fails → probe still passes → pod stays Ready → traffic still routed → user requests fail.

**Why not use liveness probe for NFS check?**
- Liveness failure → container restart on SAME node
- NFS still broken on that node → restart fails again → useless restart loop
- Pods don't reschedule to different nodes on liveness failure

**FIX APPLIED:**
```yaml
# AFTER (correct):
readinessProbe:
  httpGet:
    path: /wp-content/index.php  # ← On NFS mount - detects storage failure
  timeoutSeconds: 5              # ← Longer timeout for NFS latency

livenessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif  # ← Keep local - no useless restarts
```

Now: NFS fails → readiness fails → pod removed from endpoints → traffic diverts to healthy pods

**WordPress site accessibility:**
- Browser: ✅ Site loads (mostly hitting healthy workers)
- curl from master1: ⚠️ 1/10 requests timeout (hitting worker1)

**Traffic routing test (10 curl requests):**
```
Request 1: HTTP 200 - 0.259s  ✅
Request 2: HTTP 200 - 0.150s  ✅
Request 3: HTTP 200 - 0.151s  ✅
Request 4: HTTP 200 - 0.157s  ✅
Request 5: HTTP 000 - 3.002s  ❌ TIMEOUT - hit worker1 (broken NFS)
Request 6: HTTP 200 - 0.150s  ✅
Request 7: HTTP 200 - 0.153s  ✅
Request 8: HTTP 200 - 0.159s  ✅
Request 9: HTTP 200 - 0.147s  ✅
Request 10: HTTP 200 - 0.153s ✅
```

**Ingress-nginx logs (only shows successful backends):**
```
10.244.29.129:80   = worker3 ✅
10.244.207.117:80  = worker2 ✅
(10.244.62.14 worker1 not in success logs - requests timeout)
```

⚠️ **CONFIRMED:** Ingress still routing ~33% of traffic to broken worker1 pod.
Readiness probe passes (checks local file, not NFS) → pod stays in endpoints → traffic fails.

**Nginx error log proof (requests to worker1 = 10.244.62.14):**
```
20:01:40 → 10.244.62.14:80 → HTTP 499 → 4.993s  (curl timeout)
20:01:57 → 10.244.62.14:80 → HTTP 499 → 4.994s  (curl timeout)
20:02:39 → 10.244.62.14:80 → HTTP 499 → 33.213s (curl timeout - long!)
20:34:15 → 10.244.62.14:80 → HTTP 499 → 2.216s  (browser request timeout)
```
HTTP 499 = Client closed connection (nginx code for client-side timeout).
Proves traffic routed to broken pod → user sees failure.

**Flux status:** ✅ All healthy (no NFS dependency)
```
apps            dev@sha1:adc0d2fd   True    Applied
flux-system     dev@sha1:adc0d2fd   True    Applied
infrastructure  dev@sha1:adc0d2fd   True    Applied
```

**MariaDB behavior:**
```
Status: Unaffected (running on worker3)
```

**CSI controller behavior:**
```
1 replica on worker1 (degraded - cannot reach NAS)
1 replica on worker2 (healthy - can still provision)
```

**NFS debug on affected worker (during outage):**

**1. Interface confirmed DOWN:**
```bash
ip link show eth1 | grep state
```
```
3: eth1: <BROADCAST,MULTICAST> mtu 1500 qdisc fq_codel state DOWN mode DEFAULT group default qlen 1000
```
✅ Interface is DOWN - outage simulated successfully

**2. NFS mounts still visible but stale:**
```bash
mount | grep nfs
```
```
10.0.40.120:/volume1/k8s-dev/pvc-f640539b-d6ab-484f-8575-447d02c41788 → Grafana (stale)
10.0.40.120:/volume1/k8s-dev/pvc-a605bec9-80ce-4053-bae7-a67d9aab7816 → Alertmanager (stale)
10.0.40.120:/volume1/k8s-dev/pvc-69f14fb9-0ca0-48ae-a84e-afa0a5ee8822 → WordPress (stale)
```
⚠️ Mounts still listed in mount table but are now unreachable (stale)

**3. showmount hangs (cannot reach NAS):**
```bash
showmount -e 10.0.40.120
```
```
(hangs indefinitely - had to Ctrl+C)
```
✅ Expected - NAS is unreachable from worker1

**4. Kernel NFS errors flooding dmesg:**
```bash
dmesg | grep nfs
```
```
[43808.495309] nfs: server 10.0.40.120 not responding, timed out
[43811.647355] nfs: server 10.0.40.120 not responding, timed out
[43820.207409] nfs: server 10.0.40.120 not responding, timed out
[43820.497403] nfs: server 10.0.40.120 not responding, timed out
[43820.687383] nfs: server 10.0.40.120 not responding, timed out
... (continuous timeout messages every few seconds)
[43916.720171] nfs: server 10.0.40.120 not responding, timed out
```
✅ Kernel detecting NFS server unreachable - soft mount timeouts firing

**Ingress-nginx status:** UP ✅ (no NFS dependency)
**Vault status:** UP ✅ (no NFS dependency)
**Flux status:** UP ✅ (no NFS dependency)

### After Restore

**Time restored:** 2026-04-13 ~22:40
**Command:** `ip link set eth1 up` on worker1

**Interface restored:**
```bash
ip link show eth1 | grep state
```
```
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP
```

**NFS connectivity restored:**
```bash
showmount -e 10.0.40.120
```
```
/volume1/k8s-dev      10.0.40.203,10.0.40.202,10.0.40.201  ✅
/volume1/k8s-prod     10.0.40.103,10.0.40.102,10.0.40.101
```

**NFS mounts recovered (no stale mounts):**
```bash
mount | grep nfs
```
All mounts still present and functional - soft mounts recovered automatically.

**Grafana auto-recovered:**
```
kube-prometheus-stack-grafana-76d659dc49-jzmk4   4/4   Running   32 (40m ago)
```
✅ Container restarted automatically when NFS became available (restart #32).

**All pods on worker1 healthy:**
```
apps        wordpress      2/2   Running   ✅
flux-system helm-ctrl      1/1   Running   ✅
flux-system kustomize-ctrl 1/1   Running   ✅
flux-system source-ctrl    1/1   Running   ✅
ingress     nginx-ctrl     1/1   Running   ✅
monitoring  alertmanager   2/2   Running   ✅
monitoring  grafana        4/4   Running   ✅ (auto-recovered)
monitoring  kube-state     1/1   Running   ✅
monitoring  prom-operator  1/1   Running   ✅
```

**WordPress traffic test (10 requests - all successful):**
```
Request 1:  HTTP 200 - 0.606s
Request 2:  HTTP 200 - 0.256s
Request 3:  HTTP 200 - 0.168s
Request 4:  HTTP 200 - 0.165s
Request 5:  HTTP 200 - 0.155s
Request 6:  HTTP 200 - 0.149s
Request 7:  HTTP 200 - 0.150s
Request 8:  HTTP 200 - 0.145s
Request 9:  HTTP 200 - 0.152s
Request 10: HTTP 200 - 0.164s
```
✅ All 10 requests successful (vs 1/10 timeout during outage).

**Grafana accessible:** HTTP 302 ✅ (redirect to login - working)

**Automatic recovery:** YES
- Grafana: Auto-recovered when NFS restored (kubelet restarted container)
- WordPress: Continued serving (was already running)
- Alertmanager: Continued running (soft mount)
- NFS mounts: No stale mounts - soft mount auto-recovered

**Manual intervention needed:** NO
**Stale mounts found:** NO ✅
**MariaDB data intact:** YES (unaffected - on worker3)
**WordPress accessible:** YES ✅

**Result:** PASS ✅
**Notes:**
- Soft mount (`soft` option) worked correctly - returned I/O errors instead of hanging
- Grafana auto-recovered after NFS restored (container restart succeeded)
- No stale mounts - soft mounts recovered automatically
- ⚠️ Issue found: WordPress readiness probe doesn't detect NFS failure (traffic still routed to broken pod during outage)

---

## Fixes Applied During Test

### Fix 1: Grafana HA (3 replicas)
**File:** `kubernetes/dev/deployments/apps/monitoring/helm-release.yaml`
```yaml
grafana:
  replicas: 3
  affinity:
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app.kubernetes.io/name: grafana
          topologyKey: kubernetes.io/hostname
  persistence:
    accessModes:
      - ReadWriteMany  # Changed from RWO to support multiple replicas
```
**Result:** 3 Grafana pods running on worker1, worker2, worker3 ✅

### Fix 2: WordPress Readiness Probe (NFS check)
**File:** `kubernetes/dev/deployments/apps/wordpress/deployment.yaml`
```yaml
# BEFORE (problematic):
readinessProbe:
  httpGet:
    path: /wp-includes/images/blank.gif  # Local file - doesn't detect NFS failure

# AFTER (fixed):
readinessProbe:
  httpGet:
    path: /wp-content/index.php  # On NFS mount - detects storage failure
  timeoutSeconds: 5  # Longer timeout for NFS
```
**Result:** Pod will be removed from endpoints when NFS fails ✅

### Validation Results ✅

**WordPress readiness probe fix - VALIDATED:**
```
# During NFS outage on worker1:
wordpress-...-pxlpm   1/2   Running   worker1  ← NOT READY (correct!)
wordpress-...-mb4ql   2/2   Running   worker2  ← Ready
wordpress-...-484ht   2/2   Running   worker3  ← Ready

# Endpoints (worker1 REMOVED):
wordpress   10.244.207.88:80,10.244.29.139:80  ← Only worker2 + worker3!

# Traffic test (20 requests):
ALL HTTP 200 - 100% success ✅ (vs 10% timeout before fix)
```

**Before vs After:**
| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Worker1 pod status | 2/2 Ready (wrong) | 1/2 Ready (correct) |
| Endpoints | 3 pods (broken included) | 2 pods (healthy only) |
| Traffic success | ~90% (timeouts) | 100% ✅ |

**Grafana HA fix - VALIDATED:**
- 3 replicas running on worker1, worker2, worker3
- Anti-affinity working correctly
- If 1 worker fails, 2/3 replicas still serve traffic

**After restore (eth1 up):**
```bash
kubectl get pods -o wide -n apps
```
```
wordpress-...-484ht   2/2   Running   worker3 ✅
wordpress-...-mb4ql   2/2   Running   worker2 ✅
wordpress-...-pxlpm   2/2   Running   worker1 ✅  ← Recovered to 2/2
```

```bash
kubectl get endpoints wordpress -n apps
```
```
wordpress   10.244.207.88:80,10.244.29.139:80,10.244.62.9:80  ← All 3 back in endpoints
```

**Traffic test after restore:**
```
Request 1:  HTTP 000 - 3.002s  ← Brief window during NFS reconnect
Request 2:  HTTP 000 - 3.002s  ← Brief window during NFS reconnect
Request 3:  HTTP 200 - 0.606s  ✅
Request 4:  HTTP 200 - 0.870s  ✅
Request 5-10: HTTP 200         ✅
```
Note: First 2 requests hit worker1 during NFS mount recovery. After ~6s, fully recovered.

---

## Related Cases

- TS-K8S-003 — NFS hard mount pod hangs
- TS-K8S-015 — Stale NFS mount on CSI restart
- TS-K8S-018 — CSI controller network placement
- TS-K8S-026 — Released PV cleanup
- `disaster-recovery/nginx-dr-test.md` — NGINX layer failures (references readiness probe endpoint removal)