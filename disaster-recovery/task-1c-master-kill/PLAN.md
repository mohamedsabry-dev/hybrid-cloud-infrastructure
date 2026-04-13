# Task 1c: Master Node & Quorum Failures

**Trigger:** Take down master nodes, test etcd quorum loss and recovery.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 1.9 — Single Master Node Down

> **ALREADY VALIDATED** — Tested in Task 0 (Scenario 0.2).
> See: [Task 0 Results](../task-0-backup-restore/RESULTS.md#scenario-02--etcd-single-node-failure--recovery)

Restart or force shutdown 1 master.

- Action: Graceful restart 1 master
- Check: `kubectl` commands still work (other masters serving)
- Check: etcd quorum maintained (2 of 3)
- Action: Repeat with force shutdown
- Check: etcd leader election occurs

→ Skip (validated in Task 0).

### Scenario 1.10 — Partial Master Loss (2 of 3)
Force shutdown 2 of 3 masters.

- Action: Force shutdown 2 master nodes
- Check: etcd quorum LOST (only 1 of 3)
- Check: API server behavior — read-only or unavailable?
- Check: Existing pods still running (kubelet independent)
- Recovery: Start 1 master → quorum restored

→ Run checklist.

### Scenario 1.11 — Single Vault Node Down

> **ALREADY VALIDATED** — No need to test. Faced as real incident on April 11, 2026.
> See: [TS-VLT-005](../../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md), [TS-K8S-024](../../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

Restart or force shutdown 1 vault LXC.

- Action: Graceful restart 1 vault LXC
- Check: Raft leader election (if leader killed)
- Check: Vault remains unsealed
- Action: Repeat with force kill
- Check: Same behavior

→ Skip (validated in real incident).

### Scenario 1.12 — Vault Quorum Loss (2 of 3)

> **COVERED IN TASK 4** — See Task 4 Scenario 4.2 to avoid duplication.

→ Skip (covered in Task 4).

### Scenario 1.13 — Vault Seal/Unseal Cycle

> **COVERED IN TASK 4** — See Task 4 Scenario 4.3 to avoid duplication.

→ Skip (covered in Task 4).

### Scenario 1.14 — Combined: 2 Workers + 2 Masters (Quorum Loss)
Severe combined failure — tests quorum loss and recovery.

- Action: Force shutdown 2 workers + 2 masters
- Check: etcd quorum LOST (1/3 masters)
- Check: 1 worker still running pods (kubelet works independently)
- Check: No new scheduling possible (API server read-only or unavailable)
- Recovery: Start 1 master → quorum restored → scheduling resumes

→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] WordPress accessible (browse + upload)
- [ ] etcd health and leader election
- [ ] Vault sealed/unsealed status
- [ ] API server availability
- [ ] Existing pods still running (kubelet independent)
- [ ] **Grafana:** etcd metrics, API server latency, control plane health
- [ ] **Prometheus:** scraping targets (may be unavailable during quorum loss)
- [ ] **Loki:** control plane logs, kubelet logs for disconnection events
