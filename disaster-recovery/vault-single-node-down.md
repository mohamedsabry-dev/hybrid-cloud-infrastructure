# Vault Single Node Down
# Date: 2026-04-11 (real incident)
# Result: PASS (validated in production)

---

## Scope

Test vault cluster behavior when single node goes down.
Validate 2/3 quorum maintains cluster operation.

---

## Status: Validated in Real Incident

This scenario was **not tested during DR phase** because it was already validated as a real incident on April 11, 2026.

---

## Real Incident Summary

- Single vault node went down unexpectedly
- Cluster maintained 2/3 quorum
- Applications continued serving with cached secrets
- New pods could still fetch secrets
- Recovery required manual intervention for stale raft data

---

## Documented In

- [TS-VLT-005](../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md) — Vault node recovery with stale raft data
- [TS-K8S-024](../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md) — Vault cluster resilience with 2-node quorum

---

## Key Findings (from real incident)

1. **2/3 quorum = operational** — cluster continues serving
2. **Stale raft data requires cleanup** — node may not rejoin automatically
3. **Recovery procedure documented** — see TS-VLT-005 for steps

---

## Result: PASS

Validated through real production incident. See TS cases for full details.
