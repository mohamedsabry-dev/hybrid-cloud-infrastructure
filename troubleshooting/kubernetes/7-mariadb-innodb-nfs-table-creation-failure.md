# TS-K8S-007 | 2026-04-02 | RESOLVED

## 1. Context

- **System:** MariaDB StatefulSet / InnoDB / NFS Storage
- **Environment:** k8s-prod cluster (also applied fix to dev)
- **Related Components:** NFS CSI driver, InnoDB storage engine, Vault secrets injection
- **Discovered During:** WordPress installation attempting to create database tables
- **Related:** Case 3 (NFS Mount Options), Case 6 (NFS Complete Guide)

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

**Finding:** Vault secrets injection working correctly.

### Step 2: Check Database/User Creation

```bash
kubectl logs mariadb-0 -n database -c mariadb
# [Note] [Entrypoint]: Creating database wordpress
# [Note] [Entrypoint]: Creating user wordpress
```

**Finding:** Database and user created successfully.

### Step 3: Verify NFS Mount

```bash
kubectl exec mariadb-0 -n database -c mariadb -- df -h /var/lib/mysql
# 10.0.40.120:/volume1/k8s-prod/pvc-... 1.8T 221G 1.6T 13%
```

**Finding:** NFS mount working.

### Step 4: Check Permissions

```bash
kubectl exec mariadb-0 -n database -c mariadb -- ls -la /var/lib/mysql/
# drwxrwsr-x. 6 mysql mysql 4096 ...
```

**Finding:** Permissions correct.

### Step 5: Check InnoDB Flush Method (ROOT CAUSE)

```bash
kubectl exec mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | O_DIRECT |
```

**Finding:** InnoDB using O_DIRECT which is incompatible with NFS.

---

## 4. Root Cause

**InnoDB `innodb_flush_method` was set to `O_DIRECT`.**

O_DIRECT bypasses the OS page cache and attempts direct I/O to disk. **NFS does not properly support O_DIRECT operations**, causing table creation to fail with generic error 168.

### Why Dev Worked But Prod Failed (Not Fully Determined)

- Both environments had identical NFS mount options
- Both used same NAS (10.0.40.120) with different shares (k8s-dev vs k8s-prod)
- Dev cluster initialized MariaDB before this issue was discovered
- Possible causes:
  - Different timing during initialization
  - NFS export settings on NAS might differ between shares
  - Dev pod initialized before probes were added (less restart pressure)
- **Root cause of discrepancy not confirmed**

---

## 5. Solution

### Fix: Set innodb_flush_method=fsync

Add `--innodb-flush-method=fsync` to MariaDB startup command:

```yaml
command:
  - /bin/bash
  - -c
  - |
    # Source Vault secrets
    if [ -f /vault/secrets/db-creds ]; then
      export $(cat /vault/secrets/db-creds | xargs)
    fi
    exec docker-entrypoint.sh mysqld --innodb-flush-method=fsync
```

### Why fsync Works

- `fsync` uses standard POSIX file sync operations
- Compatible with NFS and network filesystems
- Slightly higher overhead than O_DIRECT but reliable

### Additional Fix: TCP Socket Probes

Original probes used `mysqladmin ping` which requires authentication:

```yaml
# PROBLEM: Fails when root has password
livenessProbe:
  exec:
    command: [mysqladmin, ping, -h, localhost]
```

Fixed to use TCP socket check (no auth needed):

```yaml
# SOLUTION: TCP check doesn't need password
livenessProbe:
  tcpSocket:
    port: 3306
  initialDelaySeconds: 30
  periodSeconds: 10
```

### Files Changed

- `kubernetes/dev/deployments/apps/mariadb/statefulset.yaml`
- `kubernetes/prod/deployments/apps/mariadb/statefulset.yaml`

### Prevention Measures

1. Always use `innodb_flush_method=fsync` for NFS storage
2. Use TCP probes for databases to avoid authentication issues
3. Fix probe issues quickly to prevent constant restarts and potential data corruption

---

## 6. Solution Risk

- **Risk Level:** Low
- **Potential Impact:**
  - `fsync` has slightly higher overhead than `O_DIRECT` but is reliable on NFS
  - Pod restart required after configuration change
  - Existing data not affected

---

## 7. Impact After Fix

**Observed Results:**

```bash
# Table creation succeeds
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
# Query OK, 0 rows affected

# Verify flush method
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | fsync |

# WordPress installation completes successfully
```

---

## 8. Notes

### Lessons Learned

1. **InnoDB O_DIRECT is incompatible with NFS** - Always use `fsync` for NFS storage
2. **Use TCP probes for databases** - Avoids authentication issues with liveness/readiness checks
3. **Constant pod restarts can corrupt InnoDB** - Fix probe issues quickly to prevent data corruption
4. **Same config can behave differently** - Timing, initialization order, and subtle environment differences matter

### Commands Reference

#### Test Table Creation
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
```

#### Check Flush Method
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
```

#### Verify NFS Mount
```bash
kubectl exec mariadb-0 -n database -c mariadb -- cat /proc/mounts | grep mysql
```

### Related Files

- `kubernetes/dev/deployments/apps/mariadb/statefulset.yaml`
- `kubernetes/prod/deployments/apps/mariadb/statefulset.yaml`

### References

- [MariaDB InnoDB flush methods](https://mariadb.com/kb/en/innodb-system-variables/#innodb_flush_method)
- NFS and database compatibility: O_DIRECT not supported on most NFS implementations
- Kubernetes probes: TCP socket probes are simpler and don't require auth

---

## 9. Workaround

**Temporary:** Use `innodb_flush_method=fsync` command line argument:

```bash
# In pod spec
command: ["mysqld", "--innodb-flush-method=fsync"]
```

Or via environment variable (if MariaDB supports it in your version):

```yaml
env:
  - name: MARIADB_EXTRA_FLAGS
    value: "--innodb-flush-method=fsync"
```

**Note:** This should be made permanent in the StatefulSet manifest, not applied as a temporary workaround.
