# Task 4: Kill Vault

**Trigger:** Degrade or destroy Vault cluster and its dependencies.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 4.1 — Single Vault Pod Restart
Restart 1 vault pod gracefully.
→ Run checklist.

### Scenario 4.2 — Single Vault Pod Force Kill
Force shutdown 1 vault pod.
→ Run checklist.

### Scenario 4.3 — Vault Quorum Loss (2 of 3 Down)
Kill 2 vault nodes. Quorum lost.
Check: existing pods with cached secrets still running? New pods can fetch secrets?
→ Run checklist.

### Scenario 4.4 — Full Vault Outage (3 of 3 Down)
Kill all 3 vault nodes.
Same checks as 4.3.
→ Run checklist.

### Scenario 4.5 — Manual Seal → Auto-Unseal
Manually seal vault → verify auto-unseal triggers correctly → verify app health.
→ Run checklist.

### Scenario 4.6 — Break Auto-Unseal
Remove or change the secrets used for auto-unseal.
Vault stays sealed → manual recovery procedure → verify app recovers.
→ Run checklist.

### Scenario 4.7 — Vault-Injector Behavior During Degraded Vault
Vault cluster degraded (1 or 2 nodes down).
Check: vault-injector sidecar behavior, can it still inject to new pods?
What if vault-injector itself is rescheduling?
→ Run checklist.

### Scenario 4.8 — Vault Raft Backup & Restore (Normal)
Backup Vault raft under normal operation → restore → verify all secrets intact.
→ Run checklist.

### Scenario 4.9 — Vault Raft Backup & Restore (Under Load)
Backup Vault raft during active workload → restore → verify integrity.
→ Run checklist.

### Scenario 4.10 — Vault Raft Restore with Partial Quorum
Restore raft backup with only 1 node available. Then 2 nodes. Then 3 nodes.
Document which quorum states allow successful restore.
→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] Existing pods still serving with cached secrets
- [ ] New pods can / cannot inject secrets
- [ ] Vault UI accessible
- [ ] Vault sealed / unsealed status
- [ ] vault-injector pod healthy and scheduling correctly
- [ ] App functionality (WordPress login, DB connections via Vault creds)
- [ ] Raft backup integrity after restore