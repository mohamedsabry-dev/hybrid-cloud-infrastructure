# TS-K8S-024 | 2026-04-11 | RESOLVED (Resilience Confirmed)
# REAL INCIDENT — Proxmox crash took down vault3. Documents successful HA resilience.
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / Vault
Sub-techs: Vault HA, Raft quorum, vault-agent sidecar, token renewal,
           Kubernetes Vault integration, LXC containers
Environment: DEV pve-dev | Vault HA cluster (vault1, vault2, vault3 on LXC)
Re-opened: No

_____________________________________________________________________

[Issue Description]
During Proxmox host crash (TS-PVE-015), CT 2006 (vault3) went down unexpectedly.
Verification needed: did Vault cluster maintain quorum with 2 nodes? Did
Kubernetes workloads continue operating without interruption?

This is a resilience confirmation case — not a failure.

Related tickets:
  TS-PVE-015  — Proxmox crash that caused vault3 to go down
  TS-VLT-005  — Vault node recovery (stale Raft data after crash)
  TS-K8S-014  — Vault K8s auth service account setup

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked Vault cluster status after vault3 went down.

Command:
  vault status (on vault1)

Output:
  Seal Type:    awskms
  Sealed:       false
  Storage Type: raft
  HA Mode:      active
  Active Since: 2026-04-11T11:12:29.439620263+02:00
  Raft Committed Index: 7237

Command:
  vault operator raft list-peers

Output:
  vault1  10.0.62.10:8201  leader    true
  vault2  10.0.62.11:8201  follower  true
  (vault3 absent — CT 2006 down)

Command:
  vault operator members

Output:
  vault1  https://10.0.62.10:8200  active    1.21.4
  vault2  https://10.0.62.11:8200  inactive  1.21.4  last echo: 13:41:14

Quorum calculation:
  Total nodes:        3
  Nodes down:         1 (vault3)
  Nodes up:           2 (vault1, vault2)
  Quorum requirement: (N/2)+1 = 2
  Quorum maintained:  YES — 2 >= 2

Checked Vault Agent Injector in Kubernetes:
  kubectl logs vault-agent-injector-74cf455f87-4st57 -n vault
  → Handler started, listening on :8080, cert bundle updated. No errors.

Checked vault-agent sidecar on MariaDB (token renewal log):
  2026-04-11T09:15:53  agent.auth.handler: authentication successful
  2026-04-11T09:58:35  agent.auth.handler: renewed auth token
  2026-04-11T10:41:17  agent.auth.handler: renewed auth token
  2026-04-11T11:24:00  agent.auth.handler: renewed auth token  ← AFTER crash (~11:01)

Token renewals continued through the crash. 11:24 renewal confirms connectivity
maintained post-crash. No authentication failures or connection errors in any
vault-agent sidecar.


# Suspected Root Cause
N/A — system operated as designed. No failure to diagnose.


# More Checks Notes:
Leadership timeline:
  Before crash:  vault1/2/3 sharing leader/follower roles
  During crash (~11:01):  vault3 crashed → remaining nodes hold election
  After stabilization (11:12:29):  vault1 elected leader, vault2 follower
  After CT 2006 unlocked and restarted:  vault3 rejoined as follower


# Suspected Solution
N/A — no action required. System self-healed.


# Test
N/A — resilience verified by observing continuous token renewals and no
disruption to vault-dependent workloads throughout the incident.

_____________________________________________________________________

[Final Root Cause]
N/A — documents successful resilience, not a failure.
Vault cluster operated as designed with 2-node quorum maintained throughout
vault3 outage. All Kubernetes workloads continued without interruption.

_____________________________________________________________________

[Final Solution]
No action required. System operated within designed fault tolerance.

After CT 2006 (vault3) was unlocked and restarted, vault3 rejoined the Raft
cluster automatically as a follower. See TS-VLT-005 for the vault3 rejoin
procedure (stale Raft data required data wipe and rejoin).

Verified: Yes (resilience confirmed)

_____________________________________________________________________

[Risk Level] N/A
Note: System operated within designed fault tolerance parameters.

_____________________________________________________________________

[References]
- TS-PVE-015 — Proxmox crash root cause
- TS-VLT-005 — vault3 Raft rejoin after stale data

_____________________________________________________________________

[Draft Notes]

Why Vault survived with 2 nodes:
  Vault Raft consensus requires a majority of nodes (quorum) to be available.
  3-node cluster:
    1 node down → 2/3 still majority → cluster operates normally
    2 nodes down → 1/3 not majority → cluster read-only (no writes)

Why Kubernetes workloads were unaffected:
  vault-agent sidecars connect to Vault via Kubernetes service (load balanced).
  They automatically retry on connection failure.
  Tokens are cached locally for short outages.
  Token renewals happen before expiration — brief leader elections are transparent.
  Only a cluster-wide Vault outage would affect workloads.

Verification commands:
  vault status
  vault operator raft list-peers
  vault operator members
  kubectl get pods -n vault
  kubectl logs -n vault -l app.kubernetes.io/name=vault-agent-injector
  kubectl logs <pod> -c vault-agent -n <namespace>
  kubectl logs <pod> -c vault-agent -n <namespace> | grep -i "error\|fail"