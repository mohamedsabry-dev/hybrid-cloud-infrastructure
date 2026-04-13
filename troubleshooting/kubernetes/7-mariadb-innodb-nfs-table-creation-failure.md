# TS-K8S-007 | 2026-04-02 | RESOLVED

## 1. Context

- **System:** MariaDB StatefulSet / InnoDB / NFS Storage
- **Environment:** k8s-prod cluster (also applied fix to dev)
- **Related Components:** NFS CSI driver, InnoDB storage engine, Vault secrets injection
- **Discovered During:** WordPress installation attempting to create database tables
- **Related Cases:**
  - TS-K8S-003 — NFS hard mount causing pod hangs (introduced soft mount that caused this issue)
  - TS-K8S-006 — NFS complete guide (architecture reference)
  - TS-K8S-015 — Stale NFS mount on CSI restart (soft mount caused MariaDB CrashLoopBackOff — same root tradeoff)

---

## 2. Issue

**Symptom:** MariaDB fails to create tables with error 168 on NFS storage.

**WordPress Installation Error:**
```
WordPress database error: [Can't create table `wordpress`.`wp_users` (errno: 168 "Unknown (generic) error from engine")]
CREATE TABLE wp_users ( ID bigint(20) unsigned NOT NULL auto_increment, ... )
```

**Manual Table Creation Also Fails:**
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
# ERROR 1005 (HY000): Can't create table `wordpress`.`test` (errno: 168 "Unknown (generic) error from engine")
```

**InnoDB Logs Show Storage Errors:**
```
InnoDB: Retry attempts for reading partial data failed.
```

**Impact:** WordPress installation blocked, no tables can be created in any database.

---

## 3. Analysis

### Step 1: Verify Vault Secrets Injection

```bash
kubectl exec mariadb-0 -n database -c mariadb -- cat /vault/secrets/db-creds
# MYSQL_ROOT_PASSWORD=<redacted>
# MYSQL_PASSWORD=<redacted>
```

Finding: Vault secrets injection working correctly.

### Step 2: Check Database/User Creation

```bash
kubectl logs mariadb-0 -n database -c mariadb
# [Note] [Entrypoint]: Creating database wordpress
# [Note] [Entrypoint]: Creating user wordpress
```

Finding: Database and user created successfully.

### Step 3: Verify NFS Mount

```bash
kubectl exec mariadb-0 -n database -c mariadb -- df -h /var/lib/mysql
# 10.0.40.120:/volume1/k8s-prod/pvc-... 1.8T 221G 1.6T 13%
```

Finding: NFS mount working.

### Step 4: Check Permissions

```bash
kubectl exec mariadb-0 -n database -c mariadb -- ls -la /var/lib/mysql/
# drwxrwsr-x. 6 mysql mysql 4096 ...
```

Finding: Permissions correct.

### Step 5: Check InnoDB Flush Method (ROOT CAUSE)

```bash
kubectl exec mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | O_DIRECT |
```

Finding: InnoDB using O_DIRECT which is incompatible with NFS.

---

## 4. Root Cause

**InnoDB `innodb_flush_method` was set to `O_DIRECT`.**

O_DIRECT bypasses the OS page cache and attempts direct I/O to disk. **NFS does not properly support O_DIRECT operations**, causing table creation to fail with generic error 168.

### The Soft Mount Connection

At this point in the journey, MariaDB was using `soft` mount options from TS-K8S-003. The soft mount means:
- NFS I/O errors return to the application after timeout instead of hanging
- O_DIRECT failures are immediately surfaced as InnoDB errors
- Crash is fast and visible — which is what led to discovering this issue

With hard mount + O_DIRECT, MariaDB would hang silently instead of crashing. The soft mount from TS-K8S-003 made this bug visible faster — but soft mount is still wrong for databases. See TS-K8S-015 for the full consequence.

---

## 5. Solution

### Fix 1: Set innodb_flush_method=fsync

Add `--innodb-flush-method=fsync` to MariaDB startup command:

```yaml
command:
  - /bin/bash
  - -c
  - |
    if [ -f /vault/secrets/db-creds ]; then
      export $(cat /vault/secrets/db-creds | xargs)
    fi
    exec docker-entrypoint.sh mysqld --innodb-flush-method=fsync
```

### Why fsync Works

- `fsync` uses standard POSIX file sync operations
- Compatible with NFS and all network filesystems
- Slightly higher overhead than O_DIRECT but reliable

### Fix 2: TCP Socket Probes

Original probes used `mysqladmin ping` which requires authentication:

```yaml
# PROBLEM: Fails when root has password
livenessProbe:
  exec:
    command: [mysqladmin, ping, -h, localhost]
```

Fixed to use TCP socket check:

```yaml
# SOLUTION: TCP check doesn't need password
livenessProbe:
  tcpSocket:
    port: 3306
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Fix 3: Use nfs-database StorageClass (Added in TS-K8S-015)

After this case was resolved, TS-K8S-015 revealed that soft mount also causes MariaDB to crash when the CSI node pod restarts. The permanent fix is to use the `nfs-database` StorageClass with hard mount for all database workloads.

```yaml
# StatefulSet volumeClaimTemplate
volumeClaimTemplates:
  - metadata:
      name: mariadb-data
    spec:
      storageClassName: nfs-database   # hard mount — not nfs-retain
      accessModes: [ReadWriteOnce]
      resources:
        requests:
          storage: 50Gi
```

**Current MariaDB PVC uses `nfs-retain` (soft mount) — migration to `nfs-database` is a pending action.**

---

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:** Pod restart required, `fsync` has slightly higher overhead than O_DIRECT

---

## 7. Impact After Fix

```bash
# Table creation succeeds
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
# Query OK, 0 rows affected

# Verify flush method
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | fsync |
```

---

## 8. Notes

### Lessons Learned

1. **InnoDB O_DIRECT is incompatible with NFS** — Always use `fsync` for NFS storage
2. **Use TCP probes for databases** — Avoids authentication issues
3. **Constant pod restarts can corrupt InnoDB** — Fix probe issues quickly
4. **Soft mount made this bug visible** — I/O errors surfaced immediately rather than hanging. But soft mount is wrong for databases long-term — see TS-K8S-015

### NFS + Database Checklist

| Setting | Correct Value | Why |
|---|---|---|
| `innodb_flush_method` | `fsync` | O_DIRECT not supported on NFS |
| StorageClass | `nfs-database` | hard mount for write integrity |
| Liveness probe | `tcpSocket` | no auth dependency |
| Readiness probe | `tcpSocket` | no auth dependency |

### Commands Reference

```bash
# Test table creation
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"

# Check flush method
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"

# Verify NFS mount
kubectl exec mariadb-0 -n database -c mariadb -- cat /proc/mounts | grep mysql
```

---

## 9. Workaround

```yaml
# In pod spec
command: ["mysqld", "--innodb-flush-method=fsync"]
```

Make this permanent in the StatefulSet manifest, not just a workaround.