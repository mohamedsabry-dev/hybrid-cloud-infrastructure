DR Test: Vault Quorum Loss + Injector Behavior
Date: 2026-04-13
Result: PASS
_____________________________________________________________________

[Info]
Domain: Vault / Raft HA / Kubernetes / Vault Agent Injection
Environment: DEV — 3-node Vault cluster (LXC), 2 vault-agent-injector
  replicas on masters
Triggered by: Need to understand what happens to the entire stack when
  Vault loses quorum — both existing and new workloads

_____________________________________________________________________

[Planned Scope]

Kill 2 of 3 Vault nodes (leader + follower), lose Raft quorum. Test
whether existing pods keep working with cached secrets, whether new
pods can start, and how the Raft redirect behavior affects vault-agent.

Components involved: Vault cluster (raft), vault-agent sidecars,
vault-agent-injector, WordPress pods, Flux GitOps

_____________________________________________________________________

[Pre-State]

Vault cluster healthy: vault1 (leader), vault2/vault3 (followers).
All unsealed via awskms. vault-agent-injector: 2 replicas on master1
and master3. WordPress: 3 pods serving.

_____________________________________________________________________

[Test 1.1 — Kill 2/3 Vault nodes (quorum loss)]

Action:
  ```
  pct stop 2004 && pct stop 2005    # vault1 (leader) + vault2
  ```

What happened:
  - vault3 (surviving): stuck in standby, still pointing to dead leader
    ```
    HA Mode: standby
    Active Node Address: https://10.0.62.10:8200    ← dead
    ```
  - `vault operator raft list-peers` failed — can't reach leader to query
  - Existing WordPress pods: ALL STILL RUNNING, serving traffic normally
  - WordPress login, browsing, DB queries — all working

Cascade:
  2/3 Vault nodes dead → no Raft quorum → can't elect leader →
  surviving node stuck in standby → Vault API unavailable →
  but existing pods don't care (cached secrets in sidecar)

What this tells me:
  Vault quorum loss doesn't affect running workloads. vault-agent
  sidecars have the secrets cached locally — they don't need to talk
  to Vault for ongoing operations. The blast radius is limited to
  anything that needs NEW secrets.

_____________________________________________________________________

[Test 1.2 — New pod creation during quorum loss]

Why this test: existing pods survived, but can new ones start?

Action:
  ```
  kubectl scale deployment wordpress -n apps --replicas=4
  ```

What happened:
  - New pod stuck at Init:1/2 — passed wait-for-mariadb, stuck on
    vault-agent-init
  - vault-agent-init error:
    ```
    dial tcp 10.0.62.10:8200: connect: no route to host
    backoff: 770ms → 1.47s → 2.8s → 4.76s → continues indefinitely
    ```
  - Pod stayed stuck until quorum restored

  Why it tries 10.0.62.10 (dead leader) instead of the VIP:
  1. vault-agent connects to VIP → reaches vault3
  2. vault3 says "I'm standby, leader is at 10.0.62.10"
  3. vault-agent follows the redirect → dead node
  4. Retries forever with exponential backoff

  This is Raft HA redirect behavior — vault3 can't serve because it's
  not leader, and it can't become leader because there's no quorum.

What this tells me:
  New pods CANNOT start during quorum loss. vault-agent-init blocks
  indefinitely. The Raft redirect makes it worse — even reaching a
  healthy node gets you redirected to the dead leader. Single surviving
  node is useless for new secret requests.

_____________________________________________________________________

[Test 1.3 — Restore quorum (start vault1 only)]

Why this test: do we need all 3 nodes back, or is 2/3 enough?

Action:
  ```
  pct start 2004    # vault1 only
  ```

What happened:
  - vault3 promoted itself to leader (2/3 = quorum)
  - vault1 rejoined as follower, auto-unsealed via AWS KMS
  - Scaled WordPress to 4 → new pod got secrets in 12 seconds

  ```
  vault operator raft list-peers
  vault1    follower    true    ← rejoined
  vault2    follower    true    ← still offline
  vault3    leader      true    ← promoted
  ```

  Important: `raft list-peers` shows CONFIGURED membership, not live
  status. vault2 shows as "follower" but it's offline. Use
  `vault operator raft autopilot state` for actual health:
  ```
  Healthy: false               ← cluster degraded
  Failure Tolerance: 0         ← can't lose another node
  vault2 Last Contact: 5m40s   ← no heartbeat
  ```

What this tells me:
  2/3 is enough for full functionality — leader election, secret
  serving, new pod creation. But Failure Tolerance drops to 0, meaning
  one more failure = total outage. Use `autopilot state` not
  `list-peers` for real health checks.

_____________________________________________________________________

[Recovery]

  ```
  pct start 2005    # vault2
  ```

  Cluster back to 3/3 healthy, Failure Tolerance: 1.
  Flux auto-reconciled WordPress back to 3 replicas (reverted the
  manual scale to 4).

_____________________________________________________________________

[Findings]

1. Quorum is everything. 2/3 = operational. 1/3 = stuck, can't self-heal.
   Single surviving node knows it's not leader but can't promote itself.

2. Existing pods survive quorum loss indefinitely. Cached secrets in
   vault-agent sidecar keep working. No impact on running workloads.

3. New pods CANNOT start during quorum loss. vault-agent-init blocks
   on authentication forever. The Raft redirect behavior makes it worse —
   healthy standby node redirects to dead leader.

4. `raft list-peers` lies about health. It shows configured membership,
   not live state. Use `autopilot state` for actual node health and
   failure tolerance.

5. Flux GitOps self-heals — manual scale changes get reverted to what's
   in Git on next reconciliation cycle (~5 min).

_____________________________________________________________________

[References]

- vault-aws-kms-credential-loss.md — single node credential loss (different scenario)
- troubleshooting/vault/5-vault-node-recovery-stale-raft-data.md (TS-VLT-005)
- troubleshooting/kubernetes/24-vault-cluster-resilience-2-node-quorum.md (TS-K8S-024)
