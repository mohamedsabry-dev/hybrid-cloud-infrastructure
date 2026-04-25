# TS-VLT-005 | 2026-04-11 | RESOLVED | INCIDENT
# Unplanned production failure (Proxmox crash during backup), not planned DR testing.
# Documented before DR test phase began.
_____________________________________________________________________

[Info]
Domain: Vault
Sub-techs: HashiCorp Vault HA, Raft consensus, AWS KMS auto-unseal, vault.db,
           LXC container recovery
Environment: DEV lab.local | pve-dev | vault1/vault2/vault3 on LXC containers
Re-opened: No

_____________________________________________________________________

[Issue Description]
After Proxmox host crash during backup (TS-PVE-015) and CT 2006 (vault3) recovery,
vault3 could not rejoin the Vault cluster. It had stale Raft data and thought it
belonged to a different cluster.

  vault3 after recovery:
    Cluster Name  vault-cluster-a8b762c2              ← WRONG
    Cluster ID    83b8c62f-55d1-6c34-33bd-a1f672c7ee6d  ← WRONG
    Raft Index    100                                  ← WAY BEHIND (vault1 at 7237)

  vault operator raft join https://vault1.lab.local:8200
  Key       Value
  ---       -----
  Joined    true
  (but vault status still showed wrong cluster ID after joining)

Impact:
  Vault cluster operating with only 2 nodes instead of 3.
  Reduced fault tolerance — loss of one more node would break quorum.
  vault3 isolated with stale data.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Compared cluster state between healthy node (vault1) and broken node (vault3):

  Attribute         vault1 (healthy)                          vault3 (broken)
  Cluster Name      vault-cluster-3dfa00ef                    vault-cluster-a8b762c2
  Cluster ID        1caaba58-fa2a-1581-84dd-e9a6eedf583b     83b8c62f-55d1-6c34-33bd-a1f672c7ee6d
  Raft Index        7237                                      100
  HA Mode           active (leader)                           standby


# Suspected Root Cause
Proxmox crashed mid-backup leaving vault3 data in inconsistent state.
vault3 has stale cluster identity that does not match the current cluster.


# More Checks Notes:

Attempt 1 — Simple raft join without clearing data (FAILED):
  vault operator raft join https://vault1.lab.local:8200
  Output: Joined: true
  vault status → still showed old cluster ID

  Why it failed: vault.db file contained old cluster identity. Raft join only
  updates Raft consensus state — it does not touch the main Vault database.

Attempt 2 — Remove raft directory only (FAILED):
  systemctl stop vault
  mv /opt/vault/data/raft /opt/vault/data/raft.bak.20260411
  mkdir -p /opt/vault/data/raft
  chown vault:vault /opt/vault/data/raft
  systemctl start vault
  vault operator raft join https://vault1.lab.local:8200

  vault status → still showed old cluster ID.

  ls -la /opt/vault/data/
  → vault.db still present with old cluster state.

  Why it failed: vault.db (main Vault database) stores cluster identity separately
  from the Raft directory. Both must be cleared for a clean rejoin.

  Vault stores cluster identity in TWO locations:
    /opt/vault/data/raft/    Raft consensus logs and snapshots
    /opt/vault/data/vault.db Main Vault database including cluster metadata

Attempt 3 — Remove all vault data (SUCCEEDED):
  systemctl stop vault
  rm -rf /opt/vault/data/raft
  rm -f /opt/vault/data/vault.db
  mkdir -p /opt/vault/data/raft
  chown -R vault:vault /opt/vault/data
  systemctl start vault
  (waited for AWS KMS auto-unseal, ~5-10 seconds)
  vault operator raft join https://vault1.lab.local:8200


# Suspected Root Cause (confirmed)
Stale vault.db persisted old cluster identity from before the crash.
Removing only the Raft directory was insufficient — vault.db must also be
removed for a clean cluster rejoin. Both files together define the node's
cluster identity.


# Test
After Attempt 3, verified from both vault3 and vault1.

Command:
  vault status  (on vault3)
  vault operator raft list-peers  (on vault1)

Result: PASS

  vault3 status:
    Cluster Name  vault-cluster-3dfa00ef               ← correct
    Cluster ID    1caaba58-fa2a-1581-84dd-e9a6eedf583b  ← correct
    HA Mode       standby
    Raft Committed Index  7246                          ← synced to leader

  vault operator raft list-peers:
    vault1  10.0.62.10:8201  leader    true
    vault2  10.0.62.11:8201  follower  true
    vault3  10.0.62.12:8201  follower  true

_____________________________________________________________________

[Final Root Cause]
Proxmox crashed mid-backup leaving vault3 with inconsistent data. vault.db
contained an old cluster identity that did not match the current cluster.
vault operator raft join returns success but does not clear the cluster identity
stored in vault.db — it only updates Raft consensus state. Both vault.db and
the raft directory must be removed for a clean rejoin.

_____________________________________________________________________

[Final Solution]
Complete node recovery procedure (safe on follower nodes when cluster has quorum):

  # 1. Stop Vault
  systemctl stop vault

  # 2. Backup existing data (optional, for investigation)
  mv /opt/vault/data/raft /opt/vault/data/raft.bak.$(date +%Y%m%d)
  mv /opt/vault/data/vault.db /opt/vault/data/vault.db.bak.$(date +%Y%m%d)

  # 3. Remove both files
  rm -rf /opt/vault/data/raft
  rm -f /opt/vault/data/vault.db

  # 4. Recreate directory structure
  mkdir -p /opt/vault/data/raft
  chown -R vault:vault /opt/vault/data

  # 5. Start Vault — AWS KMS auto-unseal triggers automatically
  systemctl start vault

  # 6. Wait for unseal (~5-10 seconds)
  sleep 5
  vault status  # Sealed: false, not yet joined

  # 7. Join the cluster
  vault operator raft join https://vault1.lab.local:8200

  # 8. Verify
  vault status                      # correct cluster name and ID
  vault operator raft list-peers    # all 3 nodes present

Why removing vault.db is safe on a follower:
  All secrets are replicated from the leader after rejoin.
  Local node identity is regenerated on join.
  Cached lease data re-synced from leader.
  Nothing permanent is lost — leader holds the source of truth.

IMPORTANT: NEVER do this on the leader node or when cluster has no quorum.

Why AWS KMS auto-unseal still works after removing vault.db:
  Vault reads unseal config from /etc/vault.d/vault.hcl (not vault.db).
  Contacts AWS KMS to decrypt the unseal key.
  Unseals automatically, then waits for raft join command.
  Unseal key is in AWS KMS — not affected by local file removal.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Safe only on a follower node when the cluster still has quorum (2 of 3
nodes healthy). All data replicates from leader after rejoin. No data loss.

_____________________________________________________________________

[References]
- TS-PVE-015 — Proxmox crash that triggered this incident
- TS-K8S-024 — Vault cluster resilience (2-node quorum survived during this)
- TS-VLT-001 — Initial Vault cluster setup

_____________________________________________________________________

[Draft Notes]

Key lesson: vault operator raft join returning success does not mean the node
is properly rejoined. Always verify cluster name and cluster ID in vault status
match the expected cluster. If they do not match, vault.db must be removed —
not just the raft directory.

If vault operator raft join fails silently (returns success but cluster ID wrong):
  Check and remove vault.db in addition to raft directory.
  Cluster identity stored in multiple locations.

Prevention:
  Use systemctl stop vault gracefully before any maintenance
  Ensure clean shutdown before backups
  Consider adding retry_join to vault.hcl for automatic cluster discovery

Commands reference:
  vault status                                    check cluster name, ID, raft index
  vault operator raft list-peers                  verify all nodes present
  vault operator members                          alternative membership check
  vault operator raft autopilot state             detailed autopilot health
  vault operator raft remove-peer <node-id>       force remove dead peer (from leader)
  vault operator raft join https://<leader>:8200  rejoin cluster