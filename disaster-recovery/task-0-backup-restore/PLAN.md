# Task 0: Backup & Restore Validation

**Priority:** Execute FIRST — before Tasks 1 through 5. This is your safety net.

---

## Scenario 0.0 — Full Environment Backup (Pre-requisite)

Complete Proxmox backup of all VMs/LXCs before DR testing begins.

**VMs:**
- [x] 1001 (freeipa)
- [x] 1010 (k8s-master1)
- [x] 1011 (k8s-master2)
- [x] 1012 (k8s-master3)
- [x] 1020 (k8s-worker1)
- [x] 1021 (k8s-worker2)
- [x] 1022 (k8s-worker3)

**LXCs:**
- [x] 2001 (ansible)
- [x] 2002 (local-runner)
- [x] 2003 (ex-nginx)
- [x] 2004 (vault1)
- [x] 2005 (vault2)
- [x] 2006 (vault3)

- Action: Run `vzdump` (snapshot mode) for each VM/LXC
- Destination: NAS storage (nas-dev-data, nas-prod-data)
- Check: Verify all backups completed before proceeding

---

## Scenario 0.1 — ETCD Backup to S3

Backup etcd snapshot under normal operation, verify S3 upload.

- [x] Trigger manual backup job
  ```bash
  kubectl create job --from=cronjob/etcd-backup etcd-backup-dr-test -n etcd-backup
  ```
- [x] Verify local backup exists on master node
- [x] Verify S3 bucket contains uploaded snapshot
- [x] Confirm Vault agent injects AWS credentials

---

## Scenario 0.2 — ETCD Single Node Failure & Recovery

Test etcd cluster resilience and recovery procedures.

### Test A: Stop etcd (Quorum Test)
- [x] Stop etcd on one master (move manifest to /tmp)
- [x] Verify cluster survives with 2/3 quorum
- [x] Observe resource impact on surviving masters
- [x] Restore etcd (move manifest back)

### Test B: Delete etcd Data (Cluster Sync Recovery)
- [x] Delete /var/lib/etcd on broken node
- [x] Remove member from cluster
- [x] Re-add member with `etcdctl member add`
- [x] Verify `--initial-cluster-state=existing`
- [x] Restore manifest and verify sync from leader
- [x] Restart kubelet if node stays NotReady

### Test C: S3 Backup Validation
- [x] Download snapshot from S3
- [x] Validate with `etcdutl snapshot status`
- [x] Compare hash/revision with original backup

---

## Observation Checklist

- [x] Proxmox backups completed (dev + prod)
- [x] etcd backups uploaded to S3
- [x] etcd cluster survives single node failure
- [x] Node recovery via cluster sync works
- [x] S3 backup is valid and restorable
- [x] All pods running after recovery

---

## Additional Backup Systems (Not Tested — Already Validated)

| System | Status | Notes |
|--------|--------|-------|
| Proxmox config | Validated | Used in TS-PVE-007 (crontab recovery) |
| VM/Node restore | Validated | Used in TS-TF-010 (cloud-init SSH key) |
| Vault Raft | Deferred | NAS mount blocks LXC snapshots; using 3-node cluster + vzdump |
| Router (ER605) | Validated | Used in real scenario; backups in gitignore |
| Router (MikroTik) | Backed up | Backups in gitignore |
| NAS (Asustor) | Partial | RAID 1 only; USB backup planned |
