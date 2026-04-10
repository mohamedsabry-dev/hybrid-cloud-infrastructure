# Task 0: Backup & Restore Validation

**Priority:** Execute FIRST — before Tasks 1 through 5. This is your safety net.

---

### Scenario 0.0 — Full Environment Backup (Pre-requisite)
Complete Proxmox backup of all VMs/LXCs before DR testing begins.

**VMs:**
- [ ] 1001 (freeipa)
- [ ] 1010 (k8s-master1)
- [ ] 1011 (k8s-master2)
- [ ] 1012 (k8s-master3)
- [ ] 1020 (k8s-worker1)
- [ ] 1021 (k8s-worker2)
- [ ] 1022 (k8s-worker3)

**LXCs:**
- [ ] 2001 (ansible)
- [ ] 2002 (local-runner)
- [ ] 2003 (ex-nginx)
- [ ] 2004 (vault1)
- [ ] 2005 (vault2)
- [ ] 2006 (vault3)

- Action: Run `vzdump` (snapshot mode) for each VM/LXC
- Destination: NAS storage
- Retention: Keep until all DR scenarios complete successfully
- Check: Verify all backups completed before proceeding to 0.1

→ Run checklist.

---

### Scenario 0.1 — ETCD Backup & Restore
Backup etcd snapshot under normal operation, then restore.

- Action: Trigger manual backup job
  ```
  kubectl create job --from=cronjob/etcd-backup etcd-backup-test -n etcd-backup
  ```
- Check: Local backup exists on master node (`/var/lib/etcd-backup/`)
- Check: S3 bucket contains uploaded snapshot
- Action: Restore from local snapshot
- Check: Cluster state matches pre-backup state
- Check: All pods running and serving traffic

→ Run checklist.

### Scenario 0.2 — ETCD Restore from S3
Download snapshot from S3 and restore (simulates local backups lost).

- Action: Delete local backups on all masters
- Action: Download latest snapshot from S3 bucket
- Action: Restore etcd from downloaded snapshot
- Check: etcd cluster healthy (all 3 members)
- Check: Kubernetes API responding
- Check: All workloads recovered

→ Run checklist.

### Scenario 0.3 — WordPress Data Backup & Restore
Backup and restore WordPress uploads (NFS PVC) + MariaDB.

- Action: Backup WordPress uploads directory (NFS)
- Action: Backup MariaDB database (`mysqldump` or snapshot)
- Action: Simulate data loss (delete some uploads, drop table)
- Action: Restore uploads from backup
- Action: Restore MariaDB from backup
- Check: Uploads intact and accessible
- Check: DB consistent — no missing/duplicate records
- Check: WordPress functioning normally

→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] Backup completed successfully
- [ ] Restore produced consistent state
- [ ] DB integrity (no missing / duplicate records)
- [ ] WordPress uploads intact
- [ ] etcd cluster healthy after restore
- [ ] Pods running and serving traffic
