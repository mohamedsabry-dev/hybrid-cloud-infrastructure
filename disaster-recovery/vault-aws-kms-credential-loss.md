DR Test: Vault AWS KMS Auto-Unseal Dependency
Date: 2026-04-13
Result: PASS
_____________________________________________________________________

[Info]
Domain: Vault / AWS KMS / Raft HA
Environment: DEV — 3-node Vault cluster (vault1/2/3), seal type awskms
Triggered by: Need to understand what happens if AWS credentials are
  lost on a Vault node — does it seal, crash, or just not start?

_____________________________________________________________________

[Planned Scope]

Break AWS KMS credentials on 1 of 3 Vault nodes and observe:
does it start sealed, or fail entirely? How does the cluster react?

Credential flow:
  AWS Secrets Manager → GitHub Actions → Ansible → /etc/vault.d/vault.env → systemd

_____________________________________________________________________

[Pre-State]

All 3 Vault nodes unsealed, HA active, seal type awskms.
```
vault status → Sealed: false, Seal Type: awskms
```

_____________________________________________________________________

[Test 1.1 — Break AWS credentials on vault1]

Action:
  ```
  cp /etc/vault.d/vault.env /etc/vault.d/vault.env.backup
  echo "# BROKEN FOR DR TEST" > /etc/vault.d/vault.env
  systemctl restart vault
  ```

What happened:
  - vault1: service FAILED to start — not sealed, completely dead
    ```
    error parsing Seal configuration: NoCredentialProviders: no valid providers in chain
    ```
  - Systemd retried 3x then gave up
  - vault1 unreachable: connection refused on port 8200

  Cluster from vault3:
  ```
  vault operator raft autopilot state
  Healthy: false              ← degraded
  Failure Tolerance: 0        ← can't lose another node
  vault1: Healthy: false
  vault2: Healthy: true
  vault3: leader, Healthy: true
  ```

  Key difference from quorum loss test: this is 1 node down, 2/3
  quorum intact. Cluster still serves requests.

What this tells me:
  Without AWS credentials, Vault doesn't start at all — it's not
  "sealed waiting for unseal", it's "service failed, process dead."
  The error is immediate and clear (NoCredentialProviders). But with
  2/3 quorum, the cluster keeps working.

_____________________________________________________________________

[Recovery]

  ```
  mv /etc/vault.d/vault.env.backup /etc/vault.d/vault.env
  systemctl restart vault
  ```

  vault1 auto-unsealed immediately via AWS KMS, rejoined Raft cluster
  as follower. Cluster back to Healthy: true, Failure Tolerance: 1.
  Total recovery: ~3 minutes.

  ```
  vault operator raft list-peers
  vault1    follower    true     ← back online
  vault2    follower    true
  vault3    leader      true
  ```

_____________________________________________________________________

[Findings]

1. No credentials = no start. Vault doesn't stay sealed waiting for
   help — the service crashes. Systemd retries 3x then stops. This
   means credential loss is a hard failure, not a graceful degradation.

2. Single node credential loss doesn't affect the cluster. 2/3 quorum
   maintained, apps unaffected. See vault-single-node-down.md for
   new pod creation test during degraded state.

3. Recovery is trivial: restore vault.env + restart. Auto-unseal via
   KMS kicks in immediately, node rejoins Raft as follower. No manual
   unseal needed.

4. Credential backup matters. vault.env contains the AWS access key
   that makes auto-unseal work. If all 3 nodes lose it simultaneously
   (bad Ansible push, credential rotation gone wrong), the entire
   Vault cluster is dead and can't auto-recover.

_____________________________________________________________________

[References]

- vault-raft-quorum-loss.md — comparison: quorum loss vs single node loss
- /etc/vault.d/vault.hcl — seal "awskms" config
- /etc/vault.d/vault.env — AWS credentials (mode 0600, owner vault)
