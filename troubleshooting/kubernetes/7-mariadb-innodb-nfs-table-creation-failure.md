# TS-K8S-007 | 2026-04-02 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Kubernetes / MariaDB / NFS Storage
Sub-techs: InnoDB storage engine, innodb_flush_method, O_DIRECT vs fsync,
           NFS CSI driver, Vault secrets injection, TCP socket probes
Environment: PROD k8s cluster (also applied fix to dev) | NFS server 10.0.40.120
Discovered during: WordPress installation attempting to create database tables
Related: TS-K8S-003 (NFS hard mount — introduced soft mount that surfaced this),
         TS-K8S-006 (NFS complete guide),
         TS-K8S-015 (stale NFS mount on CSI restart — soft mount caused MariaDB crash)
Re-opened: No

_____________________________________________________________________

[Issue Description]
MariaDB couldn't create any tables on NFS storage. WordPress installation failed
during table creation, and manual table creation failed too.

WordPress installation error:
```
WordPress database error: [Can't create table `wordpress`.`wp_users` (errno: 168 "Unknown (generic) error from engine")]
CREATE TABLE wp_users ( ID bigint(20) unsigned NOT NULL auto_increment, ... )
```

Manual table creation also failed:
```
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
# ERROR 1005 (HY000): Can't create table `wordpress`.`test` (errno: 168 "Unknown (generic) error from engine")
```

InnoDB logs showed storage errors:
```
InnoDB: Retry attempts for reading partial data failed.
```

_____________________________________________________________________

[Analysis]

# Step 1: Verify Vault secrets injection

```
kubectl exec mariadb-0 -n database -c mariadb -- cat /vault/secrets/db-creds
# MYSQL_ROOT_PASSWORD=<redacted>
# MYSQL_PASSWORD=<redacted>
```

Vault secrets injection working correctly. Not the problem.

# Step 2: Check database/user creation

```
kubectl logs mariadb-0 -n database -c mariadb
# [Note] [Entrypoint]: Creating database wordpress
# [Note] [Entrypoint]: Creating user wordpress
```

Database and user created successfully. Not the problem.

# Step 3: Verify NFS mount

```
kubectl exec mariadb-0 -n database -c mariadb -- df -h /var/lib/mysql
# 10.0.40.120:/volume1/k8s-prod/pvc-... 1.8T 221G 1.6T 13%
```

NFS mount working fine.

# Step 4: Check permissions

```
kubectl exec mariadb-0 -n database -c mariadb -- ls -la /var/lib/mysql/
# drwxrwsr-x. 6 mysql mysql 4096 ...
```

Permissions correct.

# Step 5: Check InnoDB flush method — found the root cause

```
kubectl exec mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | O_DIRECT |
```

InnoDB was using `O_DIRECT`, which bypasses the OS page cache and attempts direct
I/O to disk. NFS doesn't properly support O_DIRECT operations, causing table
creation to fail with generic error 168.

_____________________________________________________________________

[Final Root Cause]
InnoDB `innodb_flush_method` was set to `O_DIRECT`. O_DIRECT bypasses the OS page
cache and attempts direct I/O to disk. NFS doesn't properly support O_DIRECT
operations, so every table creation failed with error 168.

The soft mount connection: at this point in the NFS journey, MariaDB was using
`soft` mount options from TS-K8S-003. The soft mount means NFS I/O errors return
immediately instead of hanging — which made this bug visible fast (crash instead of
silent hang). With hard mount + O_DIRECT, MariaDB would have hung silently. The
soft mount from TS-K8S-003 made this issue surface, but soft mount is still wrong
for databases long-term. See TS-K8S-015 for the full consequence.

_____________________________________________________________________

[Final Solution]

# Fix 1: Set innodb_flush_method=fsync

Added `--innodb-flush-method=fsync` to MariaDB startup command:

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

`fsync` uses standard POSIX file sync operations — compatible with NFS and all
network filesystems. Slightly higher overhead than O_DIRECT but reliable.

# Fix 2: TCP socket probes

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

# Fix 3: Use nfs-database StorageClass (added in TS-K8S-015)

After this case was resolved, TS-K8S-015 revealed that soft mount also causes
MariaDB to crash when the CSI node pod restarts. The permanent fix is to use the
`nfs-database` StorageClass with hard mount for all database workloads:

```yaml
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

Current MariaDB PVC uses `nfs-retain` (soft mount) — migration to `nfs-database`
is a pending action.

# Verification

```
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
# Query OK, 0 rows affected

kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | fsync |
```

Verified: Yes — table creation works, flush method confirmed as fsync.

_____________________________________________________________________

[Risk Level] LOW

Pod restart required to apply. `fsync` has slightly higher overhead than O_DIRECT
but is the only correct option for NFS storage.

_____________________________________________________________________

[References]
- TS-K8S-003 — NFS hard mount (introduced soft mount that surfaced this issue)
- TS-K8S-006 — NFS complete guide (architecture reference)
- TS-K8S-015 — stale NFS mount on CSI restart (soft mount caused MariaDB crash)
