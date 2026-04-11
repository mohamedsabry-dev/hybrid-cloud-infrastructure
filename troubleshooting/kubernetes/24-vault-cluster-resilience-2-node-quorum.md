# TS-K8S-024 | 2026-04-11 | RESOLVED (Resilience Confirmed)

> **REAL INCIDENT** — This case occurred during an unplanned production failure (Proxmox crash took down vault3), not planned DR testing. Documents successful HA resilience before DR test phase began.

## 1. Context
- System: HashiCorp Vault HA Cluster (3 nodes on Proxmox LXC)
- Environment: pve-dev (vault1, vault2, vault3)
- Related components: Vault Raft storage, Kubernetes vault-agent-injector, K8s workloads using Vault secrets

## 2. Issue
- Symptom: During Proxmox host crash (TS-PVE-015), CT 2006 (vault3) went down unexpectedly. Need to confirm Vault cluster maintained quorum and Kubernetes operations continued normally.
- Context: Vault cluster runs on 3 LXC containers. With 1 node down, the cluster should maintain 2-node quorum (2/3 = majority) and continue serving requests.

**Question:** Did the Vault cluster survive with 2 nodes? Did Kubernetes workloads continue operating?

## 3. Analysis

### Vault Cluster Status After Incident

**Cluster health check:**
```bash
[root@vault1 ~]# vault status
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.21.4
Build Date               2026-03-04T17:40:05Z
Storage Type             raft
Cluster Name             vault-cluster-3dfa00ef
Cluster ID               1caaba58-fa2a-1581-84dd-e9a6eedf583b
Removed From Cluster     false
HA Enabled               true
HA Cluster               https://10.0.62.10:8201
HA Mode                  active
Active Since             2026-04-11T11:12:29.439620263+02:00
Raft Committed Index     7237
Raft Applied Index       7237
```

**Raft peer status (2 nodes active):**
```bash
[root@vault1 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    leader      true
vault2    10.0.62.11:8201    follower    true
```
- vault1: leader (active)
- vault2: follower (healthy)
- vault3: missing (CT 2006 was down/locked)

**Cluster membership:**
```bash
[root@vault1 ~]# vault operator members
Host Name    API Address                Cluster Address            Active Node    Version    Upgrade Version    Redundancy Zone    Last Echo
---------    -----------                ---------------            -----------    -------    ---------------    ---------------    ---------
vault1       https://10.0.62.10:8200    https://10.0.62.10:8201    true           1.21.4     1.21.4             n/a                n/a
vault2       https://10.0.62.11:8200    https://10.0.62.11:8201    false          1.21.4     1.21.4             n/a                2026-04-11T13:41:14+02:00
```

### Kubernetes Integration Status

**Vault Agent Injector (healthy):**
```bash
[root@k8s-master1 ~]# kubectl logs vault-agent-injector-74cf455f87-4st57 -n vault
2026-04-11T09:15:42.708Z [INFO]  handler.auto-tls: Generated CA
2026-04-11T09:15:42.730Z [INFO]  handler: Starting handler..
Listening on ":8080"...
2026-04-11T09:15:42.809Z [INFO]  handler.certwatcher: Updated certificate bundle received. Updating certs...
```
- Injector running normally
- No errors or disconnections

**Vault Agent Sidecar (workload example - MariaDB):**
```bash
[root@k8s-master1 ~]# kubectl logs mariadb-0 -n database -c vault-agent
==> Note: Vault Agent version does not match Vault server version. Vault Agent version: 1.21.2, Vault server version: 1.21.4
==> Vault Agent started! Log data will stream in below:
...
2026-04-11T09:15:53.528Z [INFO]  agent.auth.handler: authentication successful, sending token to sinks
2026-04-11T09:15:53.529Z [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
2026-04-11T09:15:53.532Z [INFO]  agent.auth.handler: starting renewal process
2026-04-11T09:58:35.741Z [INFO]  agent.auth.handler: renewed auth token
2026-04-11T10:41:17.924Z [INFO]  agent.auth.handler: renewed auth token
2026-04-11T11:24:00.101Z [INFO]  agent.auth.handler: renewed auth token
```
- Token renewals continued through the incident (~11:01 crash)
- 11:24:00 renewal confirms connectivity maintained post-crash
- No authentication failures or connection errors

## 4. Root Cause
> **Not applicable** - This case documents successful resilience, not a failure. The Vault cluster operated as designed with 2/3 nodes maintaining quorum.

## 5. Solution
> **No action required** - System self-healed. After CT 2006 (vault3) was unlocked and restarted, it would rejoin the Raft cluster automatically.

## 6. Solution Risk
- Risk level: N/A
- System operated within designed fault tolerance

## 7. Impact After Fix
- Observed: Zero downtime for Vault-dependent Kubernetes workloads
- Vault cluster maintained quorum with 2 nodes
- All token renewals succeeded
- No secret injection failures

## 8. Notes

### Why Vault Survived

| Factor | Value | Explanation |
|--------|-------|-------------|
| Total nodes | 3 | Configured for HA |
| Nodes down | 1 | vault3 (CT 2006) |
| Nodes up | 2 | vault1, vault2 |
| Quorum requirement | 2 | (N/2)+1 = (3/2)+1 = 2 |
| Quorum maintained | Yes | 2 >= 2 |

Vault's Raft consensus requires a majority of nodes (quorum) to be available. With 3-node cluster:
- 1 node down: 2/3 still majority, cluster operates normally
- 2 nodes down: 1/3 not majority, cluster becomes read-only (no writes)

### Leadership Timeline

```
[Before crash]
vault1: leader or follower
vault2: leader or follower
vault3: leader or follower

[During crash - 11:01]
vault3: crashed (CT 2006 down)
Remaining 2 nodes hold election if vault3 was leader

[After stabilization - 11:12:29]
vault1: elected leader (Active Since timestamp)
vault2: follower
vault3: absent

[After CT 2006 unlocked and started]
vault3: will rejoin as follower
```

### Kubernetes Workload Resilience

The vault-agent sidecars in Kubernetes pods:
1. Connect to Vault via Kubernetes service (load balanced)
2. Automatically retry on connection failure
3. Cache tokens locally for short outages
4. Renew tokens before expiration

This design ensures:
- Brief leader elections don't cause failures
- Single node loss is transparent to applications
- Only cluster-wide Vault outage affects workloads

### Verification Commands

```bash
# Check Vault cluster health
vault status
vault operator raft list-peers
vault operator members

# Check K8s Vault integration
kubectl get pods -n vault
kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector

# Check workload vault-agents
kubectl logs <pod> -c vault-agent -n <namespace>

# Check for failed auth attempts
kubectl logs <pod> -c vault-agent -n <namespace> | grep -i "error\|fail"
```

### Related Cases
- TS-PVE-015: Proxmox crash that caused vault3 to go down
- TS-VLT-005: Vault node recovery (stale Raft data after crash)
- TS-K8S-014: Vault K8s auth service account setup
- TS-K8S-017: Vault injection in system namespace

## 9. Workaround (if any)
> **None needed** - System operated within designed fault tolerance parameters. This case serves as documentation that the HA architecture works as expected.
