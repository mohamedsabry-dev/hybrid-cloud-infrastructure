# Task 4: Kill Vault

**Trigger:** Degrade or destroy Vault cluster and its dependencies.
**Baseline:** WordPress browsing + video upload running throughout all scenarios.
**Test Date:** 2026-04-13
**Status:** ✅ COMPLETE

> **Full test evidence and logs:** See [RESULTS.md](./RESULTS.md)

---

### Scenario 4.1 — Single Vault Node Down ✅ SKIPPED

> **ALREADY VALIDATED** — Faced as real incident on April 11, 2026.
> See: [TS-VLT-005](../../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md), [TS-K8S-024](../../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

---

### Scenario 4.2 — Vault Quorum Loss + Injector Behavior ✅ PASS

Combined test: Kill 2/3 vault nodes, lose raft quorum, and test vault-injector behavior.

**Step A — Quorum Loss Impact**
- [x] Stop 2 vault LXCs (`pct stop 2004 && pct stop 2005`)
- [x] Vault cluster unavailable — vault3 stuck in standby, can't elect leader (1/3 = no quorum)
- [x] Existing pods still serving with cached secrets — **YES**
- [x] New pods can fetch secrets? — **NO** (stuck on vault-agent-init)
- [x] Vault UI inaccessible — **YES** (leader down)

**Step B — Vault-Injector Deep Dive (while vault down)**
- [x] Scaled WordPress to 4 replicas to test new pod behavior
- [x] vault-injector sidecar injected — **YES** (mutating webhook worked)
- [x] Init container behavior — **Infinite retry with exponential backoff** (770ms → 1.47s → 2.8s → 4.76s → ...)
- [x] New pods stuck at `Init:1/2` — cannot authenticate to vault

**Key Finding:** vault-agent connects to VIP → vault3 redirects to dead leader IP → fails. This is Raft HA redirect behavior.

**Step C — Recovery**
- [x] Started vault1 only (testing 2/3 quorum) — `pct start 2004`
- [x] Quorum restored — vault3 promoted to leader!
- [x] New pod got secrets in **12 seconds**
- [x] Started vault2 — cluster fully healthy (Failure Tolerance: 1)

**Critical Insight:** 2/3 nodes = quorum restored. Single node (1/3) cannot self-heal.

---

### Scenario 4.3 — AWS KMS Auto-Unseal Dependency ✅ PASS

**Test Execution:**
- [x] Broke AWS credentials (`/etc/vault.d/vault.env` → empty file)
- [x] Restarted vault1 — **service failed** (not just sealed!)
- [x] Error: `NoCredentialProviders: no valid providers in chain`
- [x] Cluster impact: 2/3 quorum maintained (vault2+vault3)
- [x] New pods CAN get secrets — **YES** (11 seconds) — unlike 4.2!

**Recovery:**
- [x] Restored vault.env from backup
- [x] Restarted vault service
- [x] Auto-unseal worked — `core: unsealed with stored key`
- [x] vault1 rejoined as follower, cluster healthy

**Key Finding:** Without AWS KMS credentials, vault won't start at all (systemd 3x retry then gives up).

---

### Observation Checklist (Final Results):

| Check | 4.2 (Quorum Loss) | 4.3 (AWS KMS) |
|-------|-------------------|---------------|
| Existing pods serving (cached secrets) | ✅ YES | ✅ YES |
| New pods can inject secrets | ❌ NO (stuck) | ✅ YES (2/3 quorum) |
| Vault UI accessible | ❌ NO | ✅ YES (vault2/3) |
| Vault sealed/unsealed | N/A (no quorum) | Unsealed (2/3) |
| vault-injector healthy | ✅ YES | ✅ YES |
| App functionality | ✅ OK (cached) | ✅ OK |

### Critical Learnings

1. **Quorum requirements:** 2/3 = operational, 1/3 = stuck (no leader election)
2. **Cached secrets save running pods** — no immediate impact on existing workloads
3. **AWS KMS is hard dependency** — no credentials = vault won't even start
4. **Flux GitOps self-heals** — manual scaling reverted automatically (5m reconcile)

### Related Cases
- [TS-VLT-005](../../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md)
- [TS-K8S-024](../../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)
