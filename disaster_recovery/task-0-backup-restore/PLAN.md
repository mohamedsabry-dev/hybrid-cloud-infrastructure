# Task 0: Backup & Restore Validation

**Priority:** Execute FIRST — before Tasks 1 through 5. This is your safety net.

---

### Scenario 0.1 — ETCD Backup & Restore (Normal)
Backup etcd snapshot under normal operation → restore → verify cluster state.
→ Run checklist.

### Scenario 0.2 — ETCD Backup & Restore (Under Load)
Backup etcd during active workload (uploads, deployments running) → restore → verify data integrity.
→ Run checklist.

### Scenario 0.3 — ETCD Snapshot Corruption
Simulate corrupted etcd snapshot → attempt restore → document failure behavior and recovery path.
→ Run checklist.

### Scenario 0.4 — Vault Raft Backup & Restore (Normal)
Backup Vault raft → restore → verify all secrets accessible.
→ Run checklist.

### Scenario 0.5 — Vault Raft Backup Integrity
Verify backup integrity before restore (checksum, validation).
Restore with different quorum states (1, 2, 3 nodes).
→ Run checklist.

### Scenario 0.6 — WordPress Data Backup & Restore
Backup WordPress uploads + MariaDB during active operations.
Restore → verify: uploads intact, DB consistent, no missing/duplicate records.
→ Run checklist.

### Scenario 0.7 — MariaDB Point-in-Time Recovery
Test point-in-time recovery for MariaDB.
Verify: can you restore to a specific moment before a failure?
→ Run checklist.

### Scenario 0.8 — Local Backup Without NFS
Backup to local storage (no NFS dependency).
Then: simulate NFS down → restore from local backup → verify.
Confirms you can recover even when NFS is unavailable.
→ Run checklist.

### Scenario 0.9 — Backup Copy Strategy
Backup to local → scheduled copy to NFS.
Verify: only latest backup kept on local, older copies on NFS.
Test: NFS goes down → local backup still usable.
→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] Backup completed successfully (under load if applicable)
- [ ] Restore produced consistent state
- [ ] DB integrity (no missing / duplicate records)
- [ ] WordPress uploads intact
- [ ] Vault secrets accessible after raft restore
- [ ] etcd cluster healthy after restore
- [ ] Local backup usable without NFS
- [ ] Backup copy to NFS succeeded