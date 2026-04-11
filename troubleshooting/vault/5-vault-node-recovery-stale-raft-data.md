# TS-VLT-005 | 2026-04-11 | RESOLVED

## 1. Context
- System: HashiCorp Vault HA Cluster (3-node Raft)
- Environment: pve-dev (vault1, vault2, vault3 on LXC containers)
- Related components: Raft consensus, AWS KMS auto-unseal, LXC container recovery
- Trigger: Proxmox host crash during backup (TS-PVE-015)

## 2. Issue
- Symptom: After Proxmox crash and CT 2006 (vault3) recovery, vault3 node could not rejoin the Vault cluster. It had stale Raft data and thought it belonged to a different cluster.
- Error:
```bash
[root@vault3 ~]# vault status
Cluster Name             vault-cluster-a8b762c2    # WRONG - should be vault-cluster-3dfa00ef
Cluster ID               83b8c62f-55d1-6c34-33bd-a1f672c7ee6d  # WRONG
HA Mode                  standby
Active Node Address      https://10.0.62.11:8200
Raft Committed Index     100    # WAY BEHIND - vault1 was at 7237

# Attempting to join returned success but didn't fix the issue
[root@vault3 ~]# vault operator raft join https://vault1.lab.local:8200
Key       Value
---       -----
Joined    true

# But status still showed wrong cluster
[root@vault3 ~]# vault status
Cluster ID               83b8c62f-55d1-6c34-33bd-a1f672c7ee6d  # Still wrong!
```

**Impact:**
- Vault cluster operating with only 2 nodes instead of 3
- Reduced fault tolerance (loss of one more node would break quorum)
- vault3 isolated with stale data

## 3. Analysis

### Cluster State Comparison

| Attribute | vault1 (healthy) | vault3 (broken) |
|-----------|------------------|-----------------|
| Cluster Name | vault-cluster-3dfa00ef | vault-cluster-a8b762c2 |
| Cluster ID | 1caaba58-fa2a-1581-84dd-e9a6eedf583b | 83b8c62f-55d1-6c34-33bd-a1f672c7ee6d |
| Raft Index | 7237 | 100 |
| HA Mode | active (leader) | standby |

### Attempt 1: Simple Raft Join (FAILED)

```bash
# Tried joining without clearing data
vault operator raft join https://vault1.lab.local:8200
# Returned: Joined: true
# But vault status still showed old cluster ID
```

**Why it failed:** Vault's local `vault.db` file contained the old cluster identity. The Raft join only updates Raft consensus state, not the main Vault database.

### Attempt 2: Remove Raft Directory Only (FAILED)

```bash
systemctl stop vault
mv /opt/vault/data/raft /opt/vault/data/raft.bak.20260411
mkdir -p /opt/vault/data/raft
chown vault:vault /opt/vault/data/raft
systemctl start vault
vault operator raft join https://vault1.lab.local:8200
```

**Why it failed:** The `vault.db` file (main Vault database) still contained the stale cluster identity:
```bash
ls -la /opt/vault/data/
# Shows vault.db still present with old cluster state
```

### Attempt 3: Remove All Vault Data (SUCCEEDED)

```bash
systemctl stop vault
rm -rf /opt/vault/data/raft
rm -f /opt/vault/data/vault.db
mkdir -p /opt/vault/data/raft
chown -R vault:vault /opt/vault/data
systemctl start vault
# Wait for auto-unseal via AWS KMS
vault operator raft join https://vault1.lab.local:8200
```

## 4. Root Cause
> **Stale vault.db persisted old cluster identity.** When Proxmox crashed mid-backup, vault3's data was in an inconsistent state. The `vault.db` file contained an old cluster identity that didn't match the current cluster. Simply removing the Raft directory was insufficient because Vault stores cluster identity in both:
> 1. `/opt/vault/data/raft/` - Raft consensus logs and snapshots
> 2. `/opt/vault/data/vault.db` - Main Vault database including cluster metadata
>
> Both must be removed for a clean rejoin.

## 5. Solution

### Complete Node Recovery Procedure

```bash
# 1. Stop Vault service
systemctl stop vault

# 2. Backup existing data (optional, for investigation)
mv /opt/vault/data/raft /opt/vault/data/raft.bak.$(date +%Y%m%d)
mv /opt/vault/data/vault.db /opt/vault/data/vault.db.bak.$(date +%Y%m%d)

# 3. Or simply remove all data for clean rejoin
rm -rf /opt/vault/data/raft
rm -f /opt/vault/data/vault.db

# 4. Recreate directory structure
mkdir -p /opt/vault/data/raft
chown -R vault:vault /opt/vault/data

# 5. Start Vault (will auto-unseal via AWS KMS)
systemctl start vault

# 6. Wait for unsealing (5-10 seconds with KMS)
sleep 5
vault status  # Should show Sealed: false but not joined yet

# 7. Join the existing cluster
vault operator raft join https://vault1.lab.local:8200
# Or: vault operator raft join https://vault2.lab.local:8200

# 8. Verify join successful
vault status
# Should show:
# - Correct Cluster Name: vault-cluster-3dfa00ef
# - Correct Cluster ID: 1caaba58-fa2a-1581-84dd-e9a6eedf583b
# - HA Mode: standby
# - Raft Index matching leader

# 9. Verify from leader node
vault operator raft list-peers
# Should show all 3 nodes
```

### Verification Output

```bash
[root@vault1 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    leader      true
vault2    10.0.62.11:8201    follower    true
vault3    10.0.62.12:8201    follower    true

[root@vault3 ~]# vault status
Cluster Name             vault-cluster-3dfa00ef
Cluster ID               1caaba58-fa2a-1581-84dd-e9a6eedf583b
HA Mode                  standby
Active Node Address      https://10.0.62.10:8200
Raft Committed Index     7246
Raft Applied Index       7246
```

## 6. Solution Risk
- Risk level: LOW
- Removing data from a single follower node is safe when:
  - Cluster still has quorum (2 of 3 nodes healthy)
  - Leader node has current data
  - Node will replicate all data after rejoin
- Data loss: None (vault3 receives all data from leader after rejoining)

## 7. Impact After Fix
- Observed: vault3 successfully rejoined cluster as follower
- Raft index synced to current state (7246)
- Cluster back to full 3-node redundancy
- Kubernetes workloads unaffected throughout (were using vault1/vault2)

## 8. Notes

### What Gets Lost When Removing vault.db

When you remove a follower node's vault.db:
- Local node identity (regenerated on join)
- Cached lease data (re-synced from leader)
- **Nothing permanent** - all secrets are replicated from leader

**Important:** NEVER do this on the leader node or when cluster has no quorum!

### Why Auto-Unseal Still Worked

With AWS KMS auto-unseal:
1. Vault starts and reads config from `/etc/vault.d/vault.hcl`
2. Contacts AWS KMS to decrypt the unseal key
3. Unseals automatically
4. Then waits for Raft join command to join cluster

The unseal key is stored in AWS KMS, not in local files, so removing `vault.db` doesn't affect unsealing.

### Prevention

To prevent stale data issues after crashes:
1. Use `systemctl stop vault` gracefully before maintenance
2. Ensure clean shutdown before backups
3. Consider adding `retry_join` to vault.hcl for automatic cluster discovery

### Commands Reference

```bash
# Check cluster status from any node
vault status
vault operator raft list-peers
vault operator members

# Force remove a dead peer (from leader)
vault operator raft remove-peer <node-id>

# Join existing cluster
vault operator raft join https://<leader>:8200

# Check Raft autopilot status
vault operator raft autopilot state
```

### Related Cases
- TS-PVE-015: Proxmox crash that caused this issue
- TS-K8S-024: Vault cluster resilience (2-node quorum survived)
- TS-VLT-001: Initial Vault cluster setup

## 9. Workaround (if any)
> If `vault operator raft join` fails silently (returns success but doesn't fix cluster ID), always check and remove `vault.db` in addition to the raft directory. The cluster identity is stored in multiple locations.
