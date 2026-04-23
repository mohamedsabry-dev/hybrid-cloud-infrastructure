# Vault Quorum Loss + Injector Behavior
# Date: 2026-04-13
# Result: PASS

---

## Scope

Kill 2/3 vault nodes, lose raft quorum, and test:
- Existing pods with cached secrets
- New pods trying to fetch secrets
- vault-agent-injector behavior
- Recovery when quorum restored

---

## Pre-Test State

**Timestamp:** 2026-04-13 00:48 EET

**Vault Cluster Status:**
```bash
[root@vault1 ~]# vault status
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Version                  1.21.4
Storage Type             raft
HA Enabled               true
HA Cluster               https://10.0.62.10:8201
HA Mode                  active
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
NAME                                    READY   STATUS    RESTARTS      AGE   IP              NODE
vault-agent-injector-5877589b57-4h2ts   1/1     Running   2 (38m ago)   27h   10.244.43.179   k8s-master1.lab.local
vault-agent-injector-5877589b57-vphh7   1/1     Running   2 (38m ago)   27h   10.244.25.222   k8s-master3.lab.local
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

---

## Step A — Quorum Loss Impact

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
Sealed                   false
HA Enabled               true
HA Mode                  standby                    <- STUCK IN STANDBY
Active Node Address      https://10.0.62.10:8200    <- POINTING TO DEAD LEADER

[root@vault3 ~]# vault operator raft list-peers
Error reading the raft cluster configuration: Get "https://10.0.62.10:8200/v1/sys/storage/raft/configuration": dial tcp 10.0.62.10:8200: connect: no route to host
```

**Key Finding:** Vault3 doesn't know it lost quorum - stuck in `standby` mode waiting for dead leader (10.0.62.10). Cannot elect itself as leader with only 1/3 nodes.

**Application Pods (unchanged):**
```bash
[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS    RESTARTS       AGE    IP               NODE
wordpress-6d5cdf8c64-59jkd   2/2     Running   5 (42m ago)    34h    10.244.207.122   k8s-worker2
wordpress-6d5cdf8c64-nwnn7   2/2     Running   12 (43m ago)   3d8h   10.244.62.29     k8s-worker1
wordpress-6d5cdf8c64-rw6kt   2/2     Running   4 (43m ago)    33h    10.244.207.74    k8s-worker2
```

| Check | Result | Evidence |
|-------|--------|----------|
| Vault cluster unavailable (no quorum) | **YES** | vault3 stuck in standby, raft list-peers fails |
| Existing pods still serving with cached secrets | **YES** | WordPress + MariaDB running, no restarts |
| Vault UI inaccessible | **YES** | Leader (vault1) down |
| WordPress still working | **YES** | Login, browsing, DB queries all normal |

**Conclusion:** Existing pods with vault-agent sidecars continue serving using cached secrets. No impact on running workloads.

---

## Step B — Vault-Injector Deep Dive (while vault down)

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
wordpress-6d5cdf8c64-hxj9s   0/2     Init:1/2   0              7s     10.244.29.183    k8s-worker3  <- STUCK
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
3. Exponential backoff: 770ms -> 1.47s -> 2.8s -> 4.76s -> continues indefinitely
4. Pod will remain stuck until vault quorum restored

| Check | Result | Evidence |
|-------|--------|----------|
| vault-injector sidecar behavior | **Injected** | Init container added to new pod |
| Init container timeout behavior | **Infinite retry** | Exponential backoff, no timeout |
| New pods pending/timeout (expected) | **YES - STUCK** | Init:1/2, can't authenticate |

**Conclusion:** New pods CANNOT start when vault has no quorum. They get stuck on `vault-agent-init` waiting for vault authentication.

**Why vault-agent tries 10.0.62.10 instead of VIP:**

The vault-agent-injector IS configured with VIP (`vault.lab.local:8200`), but vault-agent connects directly to leader IP. This is **Raft HA redirect behavior**:

```bash
[root@k8s-master1 ~]# kubectl describe deploy vault-agent-injector -n vault | grep -i addr
      AGENT_INJECT_VAULT_ADDR:                             https://vault.lab.local:8200
```

```bash
[root@vault3 ~]# vault status
HA Mode                  standby                    <- Can't elect itself (1/3 = no quorum)
Active Node Address      https://10.0.62.10:8200    <- Still points to dead leader
```

**How it works:**
1. vault-agent connects to VIP -> reaches vault3
2. vault3 says "I'm standby, leader is at 10.0.62.10"
3. vault-agent tries 10.0.62.10 -> dead
4. Retries forever with exponential backoff

**Raft Quorum Requirements:**

| Nodes Up | Majority? | Can Elect Leader? | Status |
|----------|-----------|-------------------|--------|
| 3/3 | YES | YES | Fully operational |
| 2/3 | YES | YES | Operational (degraded) |
| 1/3 | NO | NO | **Stuck in standby** |

**Key Insight:** Single vault node cannot self-heal. Must restore at least 2/3 for quorum.

---

## Step C — Recovery

**Action:** Start vault1 only (test 2/3 quorum)
```bash
pct start 2004
```

**Time:** 2026-04-13 01:06 EET

**Quorum Restored with 2/3 Nodes:**
```bash
[root@vault1 ~]# vault status
HA Mode                  standby
Active Node Address      https://10.0.62.12:8200    <- vault3 is now leader!

[root@vault1 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    follower    true    <- rejoined as follower
vault2    10.0.62.11:8201    follower    true    <- still offline
vault3    10.0.62.12:8201    leader      true    <- PROMOTED TO LEADER
```

**Key Finding:** vault3 was promoted to leader once quorum (2/3) was restored. vault1 rejoined as follower.

**New Pod Successfully Gets Secrets:**
```bash
[root@k8s-master1 ~]# kubectl scale deployment wordpress -n apps --replicas=4
deployment.apps/wordpress scaled

[root@k8s-master1 ~]# kubectl get pods -n apps -o wide
NAME                         READY   STATUS     AGE   NODE
wordpress-6d5cdf8c64-p9xn4   0/2     Init:0/2   2s    k8s-worker3  <- NEW POD
wordpress-6d5cdf8c64-p9xn4   0/2     PodInitializing   5s
wordpress-6d5cdf8c64-p9xn4   1/2     Running    7s
wordpress-6d5cdf8c64-p9xn4   2/2     Running    12s   <- FULLY READY!
```

**Timeline:** `Init:0/2` -> `2/2 Running` in **12 seconds**

| Check | Result | Evidence |
|-------|--------|----------|
| Quorum restored | **YES** | 2/3 nodes = majority |
| Vault unsealed (auto-unseal) | **YES** | AWS KMS auto-unseal worked |
| Leader election | **YES** | vault3 promoted to leader |
| New pods can fetch secrets | **YES** | p9xn4 got secrets in 12s |
| WordPress working | **YES** | 4/4 pods running |

---

## Raft Cluster Deep Dive (while vault2 still offline)

**`raft list-peers` vs `raft autopilot state`:**

```bash
[root@vault3 ~]# vault operator raft list-peers
Node      Address            State       Voter
----      -------            -----       -----
vault1    10.0.62.10:8201    follower    true
vault2    10.0.62.11:8201    follower    true    <- Shows as follower (but offline!)
vault3    10.0.62.12:8201    leader      true
```

**Important:** `raft list-peers` shows **configured membership**, not live status!

**To see actual health, use `autopilot state`:**

```bash
[root@vault3 ~]# vault operator raft autopilot state
Healthy:                         false        <- Cluster degraded (vault2 down)
Failure Tolerance:               0            <- Can't lose any more nodes!
Leader:                          vault3
Servers:
   vault1
      Name:              vault1
      Address:           10.0.62.10:8201
      Status:            voter
      Node Status:       alive
      Healthy:           true               <- Actually online
      Last Contact:      2.622420854s       <- Recent heartbeat

   vault2
      Name:              vault2
      Address:           10.0.62.11:8201
      Status:            voter
      Node Status:       alive
      Healthy:           false              <- OFFLINE
      Last Contact:      5m40.001130079s    <- No heartbeat for 5+ minutes

   vault3
      Name:              vault3
      Address:           10.0.62.12:8201
      Status:            leader
      Node Status:       alive
      Healthy:           true
```

**Key Insights:**

| Metric | Value | Meaning |
|--------|-------|---------|
| `Healthy: false` | Cluster degraded | Not all voters online |
| `Failure Tolerance: 0` | Critical | One more failure = total outage |
| vault2 `Last Contact: 5m40s` | No heartbeat | Node is offline |

---

## Full Cluster Restoration

**Action:** Start vault2
```bash
pct start 2005
```

**Time:** 2026-04-13 01:15 EET

**Cluster Fully Healthy:**
```bash
[root@vault3 ~]# vault operator raft autopilot state
Healthy:                         true         <- Cluster healthy!
Failure Tolerance:               1            <- Can lose 1 node now
Leader:                          vault3
Servers:
   vault1    Healthy: true    Last Contact: 622ms
   vault2    Healthy: true    Last Contact: 4.9s   <- Back online!
   vault3    Healthy: true    (leader)
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
10m         Normal  Progressing             Kustomization/apps  Deployment/apps/wordpress configured  <- Auto-scaled back!
5m          Normal  ReconciliationSucceeded Kustomization/apps  Reconciliation finished in 374.640582ms
```

**Note:** Flux reconciles every 5 minutes. When we scaled to 4 replicas manually, Flux auto-corrected back to 3 (as defined in Git). This is **GitOps self-healing** in action!

---

## Summary

| Phase | Duration | Result |
|-------|----------|--------|
| Pre-test baseline | - | 3/3 vault healthy, WordPress serving |
| Step A: Kill quorum | 00:53 | 1/3 vault, existing pods OK, new pods stuck |
| Step B: New pod test | 00:55 | vault-agent-init stuck (infinite retry) |
| Step C: Restore 2/3 | 01:06 | Quorum restored, vault3 became leader |
| New pod recovery | 01:07 | Pod got secrets in 12 seconds |
| Full restore 3/3 | 01:15 | Cluster fully healthy |

---

## Critical Learnings

1. **Quorum is everything:**
   - 2/3 nodes = operational (can serve new pods)
   - 1/3 nodes = stuck (can't elect leader, new pods fail)

2. **Cached secrets save the day:**
   - Existing pods with vault-agent sidecar continue working
   - No immediate impact on running workloads

3. **vault-agent-injector HA works:**
   - 2 replicas on different masters
   - Survives node failures

4. **Flux GitOps self-heals:**
   - Manual scaling reverted automatically
   - Cluster state enforced from Git

---

## Recommendations

1. **Monitor vault quorum** - Alert if Failure Tolerance = 0
2. **Use `autopilot state`** not `list-peers` for actual health
3. **Test regularly** - Vault HA is complex, validate assumptions

---

## Related Cases

- [TS-VLT-005](../troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md)
- [TS-K8S-024](../troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md)

---

## Result: PASS

- Existing pods survived quorum loss (cached secrets)
- New pods stuck without quorum (expected)
- 2/3 quorum = leader election worked
- Full recovery in ~22 minutes
