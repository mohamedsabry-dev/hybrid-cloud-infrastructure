# Task 4: Kill Vault

**Trigger:** Degrade or destroy Vault cluster and its dependencies.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 4.1 — Single Vault Node Down

> **ALREADY VALIDATED** — No need to test. Faced as real incident on April 11, 2026.
> See: [TS-VLT-005](../../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md), [TS-K8S-024](../../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

Restart or force kill 1 vault LXC.

- Action: Graceful restart 1 vault LXC (e.g., vault1 / 2004)
- Check: Raft leader election (if leader was killed)
- Check: Vault remains unsealed
- Check: App pods still serving with cached secrets
- Action: Repeat with force stop (`pct stop <CTID>`)
- Check: Same behavior, different timing?

→ Skip (validated in real incident).

### Scenario 4.2 — Vault Quorum Loss (2 of 3 Down)
Kill 2 vault LXCs, lose raft quorum.

- Action: Stop 2 vault LXCs (`pct stop 2004 && pct stop 2005`)
- Check: Vault cluster unavailable (no quorum)
- Check: Existing pods still serving with cached secrets?
- Check: New pods can fetch secrets? (expected: no)
- Check: vault-injector behavior
- Recovery: Start vault LXCs → quorum restored
- Check: New pods can now fetch secrets

→ Run checklist.

### Scenario 4.3 — AWS KMS Auto-Unseal Dependency
Test recovery when KMS credentials are broken.

- Action: Break AWS KMS credentials (rotate key or change secrets)
- Action: Restart vault LXC (`pct restart 2004`)
- Check: Vault stays sealed on startup (auto-unseal fails)
- Check: App impact — existing pods with cached secrets?
- Recovery:
  1. Restore correct AWS KMS credentials
  2. Restart vault service (`systemctl restart vault`)
- Check: Auto-unseal succeeds on restart
- Check: Vault cluster healthy
- Check: App recovers

→ Run checklist.

### Scenario 4.4 — Vault-Injector Behavior During Degraded Vault
Test sidecar injection when vault is degraded.

- Action: Stop 1 or 2 vault LXCs (degraded state)
- Action: Deploy a new pod that requires secret injection
- Check: vault-injector sidecar behavior
- Check: Can new pods get secrets injected?
- Check: What if vault-injector pod itself reschedules?
- Check: Init container timeout behavior

→ Run checklist.

---

### Observation Checklist (run after every scenario):
- [ ] Existing pods still serving with cached secrets
- [ ] New pods can / cannot inject secrets
- [ ] Vault UI accessible
- [ ] Vault sealed / unsealed status
- [ ] vault-injector pod healthy and scheduling correctly
- [ ] App functionality (WordPress login, DB connections via Vault creds)
