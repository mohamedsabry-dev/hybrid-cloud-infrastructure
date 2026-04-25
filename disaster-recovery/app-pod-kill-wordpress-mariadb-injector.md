DR Test: Application Pod Kill — WordPress, MariaDB, Vault Injector
Date: 2026-04-11
Result: PASS + FIX APPLIED (race condition found and mitigated)
_____________________________________________________________________

[Info]
Domain: Kubernetes / WordPress / MariaDB / Vault Agent Injection
Environment: DEV k8s-dev cluster | Proxmox
Triggered by: Need to verify pod-level resilience — what breaks when
  individual application components die, and what cascades

_____________________________________________________________________

[Planned Scope]

Kill application pods one by one while WordPress is actively serving
traffic (browsing + video upload running as baseline). Escalate from
single pod kills to simultaneous kills if something interesting shows up.

Components involved: WordPress (3 replicas), MariaDB (1 StatefulSet),
vault-agent-injector (1 replica on masters)

_____________________________________________________________________

[Pre-State]

All 6 nodes Ready (3 masters, 3 workers), v1.35.3.
Key pod distribution:

| Component            | Replicas | Nodes                      |
|----------------------|----------|----------------------------|
| wordpress            | 3        | worker1, worker2, worker3  |
| mariadb              | 1        | worker3                    |
| vault-agent-injector | 1        | master2                    |
| ingress-nginx        | 3        | worker1, worker3 (x2)      |
| coredns              | 2        | master1, master2           |

WordPress confirmed accessible, login working, traffic flowing
through multiple ingress pods (load balancing verified via source IPs).

_____________________________________________________________________

[Test 1.1 — Kill WordPress pod]

Action:
  ```
  kubectl delete pod -n apps wordpress-85b7f46448-hf785
  ```

What happened:
  - New pod created in 2s, fully ready (2/2) in 9s
  - Zero downtime — other 2 pods kept serving
  - All 3 browser tabs stayed logged in
  - Vault agent sidecar injected on new pod without issues

What this tells me:
  WordPress is correctly stateless. Sessions live in MariaDB, not in
  pod memory. Browser holds a session cookie, any pod can validate it
  against the shared database. Pods are disposable — state lives in the DB.

_____________________________________________________________________

[Test 1.2 — Kill MariaDB pod]

Why this test: WordPress survived pod kill because DB was up. What
  happens when the DB itself dies?

Action:
  ```
  kubectl delete pod -n database mariadb-0
  ```

What happened:
  - WordPress: "Error establishing a database connection" for ~5 seconds
  - MariaDB pod recreated by StatefulSet in 9s (2/2 Ready)
  - InnoDB crash recovery ran automatically — 73 pages recovered from
    checkpoint LSN 6301694
  - Vault-agent-init re-authenticated and injected DB creds in ~47ms
  - WordPress auto-recovered once MariaDB was reachable

  Shutdown sequence from logs:
  ```
  20:36:29 mysqld: Normal shutdown
  20:36:29 InnoDB: Starting shutdown, dumping buffer pool
  20:36:29 mysqld got signal 6 (pod terminated during shutdown)
  ```

  Boot sequence:
  ```
  20:36:34 InnoDB: Starting crash recovery from checkpoint
  20:36:34 InnoDB: 73 pages to recover
  20:36:35 mysqld: ready for connections (port 3306)
  ```

What this tells me:
  StatefulSet + PVC means MariaDB data survives pod death. InnoDB crash
  recovery handles the abrupt termination — buffer pool dump completed
  before SIGTERM, crash recovery picked up from checkpoint. The signal 6
  error is expected (fdatasync interrupted by forced termination, not a
  real crash).

  Vault secret injection on pod restart is fast (~47ms) — not a bottleneck.

_____________________________________________________________________

[Test 1.3 — Kill vault-agent-injector pod]

Why this test: vault-agent-injector is a mutating webhook — it injects
  the vault sidecar into pods at creation time. What if it's down when
  pods need to restart?

Action:
  ```
  kubectl delete pod -n vault -l app.kubernetes.io/name=vault-agent-injector
  ```

What happened:
  - Injector pod recovered in 22s, rescheduled master2 → master1
  - Running WordPress pods: no impact (they have cached secrets already)
  - No service disruption

What this tells me:
  Killing the injector is safe as long as no other pods are restarting
  at the same time. Existing pods keep their injected secrets. But this
  raised a question: what if injector dies at the same time as app pods?

_____________________________________________________________________

[Test 1.4 — Simultaneous kill: vault-injector + WordPress pods]

Why this test: the question from 1.3 — is there a race condition when
  the webhook is down during pod creation?

Action (sequential, few seconds apart):
  ```
  21:09:22 — deleted vault-agent-injector
  21:09:24 — deleted all WordPress pods
  ```

What happened:
  - Injector recovered before WordPress pods needed mutation
  - WordPress pods came up 2/2 (with sidecar) in 11s
  - Result: PASSED — sequential timing gave injector time to recover

Action (truly simultaneous):
  ```
  kubectl delete pod -n vault -l app.kubernetes.io/name=vault-agent-injector &
  kubectl delete pod -n apps -l app=wordpress
  ```

What happened:
  - WordPress pods came up **1/1 instead of 2/2** — NO vault sidecar
  - Mutating webhook was unavailable when pods were created
  - WordPress error: "Access denied for user 'wordpress'" — no secrets
    injected, pod used empty/wrong credentials
  - MariaDB rejected the connection

Cascade:
  Injector down → webhook unavailable → pods created without sidecar →
  no vault secrets → DB auth fails → WordPress down

What this tells me:
  **Race condition confirmed.** If vault-agent-injector and app pods
  restart simultaneously, the webhook gap means pods start without
  secrets. This isn't just theoretical — a master + worker crashing
  at the same time (e.g., same Proxmox host) would trigger this.

_____________________________________________________________________

[Test 1.5 — Fix and validate]

Fix applied:
  Increased vault-agent-injector to 2 replicas with anti-affinity
  across masters:
  ```yaml
  injector:
    replicas: 2
    affinity:
      podAntiAffinity:
        requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app.kubernetes.io/name: vault-agent-injector
            topologyKey: kubernetes.io/hostname
  ```
  Applied to both dev and prod helm releases.

Pre-test — 2 injectors running on separate masters:
  ```
  vault-agent-injector-...-5r2jd   1/1  Running  k8s-master1
  vault-agent-injector-...-svckt   1/1  Running  k8s-master3
  ```

Action (same simultaneous kill):
  ```
  kubectl delete pod -n vault vault-agent-injector-...-5r2jd &
  kubectl delete pod -n apps -l app=wordpress
  ```

What happened:
  - Injector on master1: killed → replacement creating
  - Injector on master3: **still running** → served webhook
  - WordPress pods: came up **2/2** (with sidecar)
  - Secrets injected, DB connection worked, zero downtime

Before vs After:
  | Scenario              | 1 replica           | 2 replicas          |
  |-----------------------|---------------------|---------------------|
  | Simultaneous restart  | Pods start 1/1      | Pods start 2/2      |
  | DB connection         | FAILED              | SUCCESS             |
  | Webhook availability  | ~3s gap             | Zero gap            |

Race condition: **MITIGATED**

_____________________________________________________________________

[Recovery]

No recovery needed — fix was applied inline during testing.
Cluster left in improved state (2 injector replicas).

_____________________________________________________________________

[Findings]

1. WordPress is correctly stateless. Sessions in DB, pods disposable.
   Single pod kill = zero downtime with 3 replicas.

2. MariaDB StatefulSet + PVC + InnoDB crash recovery = data survives
   pod death. 5s app downtime during restart, auto-recovered.

3. Vault secret injection is fast (~47ms) and not a bottleneck for
   pod startup. The bottleneck is vault sidecar readiness (~7s after
   init containers complete).

4. **Race condition between vault-agent-injector and app pod restarts.**
   Single injector replica creates a webhook gap during restart. Pods
   created during the gap start without sidecar → no secrets → auth
   failure. Fixed with 2 replicas + anti-affinity across masters.

5. Loki doesn't scrape vault namespace — discovered during testing.
   kubectl logs works but Grafana/Loki returns nothing for vault pods.

_____________________________________________________________________

[References]

- kubernetes/dev/deployments/infrastructure/vault/helm-release.yaml — injector fix
- kubernetes/prod/deployments/infrastructure/vault/helm-release.yaml — same fix
- troubleshooting/kubernetes/22-worker-node-failure-cascading-pod-failures.md — related
