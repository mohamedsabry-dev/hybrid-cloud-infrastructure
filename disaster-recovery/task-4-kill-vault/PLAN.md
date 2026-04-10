# Task 4: Kill Vault

**Trigger:** Degrade or destroy Vault cluster and its dependencies.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

### Scenario 4.1 — Single Vault Node Down
Restart or force kill 1 vault pod.

- Action: Graceful restart 1 vault pod
- Check: Raft leader election (if leader was killed)
- Check: Vault remains unsealed
- Check: App pods still serving with cached secrets
- Action: Repeat with force kill (`kubectl delete pod --force`)
- Check: Same behavior, different timing?

→ Run checklist.

### Scenario 4.2 — Vault Quorum Loss (2 of 3 Down)
Kill 2 vault nodes, lose raft quorum.

- Action: Kill 2 vault pods
- Check: Vault cluster unavailable (no quorum)
- Check: Existing pods still serving with cached secrets?
- Check: New pods can fetch secrets? (expected: no)
- Check: vault-injector behavior
- Recovery: Start vault pods → quorum restored
- Check: New pods can now fetch secrets

→ Run checklist.

### Scenario 4.3 — Manual Seal → Auto-Unseal
Test AWS KMS auto-unseal.

- Action: Manually seal vault (`vault operator seal`)
- Check: Vault shows sealed status
- Check: AWS KMS auto-unseal triggers automatically
- Check: Vault becomes unsealed
- Check: App health during seal/unseal window
- Check: No secret fetch failures for existing pods

→ Run checklist.

### Scenario 4.4 — Break Auto-Unseal
Test recovery when auto-unseal fails.

- Action: Remove or change AWS KMS secrets used for auto-unseal
- Action: Seal vault (or restart vault pods)
- Check: Vault stays sealed (auto-unseal broken)
- Action: Manual recovery procedure:
  1. Restore correct AWS KMS secrets
  2. Restart vault pods (or manually unseal)
- Check: Vault unsealed
- Check: App recovers

→ Run checklist.

### Scenario 4.5 — Vault-Injector Behavior During Degraded Vault
Test sidecar injection when vault is degraded.

- Action: Kill 1 or 2 vault nodes (degraded state)
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
