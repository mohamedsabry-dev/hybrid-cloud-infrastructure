# Runbook: MariaDB StorageClass Migration
# From: nfs-retain (soft mount) → nfs-database (hard mount)
# Tested: 2026-04-13 | DEV cluster | SUCCESSFUL

---

## Why This Migration

MariaDB was running on `nfs-retain` StorageClass which uses `soft` NFS mount.
Soft mount returns I/O error to the application after timeout — correct for stateless apps
but wrong for databases. InnoDB cannot handle I/O errors mid-write and crashes.

Root cause documented in: TS-K8S-015 (stale NFS mount → MariaDB CrashLoopBackOff)

`nfs-database` StorageClass uses `hard` NFS mount — MariaDB waits indefinitely for NFS
to recover instead of crashing. Data integrity preserved over availability.

---

## Pre-Operation Notes

StatefulSet `volumeClaimTemplate` is immutable after creation. You cannot change
`storageClassName` by editing and pushing the StatefulSet YAML — Kubernetes will reject
the update. The StatefulSet must be fully deleted and recreated.

StatefulSet deletion does NOT automatically delete PVCs — this is by design to protect data.
PVC must be deleted manually after StatefulSet and pod are gone.

With `reclaimPolicy: Retain`, deleting the PVC leaves the PV in Released state and the
NAS directory untouched. Data is safe.

StatefulSet only creates PVCs when scheduling pods. With `replicas: 0`, no PVC is created
automatically — must be created manually before starting the pod.

---

## PRE-OPERATION

### Step 1 — Backup old NAS directory
Safety net against human error during the copy operation.
Retain policy protects against K8s deletion but not against wrong cp/rm commands.

```bash
# SSH into NAS or use NAS UI
cp -r /volume1/k8s-dev/pvc-f54d8831-2f9b-4cb7-8fa8-4b9b2f3ee167/ \
      /volume1/k8s-dev/mariadb-backup/

# Verify backup complete
ls -la /volume1/k8s-dev/mariadb-backup/
# Must see: ibdata1, ib_logfile0, wordpress/, mysql/, sys/, performance_schema/
```

### Step 2 — Suspend Flux apps Kustomization
Prevent Flux from reverting manual scaling operations mid-procedure.
Must suspend BEFORE scaling WordPress — otherwise Flux reconciles replicas back
to Git value within 5 minutes.

```bash
flux suspend kustomization apps
flux get kustomization
# apps should show SUSPENDED: True
```

---

## CLEAN SHUTDOWN

### Step 3 — Scale WordPress to 0
Stop all incoming database transactions before touching MariaDB.

```bash
kubectl scale deployment wordpress -n apps --replicas=0
kubectl get pods -n apps -w
# Wait until: No resources found in apps namespace
```

### Step 4 — Verify database state before flush (optional but recommended)
Confirm no pending transactions before proceeding.

```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p

# Check active connections
> SHOW PROCESSLIST;
# Expected: only your current connection

# Check open transactions
> SELECT * FROM information_schema.INNODB_TRX;
# Expected: Empty set

# Check InnoDB status
> SHOW ENGINE INNODB STATUS\G
# Check: Pending flushes = 0, Pending reads = 0, Pending writes = 0
# Note: Modified dirty pages in buffer pool are normal — flushed on shutdown

> EXIT;
```

### Step 5 — Flush MariaDB (belt and suspenders)

```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p

> FLUSH TABLES WITH READ LOCK;
# Forces all dirty pages to disk, blocks new writes

> SHOW PROCESSLIST;
# Confirm only your connection remains

> EXIT;
```

### Step 6 — Scale MariaDB to 0 (clean InnoDB shutdown)
SIGTERM triggers InnoDB clean shutdown: flushes dirty pages, writes checkpoint,
closes all files. Safe to copy NAS directory after this.

```bash
kubectl scale statefulset mariadb -n database --replicas=0
kubectl get pods -n database -w
# Wait until: No resources found in database namespace
```

### Step 7 — Delete StatefulSet
Required because volumeClaimTemplate is immutable.
Pod must be fully gone before this step — pvc-protection finalizer blocks PVC
deletion if pod is still running.

```bash
kubectl delete statefulset mariadb -n database
# statefulset.apps "mariadb" deleted

# Verify StatefulSet gone
kubectl get statefulset -n database
# No resources found
```

### Step 8 — Delete old PVC manually
StatefulSet deletion does NOT delete PVCs automatically (by design).
Must delete manually. PV goes Released, NAS directory untouched.

```bash
# Confirm pod is gone first
kubectl get pods -n database
# No resources found

kubectl delete pvc mariadb-data-mariadb-0 -n database

# Verify PV is now Released (not deleted)
kubectl get pv | grep f54d8831
# STATUS: Released ✅ — data safe on NAS
```

---

## FLUX CREATES NEW SETUP

### Step 9 — Update Git and push

Update `statefulset.yaml` with two changes:
```yaml
# Change 1: new StorageClass
storageClassName: nfs-database

# Change 2: replicas 0 — prevents pod starting before data copy
replicas: 0
```

```bash
git add -A
git commit -m "migrate: mariadb storage to nfs-database hard mount, replicas 0 pending data copy"
git push origin dev
```

### Step 10 — Resume Flux

```bash
flux resume kustomization apps
flux reconcile kustomization apps --with-source

flux get kustomization
# apps: READY True, SUSPENDED False
```

Flux creates new StatefulSet with replicas: 0.
WordPress comes back up (replicas: 3 in Git).

### Step 11 — Verify WordPress recovered

```bash
kubectl get pods -n apps -w
# All 3 wordpress pods: Running 2/2 ✅
```

### Step 12 — Create PVC manually

⚠️ StatefulSet with replicas: 0 does NOT create PVCs automatically.
PVCs are only created when a pod needs to be scheduled.
Must create manually — StatefulSet will adopt it when scaled to 1.

PVC name must match exactly: `<volumeClaimTemplate.name>-<statefulset-name>-<ordinal>`
= `mariadb-data-mariadb-0`

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb-data-mariadb-0
  namespace: database
spec:
  storageClassName: nfs-database
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 15Gi
EOF

kubectl get pvc -n database -w
# mariadb-data-mariadb-0   Bound   pvc-<new-uuid>   15Gi   RWO   nfs-database ✅
```

### Step 13 — Identify new NAS directory

```bash
# Get PV name from PVC
kubectl get pvc mariadb-data-mariadb-0 -n database -o jsonpath='{.spec.volumeName}'

# Get NAS subdirectory from PV
kubectl get pv <pv-name> -o yaml | grep subdir
# subdir: pvc-<new-uuid>
```

---

## DATA MIGRATION

### Step 14 — Copy data from old NAS directory to new NAS directory

```bash
# SSH into NAS or use NAS file manager
cp -r /volume1/k8s-dev/pvc-f54d8831-2f9b-4cb7-8fa8-4b9b2f3ee167/* \
      /volume1/k8s-dev/pvc-<new-uuid>/
```

### Step 15 — Verify copy completed

```bash
ls -la /volume1/k8s-dev/pvc-<new-uuid>/
# Must see ALL of:
# ibdata1          ← InnoDB system tablespace
# ib_logfile0      ← InnoDB redo log
# ib_logfile1      ← InnoDB redo log
# ibtmp1           ← InnoDB temp tablespace
# wordpress/       ← WordPress database
# mysql/           ← MySQL system database
# sys/             ← System schema
# performance_schema/
```

---

## START MARIADB ON NEW PVC

### Step 16 — Push replicas: 1 to Git

```bash
# Update statefulset.yaml: replicas: 0 → replicas: 1
git add -A
git commit -m "migrate: mariadb replicas 1 on nfs-database hard mount"
git push origin dev

flux reconcile kustomization apps --with-source
```

### Step 17 — Watch MariaDB start

```bash
kubectl get pods -n database -w
# mariadb-0   Init:0/1 (vault-agent-init authenticating)
# mariadb-0   PodInitializing
# mariadb-0   Running 1/2 (MariaDB container ready)
# mariadb-0   Running 2/2 (vault-agent sidecar ready) ✅
```

### Step 18 — Verify data intact

```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mariadb -u root -p

> show databases;
# wordpress present ✅

> use wordpress;
> show tables;
# All WordPress tables present ✅

> SELECT COUNT(*) FROM wp_posts;
# Record count matches pre-migration ✅

> EXIT;
```

### Step 19 — Verify WordPress serving

```bash
# Check pods healthy
kubectl get pods -n apps
# All 3: Running 2/2 ✅

# Check WordPress accessible
curl -I https://wordpress-dev.lab.local
# HTTP/2 200 ✅

# Verify media accessible
# Open WordPress admin → Media Library
# Confirm all uploaded files visible and downloadable ✅
```

### Step 20 — Verify new StorageClass

```bash
kubectl get pvc -n database
# NAME                     STATUS  STORAGECLASS   CAPACITY
# mariadb-data-mariadb-0   Bound   nfs-database   15Gi ✅

kubectl get pv | grep 6b39c4df
# STORAGECLASS: nfs-database ✅
```

---

## CLEANUP

### Step 21 — Delete old Released PV

```bash
kubectl delete pv pvc-f54d8831-2f9b-4cb7-8fa8-4b9b2f3ee167
kubectl get pv | grep f54d8831
# No output — gone ✅
```

### Step 22 — Delete old NAS directory

Via NAS UI or SSH:
```bash
rm -rf /volume1/k8s-dev/pvc-f54d8831-2f9b-4cb7-8fa8-4b9b2f3ee167/
```

### Step 23 — Delete backup after confidence period

Wait at least 24 hours of normal operation before deleting backup.
```bash
rm -rf /volume1/k8s-dev/mariadb-backup/
```

---

## Key Learnings From This Operation

| Discovery | Detail |
|---|---|
| StatefulSet PVC not created at replicas: 0 | Must create PVC manually — StatefulSet adopts existing PVC by name |
| StatefulSet does not delete PVCs | Must delete PVC manually after StatefulSet deletion |
| Flush not required if no active transactions | Verified via SHOW PROCESSLIST + INNODB_TRX before flush |
| Flux must be suspended before scaling | Otherwise Flux reconciles replicas back to Git within 5 minutes |
| Backup is for human error not K8s deletion | Retain policy protects from K8s — backup protects from wrong cp/rm |
| PVC name formula | volumeClaimTemplate.name + "-" + statefulset-name + "-" + ordinal |
