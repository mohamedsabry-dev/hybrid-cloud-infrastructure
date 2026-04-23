# ETCD Backup to S3
# Date: 2026-04-11
# Result: PASS

---

## Scope

Backup etcd snapshot under normal operation, verify S3 upload.
Confirm Vault agent injects AWS credentials successfully.

---

## Steps

1. Trigger manual backup job
2. Verify local backup exists on master node
3. Verify S3 bucket contains uploaded snapshot
4. Confirm Vault agent injects AWS credentials

---

## Trigger Manual Backup

**Command:**
```bash
kubectl create job --from=cronjob/etcd-backup etcd-backup-dr-test -n etcd-backup
```

**Output:**
```
job.batch/etcd-backup-dr-test created
```

---

## Dev Cluster Backup

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

---

## Prod Cluster Backup

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

---

## Vault Agent Integration

Vault agent successfully injected AWS credentials:
```
2026-04-11T14:10:26.897Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2026-04-11T14:10:26.898Z [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
2026-04-11T14:10:26.898Z [INFO]  agent: sinks finished, exiting
```

---

## Summary

| Cluster | Snapshot | Size | Keys | Revision | S3 Bucket |
|---------|----------|------|------|----------|-----------|
| Dev | etcd-20260411-141101.snap | 39 MB | 2863 | 2883121 | hybrid-cloud-k8s-etcd-backup-dev |
| Prod | etcd-20260411-141028.snap | 37 MB | 2471 | 1559350 | hybrid-cloud-k8s-etcd-backup-prod |

---

## Notes

- Vault Agent version mismatch warning (1.21.2 vs 1.21.4) - informational only, does not affect functionality
- AWS credentials successfully injected via Vault
- Both local and S3 backups verified
- Backup retention working (keeping multiple snapshots)

---

## Result: PASS

- Manual backup triggered successfully
- Local snapshot created and verified
- S3 upload completed
- Vault agent injection working
