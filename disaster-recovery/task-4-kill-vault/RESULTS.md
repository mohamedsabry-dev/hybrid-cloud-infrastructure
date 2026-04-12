# Task 4: Kill Vault — DR Test Results

**Test Date:** 2026-04-13
**Environment:** dev
**Baseline:** WordPress browsing + video upload running throughout all scenarios
**Pre-test Backup:** Completed

---

## Scenario 4.1 — Single Vault Node Down

> **SKIPPED** — Already validated as real incident on April 11, 2026.
> See: [TS-VLT-005](../../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md), [TS-K8S-024](../../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

---

## Scenario 4.2 — Vault Quorum Loss + Injector Behavior (Combined with 4.4)

### Pre-Test State

**Timestamp:** 2026-04-13 00:48 EET

**Vault Cluster Status (from vault1):**
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
Active Since             2026-04-13T00:06:43.976688937+02:00
Raft Committed Index     7862
Raft Applied Index       7862
```

**Vault Raft Peers:**
```bash
[root@vault1 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    leader      true
vault2    10.0.62.11:8201    follower    true
vault3    10.0.62.12:8201    follower    true
```

**Proxmox LXC Status:**
```bash
root@pve-dev:~# pct list | grep vault
2004       running                 vault1
2005       running                 vault2
2006       running                 vault3
```

**vault-agent-injector Pods (2 replicas - HA):**
```bash
[root@k8s-master1 ~]# kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector -o wide
NAME                                    READY   STATUS    RESTARTS      AGE   IP              NODE                    NOMINATED NODE   READINESS GATES
vault-agent-injector-5877589b57-4h2ts   1/1     Running   2 (38m ago)   27h   10.244.43.179   k8s-master1.lab.local   <none>           <none>
vault-agent-injector-5877589b57-vphh7   1/1     Running   2 (38m ago)   27h   10.244.25.222   k8s-master3.lab.local   <none>           <none>
```

**Application Pods:**
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS    RESTARTS       AGE    IP               NODE                    NOMINATED NODE   READINESS GATES
wordpress-6d5cdf8c64-59jkd   2/2     Running   5 (37m ago)    34h    10.244.207.122   k8s-worker2.lab.local   <none>           <none>
wordpress-6d5cdf8c64-nwnn7   2/2     Running   12 (38m ago)   3d8h   10.244.62.29     k8s-worker1.lab.local   <none>           <none>
wordpress-6d5cdf8c64-rw6kt   2/2     Running   4 (38m ago)    33h    10.244.207.74    k8s-worker2.lab.local   <none>           <none>

[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS    RESTARTS      AGE   IP              NODE                    NOMINATED NODE   READINESS GATES
mariadb-0   2/2     Running   4 (38m ago)   33h   10.244.29.179   k8s-worker3.lab.local   <none>           <none>
```

**WordPress Baseline Check:**
```bash
[root@k8s-master1 ~]# curl http://wordpress-dev.lab.local/
<!DOCTYPE html>
<html lang="en-US">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
<title>WordPress Dev</title>
...
# HTML content returned successfully
```

**Pre-Test Summary:**

| Component | Status |
|-----------|--------|
| Vault1 (2004) | **leader**, unsealed, running |
| Vault2 (2005) | follower, running |
| Vault3 (2006) | follower, running |
| Raft Cluster | 3/3 healthy |
| Seal Type | awskms (auto-unseal) |
| vault-agent-injector | 2/2 replicas (master1, master3) |
| WordPress | 3 pods serving |
| MariaDB | 1 pod (worker3) |

### Step A — Quorum Loss Impact

**Action:** Stop 2 vault LXCs (leader + 1 follower)
```bash
pct stop 2004 && pct stop 2005
```

**Time:** 2026-04-13 00:53 EET

**Proxmox Status After Kill:**
```bash
root@pve-dev:~# pct list | grep vault
2004       stopped                 vault1
2005       stopped                 vault2
2006       running                 vault3
```

**Vault3 Status (surviving node):**
```bash
[root@vault3 ~]# vault status
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  1.21.4
Storage Type             raft
Cluster Name             vault-cluster-3dfa00ef
Cluster ID               1caaba58-fa2a-1581-84dd-e9a6eedf583b
HA Enabled               true
HA Cluster               https://10.0.62.10:8201
HA Mode                  standby                    ← STUCK IN STANDBY
Active Node Address      https://10.0.62.10:8200    ← POINTING TO DEAD LEADER
Raft Committed Index     7882
Raft Applied Index       7882

[root@vault3 ~]# vault operator raft list-peers
Error reading the raft cluster configuration: Get "https://10.0.62.10:8200/v1/sys/storage/raft/configuration": dial tcp 10.0.62.10:8200: connect: no route to host
```

**Key Finding:** Vault3 doesn't know it lost quorum — stuck in `standby` mode waiting for dead leader (10.0.62.10). Cannot elect itself as leader with only 1/3 nodes.

**Application Pods (unchanged):**
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS    RESTARTS       AGE    IP               NODE
wordpress-6d5cdf8c64-59jkd   2/2     Running   5 (42m ago)    34h    10.244.207.122   k8s-worker2
wordpress-6d5cdf8c64-nwnn7   2/2     Running   12 (43m ago)   3d8h   10.244.62.29     k8s-worker1
wordpress-6d5cdf8c64-rw6kt   2/2     Running   4 (43m ago)    33h    10.244.207.74    k8s-worker2

[root@k8s-master1 ~]# kubectl get pods -n database -o wide
NAME        READY   STATUS    RESTARTS      AGE   IP              NODE
mariadb-0   2/2     Running   4 (43m ago)   33h   10.244.29.179   k8s-worker3
```

**vault-agent-injector Pods (still running):**
```bash
[root@k8s-master1 ~]# kubectl get pods -n vault -l app.kubernetes.io/name=vault-agent-injector -o wide
NAME                                    READY   STATUS    RESTARTS      AGE   IP              NODE
vault-agent-injector-5877589b57-4h2ts   1/1     Running   2 (44m ago)   27h   10.244.43.179   k8s-master1
vault-agent-injector-5877589b57-vphh7   1/1     Running   2 (44m ago)   27h   10.244.25.222   k8s-master3
```

| Check | Result | Evidence |
|-------|--------|----------|
| Vault cluster unavailable (no quorum) | **YES** | vault3 stuck in standby, raft list-peers fails |
| Existing pods still serving with cached secrets | **YES** | WordPress + MariaDB running, no restarts |
| Vault UI inaccessible | **YES** | Leader (vault1) down |
| WordPress still working | **YES** | Login, browsing, DB queries all normal |

**Conclusion:** Existing pods with vault-agent sidecars continue serving using cached secrets. No impact on running workloads.

### Step B — Vault-Injector Deep Dive (while vault down)

**Action:** Scale WordPress to force new pod creation
```bash
[root@k8s-master1 ~]# kubectl scale deployment wordpress -n apps --replicas=4
deployment.apps/wordpress scaled
```

**Time:** 2026-04-13 00:55 EET

**New Pod Stuck on Init:**
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS     RESTARTS       AGE    IP               NODE
wordpress-6d5cdf8c64-59jkd   2/2     Running    5 (44m ago)    34h    10.244.207.122   k8s-worker2
wordpress-6d5cdf8c64-hxj9s   0/2     Init:1/2   0              7s     10.244.29.183    k8s-worker3  ← STUCK
wordpress-6d5cdf8c64-nwnn7   2/2     Running    12 (45m ago)   3d8h   10.244.62.29     k8s-worker1
wordpress-6d5cdf8c64-rw6kt   2/2     Running    4 (45m ago)    33h    10.244.207.74    k8s-worker2
```

**vault-agent-init Logs (authentication failures):**
```bash
[root@k8s-master1 ~]# kubectl logs wordpress-6d5cdf8c64-hxj9s -n apps -c vault-agent-init
==> Vault Agent started! Log data will stream in below:

2026-04-12T22:55:45.993Z [INFO]  agent.auth.handler: starting auth handler
2026-04-12T22:55:45.993Z [INFO]  agent.auth.handler: authenticating
2026-04-12T22:55:46.693Z [ERROR] agent.auth.handler: error authenticating:
    error="Put \"https://10.0.62.10:8200/v1/auth/kubernetes/login\":
    dial tcp 10.0.62.10:8200: connect: no route to host" backoff=770ms
2026-04-12T22:55:47.464Z [INFO]  agent.auth.handler: authenticating
2026-04-12T22:55:50.213Z [ERROR] agent.auth.handler: error authenticating:
    error="... dial tcp 10.0.62.10:8200: connect: no route to host" backoff=770ms
2026-04-12T22:55:51.689Z [INFO]  agent.auth.handler: authenticating
2026-04-12T22:55:54.453Z [ERROR] agent.auth.handler: error authenticating:
    error="... dial tcp 10.0.62.10:8200: connect: no route to host" backoff=1.47s
2026-04-12T22:55:57.263Z [INFO]  agent.auth.handler: authenticating
2026-04-12T22:55:58.133Z [ERROR] agent.auth.handler: error authenticating:
    error="... dial tcp 10.0.62.10:8200: connect: no route to host" backoff=2.8s
2026-04-12T22:56:02.898Z [INFO]  agent.auth.handler: authenticating
2026-04-12T22:56:05.813Z [ERROR] agent.auth.handler: error authenticating:
    error="... dial tcp 10.0.62.10:8200: connect: no route to host" backoff=4.76s
```

**Key Findings:**
1. New pod stuck at `Init:1/2` - passed `wait-for-mariadb`, stuck on `vault-agent-init`
2. vault-agent-init trying to reach dead leader (10.0.62.10:8200)
3. Exponential backoff: 770ms → 1.47s → 2.8s → 4.76s → continues indefinitely
4. Pod will remain stuck until vault quorum restored

| Check | Result | Evidence |
|-------|--------|----------|
| vault-injector sidecar behavior | **Injected** | Init container added to new pod |
| Init container timeout behavior | **Infinite retry** | Exponential backoff, no timeout |
| New pods pending/timeout (expected) | **YES - STUCK** | Init:1/2, can't authenticate |

**Conclusion:** New pods CANNOT start when vault has no quorum. They get stuck on `vault-agent-init` waiting for vault authentication.

**Why vault-agent tries 10.0.62.10 instead of VIP:**

The vault-agent-injector IS configured with VIP (`vault.lab.local:8200`), but vault-agent connects directly to leader IP. This is **Raft HA behavior**:

```bash
[root@k8s-master1 ~]# kubectl describe deploy vault-agent-injector -n vault | grep -i addr
      AGENT_INJECT_VAULT_ADDR:                             https://vault.lab.local:8200
```

```bash
[root@vault3 ~]# vault status
HA Mode                  standby                    ← Can't elect itself (1/3 = no quorum)
Active Node Address      https://10.0.62.10:8200    ← Still points to dead leader
```

**How it works:**
1. vault-agent connects to VIP → reaches vault3
2. vault3 says "I'm standby, leader is at 10.0.62.10"
3. vault-agent tries 10.0.62.10 → dead
4. Retries forever with exponential backoff

**Raft Quorum Requirements:**

| Nodes Up | Majority? | Can Elect Leader? | Status |
|----------|-----------|-------------------|--------|
| 3/3 | YES | YES | Fully operational |
| 2/3 | YES | YES | Operational (degraded) |
| 1/3 | NO | NO | **Stuck in standby** |

**Key Insight:** Single vault node cannot self-heal. Must restore at least 2/3 for quorum.

### Step C — Recovery

**Action:** Start vault1 only (test 2/3 quorum)
```bash
pct start 2004
```

**Time:** 2026-04-13 01:06 EET

**Quorum Restored with 2/3 Nodes:**
```bash
[root@vault1 ~]# vault status
HA Mode                  standby
Active Node Address      https://10.0.62.12:8200    ← vault3 is now leader!

[root@vault1 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    follower    true    ← rejoined as follower
vault2    10.0.62.11:8201    follower    true    ← still offline
vault3    10.0.62.12:8201    leader      true    ← PROMOTED TO LEADER
```

**Key Finding:** vault3 was promoted to leader once quorum (2/3) was restored. vault1 rejoined as follower.

**New Pod Successfully Gets Secrets:**
```bash
[root@k8s-master1 ~]# kubectl scale deployment wordpress -n apps --replicas=4
deployment.apps/wordpress scaled

[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS     AGE   NODE
wordpress-6d5cdf8c64-p9xn4   0/2     Init:0/2   2s    k8s-worker3  ← NEW POD
wordpress-6d5cdf8c64-p9xn4   0/2     PodInitializing   5s
wordpress-6d5cdf8c64-p9xn4   1/2     Running    7s
wordpress-6d5cdf8c64-p9xn4   2/2     Running    12s   ← FULLY READY!
```

**Timeline:** `Init:0/2` → `2/2 Running` in **12 seconds**

| Check | Result | Evidence |
|-------|--------|----------|
| Quorum restored | **YES** | 2/3 nodes = majority |
| Vault unsealed (auto-unseal) | **YES** | AWS KMS auto-unseal worked |
| Leader election | **YES** | vault3 promoted to leader |
| New pods can fetch secrets | **YES** | p9xn4 got secrets in 12s |
| WordPress working | **YES** | 4/4 pods running |

**Note:** Original stuck pod (`hxj9s`) was replaced. Kubernetes garbage collected it after extended init timeout.

### Raft Cluster Deep Dive (while vault2 still offline)

**`raft list-peers` vs `raft autopilot state`:**

```bash
[root@vault3 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    follower    true
vault2    10.0.62.11:8201    follower    true    ← Shows as follower (but offline!)
vault3    10.0.62.12:8201    leader      true
```

**Important:** `raft list-peers` shows **configured membership**, not live status!

**To see actual health, use `autopilot state`:**

```bash
[root@vault3 ~]# vault operator raft autopilot state
Healthy:                         false        ← Cluster degraded (vault2 down)
Failure Tolerance:               0            ← Can't lose any more nodes!
Leader:                          vault3
Voters:
   vault3
   vault1
   vault2
Servers:
   vault1
      Name:              vault1
      Address:           10.0.62.10:8201
      Status:            voter
      Node Status:       alive
      Healthy:           true               ← Actually online
      Last Contact:      2.622420854s       ← Recent heartbeat
      Last Term:         50
      Last Index:        7984

   vault2
      Name:              vault2
      Address:           10.0.62.11:8201
      Status:            voter
      Node Status:       alive
      Healthy:           false              ← OFFLINE
      Last Contact:      5m40.001130079s    ← No heartbeat for 5+ minutes
      Last Term:         0
      Last Index:        0

   vault3
      Name:              vault3
      Address:           10.0.62.12:8201
      Status:            leader
      Node Status:       alive
      Healthy:           true
      Last Contact:      0s                 ← It's the leader
      Last Term:         50
      Last Index:        7984
```

**Key Insights:**

| Metric | Value | Meaning |
|--------|-------|---------|
| `Healthy: false` | Cluster degraded | Not all voters online |
| `Failure Tolerance: 0` | Critical | One more failure = total outage |
| vault2 `Last Contact: 5m40s` | No heartbeat | Node is offline |
| vault2 `Last Index: 0` | No raft sync | Never synced since restart |

**Why vault2 stays in peer list:**
- Raft keeps configured members even when offline
- Allows automatic rejoin when node comes back
- Only `vault operator raft remove-peer` removes a node

### Full Cluster Restoration

**Action:** Start vault2
```bash
pct start 2005
```

**Time:** 2026-04-13 01:15 EET

**Cluster Fully Healthy:**
```bash
[root@vault3 ~]# vault operator raft autopilot state
Healthy:                         true         ← Cluster healthy!
Failure Tolerance:               1            ← Can lose 1 node now
Leader:                          vault3
Servers:
   vault1
      Healthy:           true
      Last Contact:      622.507101ms
      Last Index:        7984

   vault2
      Healthy:           true                 ← Back online!
      Last Contact:      4.907858406s
      Last Index:        7984                 ← Synced with cluster

   vault3
      Status:            leader
      Healthy:           true
      Last Index:        7984
```

**Flux Auto-Scaled WordPress Back to 3:**
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS    RESTARTS       AGE     IP              NODE
wordpress-6d5cdf8c64-nwnn7   2/2     Running   13 (12m ago)   3d8h    10.244.62.29    k8s-worker1
wordpress-6d5cdf8c64-p9xn4   2/2     Running   0              7m24s   10.244.29.178   k8s-worker3
wordpress-6d5cdf8c64-rw6kt   2/2     Running   5 (16m ago)    34h     10.244.207.74   k8s-worker2
```

**Flux Auto-Heal Evidence:**

```bash
[root@k8s-master1 ~]# flux events --for Kustomization/apps
LAST SEEN   TYPE    REASON                  OBJECT              MESSAGE
10m         Normal  Progressing             Kustomization/apps  Deployment/apps/wordpress configured  ← Auto-scaled back!
5m          Normal  ReconciliationSucceeded Kustomization/apps  Reconciliation finished in 374.640582ms, next run in 5m0s

[root@k8s-master1 ~]# kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -5
10m   Normal  Progressing              kustomization/apps   Deployment/apps/wordpress configured
8s    Normal  ReconciliationSucceeded  kustomization/apps   Reconciliation finished in 396.492946ms, next run in 5m0s
```

**Note:** Flux reconciles every 5 minutes. When we scaled to 4 replicas manually, Flux auto-corrected back to 3 (as defined in Git). This is **GitOps self-healing** in action!

### Scenario 4.2 Summary

| Phase | Duration | Result |
|-------|----------|--------|
| Pre-test baseline | - | 3/3 vault healthy, WordPress serving |
| Step A: Kill quorum | 00:53 | 1/3 vault, existing pods OK, new pods stuck |
| Step B: New pod test | 00:55 | vault-agent-init stuck (infinite retry) |
| Step C: Restore 2/3 | 01:06 | Quorum restored, vault3 became leader |
| New pod recovery | 01:07 | Pod got secrets in 12 seconds |
| Full restore 3/3 | 01:15 | Cluster fully healthy |

**Status:** PASS

**Key Findings:**
1. Existing pods survive quorum loss (cached secrets)
2. New pods cannot start without quorum (stuck on vault-agent-init)
3. 2/3 nodes = quorum restored, leader election works
4. AWS KMS auto-unseal works on node restart
5. Flux GitOps auto-heals manual scaling changes

### Scenario 4.2 Summary
- **Status:**
- **Duration:**
- **Issues Found:**

---

## Scenario 4.3 — AWS KMS Auto-Unseal Dependency

### Pre-Test State
```bash
# Current vault seal status
vault status | grep "Seal Type"

# AWS KMS key check
aws kms describe-key --key-id <key-id>
```

### Test Execution

**Action:** Break AWS KMS credentials
```bash
# Method: (rotate key / change secrets / revoke IAM)
```

**Action:** Restart vault LXC
```bash
pct restart 2004
```

| Check | Result | Evidence |
|-------|--------|----------|
| Vault stays sealed on startup | | |
| Auto-unseal fails (expected) | | |
| App impact — cached secrets still working | | |

### Recovery

**Action:** Restore AWS KMS credentials
```bash
# Restore method:
```

**Action:** Restart vault service
```bash
systemctl restart vault
```

| Check | Result | Evidence |
|-------|--------|----------|
| Auto-unseal succeeds on restart | | |
| Vault cluster healthy | | |
| App recovers | | |

## Scenario 4.3 — AWS KMS Auto-Unseal Dependency

### Setup Overview

Vault uses AWS KMS for auto-unseal. Credentials flow:

```
AWS Secrets Manager → GitHub Actions → Ansible → /etc/vault.d/vault.env → systemd
```

**Full setup details:** See [deployment-docs/vault-initial-setup-guide.txt](../../deployment-docs/vault-initial-setup-guide.txt)

**Discovery Commands (if setup unknown):**

```bash
# Check seal configuration
cat /etc/vault.d/vault.hcl | grep -A10 'seal'

# Check where credentials come from
systemctl show vault | grep -i environment

# View credentials file (if exists)
cat /etc/vault.d/vault.env
```

**Current Configuration (vault1):**

```bash
[root@vault1 ~]# cat /etc/vault.d/vault.hcl | grep -A10 'seal'
seal "awskms" {
  region     = "us-east-1"
  kms_key_id = "alias/vault-unseal"
}

[root@vault1 ~]# systemctl show vault | grep -i environment
EnvironmentFiles=/etc/vault.d/vault.env (ignore_errors=no)
```

**Credentials Location:** `/etc/vault.d/vault.env` (mode 0600, owner vault)
- Contains: `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY`
- Loaded by systemd on vault service start

### Pre-Test State

**Timestamp:** 2026-04-13 01:25 EET

```bash
[root@vault1 ~]# vault status | grep -i seal
Seal Type                awskms
Recovery Seal Type       shamir
Sealed                   false
```

### Test Execution

**Action:** Break AWS credentials on vault1

```bash
[root@vault1 vault.d]# cp vault.env vault.env.backup
[root@vault1 vault.d]# echo "# BROKEN FOR DR TEST" > vault.env
[root@vault1 vault.d]# cat /etc/vault.d/vault.env
# BROKEN FOR DR TEST

[root@vault1 vault.d]# systemctl restart vault
Job for vault.service failed because the control process exited with error code.
See "systemctl status vault.service" and "journalctl -xeu vault.service" for details.

[root@vault1 vault.d]# vault status
Error checking seal status: Get "https://vault1.lab.local:8200/v1/sys/seal-status":
dial tcp 10.0.62.10:8200: connect: connection refused
```

**Time:** 2026-04-13 01:30 EET

**Cluster Status (from vault3):**
```bash
[root@vault3 ~]# vault operator raft autopilot state
Healthy:                         false        ← Degraded (vault1 down)
Failure Tolerance:               0            ← Can't lose another node
Leader:                          vault3
Servers:
   vault1
      Healthy:           false               ← SERVICE FAILED TO START
      Last Contact:      29.623436524s

   vault2
      Healthy:           true                ← Still healthy
      Last Contact:      3.908415532s

   vault3
      Status:            leader              ← Still leader
      Healthy:           true

[root@vault3 ~]# vault status
Sealed                   false               ← Cluster still unsealed!
HA Mode                  active
```

**Key Difference from Scenario 4.2:**
- 4.2: Killed 2 nodes → lost quorum → new pods STUCK
- 4.3: Killed 1 node → 2/3 quorum → new pods CAN get secrets!

**New Pod Test (while vault1 down):**
```bash
[root@k8s-master1 ~]# kubectl scale deployment wordpress -n apps --replicas=4
deployment.apps/wordpress scaled

[root@k8s-master1 ~]# kubectl get pods -n apps -o wide -w
NAME                         READY   STATUS     AGE
wordpress-6d5cdf8c64-4rtg9   0/2     Init:0/2   1s    ← New pod
wordpress-6d5cdf8c64-4rtg9   0/2     Init:1/2   2s    ← wait-for-mariadb passed
wordpress-6d5cdf8c64-4rtg9   1/2     Running    5s    ← vault-agent-init passed!
wordpress-6d5cdf8c64-4rtg9   2/2     Running    11s   ← FULLY READY
```

**New pod got secrets in 11 seconds** even with vault1 down!

| Check | Result | Evidence |
|-------|--------|----------|
| Vault1 fails to start | **YES** | Service failed, connection refused |
| Cluster still operational | **YES** | vault2+vault3 = 2/3 quorum |
| New pods CAN get secrets | **YES** | Pod ready in 11s (unlike 4.2!) |
| Apps unaffected | **YES** | WordPress serving normally |

### Failure Logs (journalctl)

```bash
# AWS KMS failure - no credentials
Apr 13 01:31:27 vault1 vault[1376]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders: no valid providers in chain. Deprecated.
Apr 13 01:31:27 vault1 vault[1376]:         For verbose messaging see aws.Config.CredentialsChainVerboseErrors
Apr 13 01:31:27 vault1 systemd[1]: vault.service: Main process exited, code=exited, status=1/FAILURE
Apr 13 01:31:27 vault1 systemd[1]: Failed to start vault.service - "HashiCorp Vault - A tool for managing secrets".

# Systemd retry attempts (3x then give up)
Apr 13 01:31:32 vault1 systemd[1]: vault.service: Scheduled restart job, restart counter is at 1.
Apr 13 01:31:33 vault1 vault[1392]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders
Apr 13 01:31:38 vault1 systemd[1]: vault.service: Scheduled restart job, restart counter is at 2.
Apr 13 01:31:38 vault1 vault[1408]: error parsing Seal configuration: error fetching AWS KMS wrapping key information: NoCredentialProviders
Apr 13 01:31:44 vault1 systemd[1]: vault.service: Scheduled restart job, restart counter is at 3.
Apr 13 01:31:44 vault1 systemd[1]: vault.service: Start request repeated too quickly.
Apr 13 01:31:44 vault1 systemd[1]: Failed to start vault.service - "HashiCorp Vault - A tool for managing secrets".
```

### Recovery

**Action:** Restore AWS credentials

```bash
[root@vault1 vault.d]# rm vault.env
rm: remove regular file 'vault.env'? y

[root@vault1 vault.d]# mv vault.env.backup vault.env

[root@vault1 vault.d]# systemctl restart vault

[root@vault1 vault.d]# vault status
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false              ← AUTO-UNSEALED!
HA Mode                  standby
Active Node Address      https://10.0.62.12:8200
```

**Time:** 2026-04-13 01:34 EET

**Recovery Logs (journalctl):**
```bash
Apr 13 01:34:24 vault1 systemd[1]: Starting vault.service - "HashiCorp Vault - A tool for managing secrets"...
Apr 13 01:34:25 vault1 vault[1587]: ==> Vault server configuration:
Apr 13 01:34:25 vault1 vault[1587]:    Environment Variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, ...  ← Credentials loaded!
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.452+0200 [INFO]  core: stored unseal keys supported, attempting fetch
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  core: vault is unsealed
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  core: unsealed with stored key  ← AWS KMS auto-unseal worked!
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  core: entering standby mode
Apr 13 01:34:25 vault1 vault[1587]: 2026-04-13T01:34:25.861+0200 [INFO]  storage.raft: entering follower state
Apr 13 01:34:25 vault1 systemd[1]: Started vault.service - "HashiCorp Vault - A tool for managing secrets".
```

**Cluster Fully Restored:**
```bash
[root@vault1 vault.d]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    follower    true     ← Back online!
vault2    10.0.62.11:8201    follower    true
vault3    10.0.62.12:8201    leader      true

[root@vault1 vault.d]# vault operator raft autopilot state
Healthy:                         true         ← Cluster healthy!
Failure Tolerance:               1            ← Can lose 1 node
Leader:                          vault3
Servers:
   vault1    Healthy: true    Last Contact: 3.5s
   vault2    Healthy: true    Last Contact: 1.9s
   vault3    Healthy: true    (leader)
```

| Check | Result | Evidence |
|-------|--------|----------|
| Auto-unseal succeeds on restart | **YES** | `core: unsealed with stored key` |
| Vault cluster healthy | **YES** | `Healthy: true`, `Failure Tolerance: 1` |
| vault1 rejoined cluster | **YES** | Shows as follower in raft peers |

### Scenario 4.3 Summary

| Phase | Time | Result |
|-------|------|--------|
| Break credentials | 01:31 | vault1 failed to start (NoCredentialProviders) |
| Cluster impact | - | 2/3 quorum maintained, apps unaffected |
| New pod test | - | Pod got secrets in 11s (vault2/3 healthy) |
| Restore credentials | 01:34 | vault1 auto-unsealed, rejoined cluster |

- **Status:** PASS
- **Duration:** ~3 minutes
- **Issues Found:** None

**Key Findings:**
1. Without AWS credentials, vault cannot start at all (not just sealed - service fails)
2. Error is clear: `NoCredentialProviders: no valid providers in chain`
3. Systemd retries 3x then gives up
4. 2/3 quorum maintained - apps unaffected during single node failure
5. Restoring credentials → auto-unseal works immediately

---

## Task 4 — Overall Summary

### Test Results

| Scenario | Status | Key Finding |
|----------|--------|-------------|
| 4.1 Single Node Down | SKIPPED | Validated in real incident (TS-VLT-005, TS-K8S-024) |
| 4.2 Quorum Loss (2/3 down) | **PASS** | Existing pods OK, new pods STUCK, 2/3 restores quorum |
| 4.3 AWS KMS Dependency | **PASS** | No creds = service fails, 2/3 quorum = apps OK |

### Critical Learnings

1. **Quorum is everything:**
   - 2/3 nodes = operational (can serve new pods)
   - 1/3 nodes = stuck (can't elect leader, new pods fail)

2. **Cached secrets save the day:**
   - Existing pods with vault-agent sidecar continue working
   - No immediate impact on running workloads

3. **AWS KMS is critical dependency:**
   - No credentials = vault won't even start
   - Keep credentials backed up and accessible

4. **vault-agent-injector HA works:**
   - 2 replicas on different masters
   - Survives node failures

5. **Flux GitOps self-heals:**
   - Manual scaling reverted automatically
   - Cluster state enforced from Git

### Recovery Procedures Validated

| Scenario | Recovery Steps |
|----------|----------------|
| Quorum loss | Start vault nodes → auto-unseal → auto-rejoin |
| AWS KMS failure | Restore /etc/vault.d/vault.env → restart vault |

### Recommendations

1. **Monitor vault quorum** - Alert if Failure Tolerance = 0
2. **Backup AWS credentials** - Keep vault.env accessible for emergencies
3. **Test regularly** - Vault HA is complex, validate assumptions

### Related Troubleshooting Cases
- [TS-VLT-005](../../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md)
- [TS-K8S-024](../../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

---

**Task 4 Completed:** 2026-04-13 01:35 EET
**Total Duration:** ~45 minutes
**Overall Status:** PASS
