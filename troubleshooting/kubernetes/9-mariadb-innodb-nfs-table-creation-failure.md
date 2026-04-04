# MariaDB InnoDB Table Creation Failure on NFS Storage

## Problem Summary
MariaDB StatefulSet on Kubernetes with NFS storage fails to create tables with error:
```
ERROR 1005 (HY000): Can't create table `wordpress`.`wp_users` (errno: 168 "Unknown (generic) error from engine")
```

## Environment
- **Cluster**: Kubernetes with Flux GitOps
- **Storage**: NFS (Synology NAS) via nfs-csi driver
- **Database**: MariaDB 10.11.11 StatefulSet
- **Namespace**: database

## Symptoms

### WordPress Installation Fails
```
WordPress database error: [Can't create table `wordpress`.`wp_users` (errno: 168 "Unknown (generic) error from engine")]
CREATE TABLE wp_users ( ID bigint(20) unsigned NOT NULL auto_increment, ... )
```

### Manual Table Creation Also Fails
```bash
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"
# ERROR 1005 (HY000): Can't create table `wordpress`.`test` (errno: 168 "Unknown (generic) error from engine")
```

### InnoDB Logs Show Storage Errors
```
InnoDB: Retry attempts for reading partial data failed.
```

## Root Cause Analysis

### Initial Investigation
1. Vault secrets injection working correctly:
```bash
kubectl exec mariadb-0 -n database -c mariadb -- cat /vault/secrets/db-creds
# MYSQL_ROOT_PASSWORD=Change_Me
# MYSQL_PASSWORD=Admin@123
```

2. Database and user created successfully:
```bash
kubectl logs mariadb-0 -n database -c mariadb
# [Note] [Entrypoint]: Creating database wordpress
# [Note] [Entrypoint]: Creating user wordpress
```

3. NFS mount working:
```bash
kubectl exec mariadb-0 -n database -c mariadb -- df -h /var/lib/mysql
# 10.0.40.120:/volume1/k8s-prod/pvc-... 1.8T 221G 1.6T 13%
```

4. Permissions correct:
```bash
kubectl exec mariadb-0 -n database -c mariadb -- ls -la /var/lib/mysql/
# drwxrwsr-x. 6 mysql mysql 4096 ...
```

### Root Cause Identified
InnoDB `innodb_flush_method` was set to `O_DIRECT`:
```bash
kubectl exec mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# | innodb_flush_method | O_DIRECT |
```

**O_DIRECT bypasses the OS page cache and attempts direct I/O to disk. NFS does not properly support O_DIRECT operations**, causing table creation to fail with generic error 168.

### Why Dev Worked But Prod Failed (Not Fully Determined)
- Both environments had identical NFS mount options
- Both used same NAS (10.0.40.120) with different shares (k8s-dev vs k8s-prod)
- Dev cluster initialized MariaDB before this issue was discovered
- Possible causes:
  - Different timing during initialization
  - NFS export settings on NAS might differ between shares
  - Dev pod initialized before probes were added (less restart pressure)
- **Root cause of discrepancy not confirmed**

## Solution

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

## Additional Fixes Applied

### TCP Socket Probes Instead of mysqladmin
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

## Verification Commands

### Test Table Creation
```bash
# Should succeed now
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; CREATE TABLE test (id INT);"

# Verify flush method
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "SHOW VARIABLES LIKE 'innodb_flush_method';"
# Should show: fsync

# Clean up test table
kubectl exec -it mariadb-0 -n database -c mariadb -- mysql -u root -p -e "USE wordpress; DROP TABLE test;"
```

### Verify NFS Mount
```bash
kubectl exec mariadb-0 -n database -c mariadb -- cat /proc/mounts | grep mysql
```

## Files Modified
- `kubernetes/dev/deployments/apps/mariadb/statefulset.yaml`
- `kubernetes/prod/deployments/apps/mariadb/statefulset.yaml`

## Key Takeaways
1. **InnoDB O_DIRECT is incompatible with NFS** - Always use `fsync` for NFS storage
2. **Use TCP probes for databases** - Avoids authentication issues with liveness/readiness checks
3. **Constant pod restarts can corrupt InnoDB** - Fix probe issues quickly to prevent data corruption
4. **Same config can behave differently** - Timing, initialization order, and subtle environment differences matter

## References
- MariaDB InnoDB flush methods: https://mariadb.com/kb/en/innodb-system-variables/#innodb_flush_method
- NFS and database compatibility: O_DIRECT not supported on most NFS implementations
- Kubernetes probes: TCP socket probes are simpler and don't require auth
