DR Test: Vault Single Node Down
Date: 2026-04-11 (real incident, not planned test)
Result: PASS — validated in production
_____________________________________________________________________

[Info]
Domain: Vault / Raft HA
Environment: DEV — 3-node Vault cluster
Triggered by: Real incident — single vault node went down unexpectedly

_____________________________________________________________________

[Scope]

Not a planned DR test. This scenario was validated by a real incident
on 2026-04-11 before the DR test phase started. Documenting here for
completeness since it covers the "single vault node failure" case.

_____________________________________________________________________

[What happened]

- Single vault node went down unexpectedly
- Cluster maintained 2/3 quorum — kept serving
- Applications continued with cached secrets
- New pods could still fetch secrets (quorum intact)
- Recovery required manual cleanup of stale raft data on the failed node

_____________________________________________________________________

[Test 1.2 — New pod creation with 1 node down]

Date: 2026-04-13 (deliberate test, 2 days after the real incident)

Why this test: the incident proved the cluster survives, but I didn't
  check whether new pods can actually get secrets during degraded state.

Action:
  ```
  kubectl scale deployment wordpress -n apps --replicas=4
  ```

What happened:
  - New pod created, vault-agent-init authenticated against healthy nodes
  - Pod reached 2/2 Running in 11 seconds
  - WordPress serving normally

What this tells me:
  Pods don't care which Vault node they hit — they talk to the Vault
  service (VIP or any healthy node). As long as quorum exists, secret
  injection works. This is a key difference from the quorum loss test
  where 2/3 nodes died and new pods got stuck.

_____________________________________________________________________

[Findings]

1. 2/3 quorum = fully operational. First proven by the real incident
   (2026-04-11), then deliberately tested (2026-04-13). Both existing
   and new pods work fine with 1 node down.

2. Stale raft data is the real recovery problem. During the real
   incident, the node didn't rejoin cleanly — it had stale data that
   needed manual cleanup before it could re-sync with the cluster.

3. New pods get secrets in ~11s during degraded state. vault-agent-init
   authenticates against any healthy node. Quorum is what matters, not
   which specific node is up.

_____________________________________________________________________

[References]

- troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md (TS-VLT-005)
- troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md (TS-K8S-024)
- vault-raft-quorum-loss.md — planned test covering 2/3 quorum loss
- vault-aws-kms-credential-loss.md — credential loss scenario (different cause, same quorum behavior)
