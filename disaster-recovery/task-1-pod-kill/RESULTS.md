# Task 1: Single Pod Kill — Results

**Test Date:** 2026-04-11
**Baseline:** WordPress browsing + video upload running throughout all scenarios.

---

## Contents

```
Task 1 Results
├── Pre-Test Baseline
├── Scenario 1.1 — Single Pod Kill
│   ├── WordPress Pod (DONE)
│   ├── MariaDB Pod (DONE)
│   ├── vault-agent-injector Pod (DONE)
│   ├── Race Condition Test (DONE + FIX APPLIED)
│   ├── ingress-nginx Pod (TODO)
│   ├── flux Pod (TODO)
│   └── prometheus Pod (TODO)
├── Post-Test Verification
└── Summary
```

**Other scenarios moved to separate tasks:**
- 1.2-1.4 → [task-1a-pod-scale](../task-1a-pod-scale/PLAN.md)
- 1.5-1.8 → [task-1b-worker-kill](../task-1b-worker-kill/PLAN.md)
- 1.9-1.14 → [task-1c-master-kill](../task-1c-master-kill/PLAN.md)
- 1.15 → [task-1d-auto-recovery](../task-1d-auto-recovery/PLAN.md)

---

## Pre-Test Baseline

**Date/Time:** 2026-04-11 20:06 EET

**Cluster Nodes:**
```
NAME                    STATUS   ROLES           AGE   VERSION   INTERNAL-IP
k8s-master1.lab.local   Ready    control-plane   15d   v1.35.3   10.0.51.10
k8s-master2.lab.local   Ready    control-plane   15d   v1.35.3   10.0.51.11
k8s-master3.lab.local   Ready    control-plane   15d   v1.35.3   10.0.51.12
k8s-worker1.lab.local   Ready    <none>          15d   v1.35.3   10.0.54.10
k8s-worker2.lab.local   Ready    <none>          15d   v1.35.3   10.0.54.11
k8s-worker3.lab.local   Ready    <none>          15d   v1.35.3   10.0.54.12
```

**Critical Pods Distribution:**
| Component | Replicas | Nodes |
|-----------|----------|-------|
| wordpress | 3 | worker1, worker2, worker3 |
| mariadb | 1 | worker3 |
| ingress-nginx | 3 | worker1, worker3 (x2) |
| flux controllers | 4 | worker1 |
| vault-agent-injector | 1 | master2 |
| prometheus | 1 | worker1 |
| grafana | 1 | worker3 |
| loki | 1 | worker3 |
| coredns | 2 | master1, master2 |
| etcd | 3 | master1, master2, master3 |

**WordPress Accessibility:**
- [x] External access confirmed
- [x] Login functionality working

**Pre-Test Log Evidence (20:07 EET):**
```
# Traffic flowing through multiple ingress pods (load balancing confirmed)
# Source IPs show requests hitting different backend pods

2026-04-11 20:07:52 10.244.29.128 - POST /wp-admin/admin-ajax.php 200
2026-04-11 20:07:51 10.0.64.11   - GET  /wp-admin/ 200
2026-04-11 20:07:50 10.244.62.0  - GET  /wp-admin/ 200
2026-04-11 20:07:49 10.244.29.128 - POST /wp-admin/admin-ajax.php 200
2026-04-11 20:07:48 10.0.64.11   - GET  /wp-admin/ 200
2026-04-11 20:07:47 10.244.62.0  - POST /wp-login.php 302 (redirect after login)

# Kube-probes healthy on multiple workers
2026-04-11 20:07:50 10.0.64.11 - GET /wp-includes/images/blank.gif 200 "kube-probe/1.35"
2026-04-11 20:07:49 10.0.64.10 - GET /wp-includes/images/blank.gif 200 "kube-probe/1.35"
2026-04-11 20:07:48 10.0.64.11 - GET /wp-includes/images/blank.gif 200 "kube-probe/1.35"
```

**Confirmed working:**
- [x] Ingress routing (requests reaching WordPress pods)
- [x] Load balancing (traffic distributed across pods: 10.244.29.128, 10.244.62.0)
- [x] Multiple worker nodes serving (10.0.64.10, 10.0.64.11)
- [x] Database connectivity (wp-login.php 302 = successful auth against MariaDB)
- [x] Health probes passing (kube-probe/1.35 getting 200s)

---

## Scenario 1.1 — Single Pod Kill

**Status:** IN PROGRESS

### Test: WordPress Pod

**Action:**
```bash
date && kubectl delete pod -n apps wordpress-85b7f46448-hf785
# Sat Apr 11 08:10:05 PM EET 2026
```

**Recovery Timeline:**
```
20:10:05 - Pod deleted
20:10:07 - New pod wordpress-85b7f46448-6pkmd created (PodInitializing)
20:10:08 - 1/2 Running (wordpress container ready)
20:10:14 - 2/2 Running (vault-agent sidecar ready)
```

**Recovery Time:** ~9 seconds to full ready state

**Service Availability:**
- [x] Zero downtime — other 2 pods continued serving
- [x] Existing sessions NOT interrupted (3 browser tabs stayed logged in)
- [x] Load balancing continued across remaining pods

**Post-Recovery Logs (20:11):**
```
# Traffic flowing normally, requests served by multiple pods
20:11:46 10.245.207.64 - GET /wp-json/wp/v2/users/me 200
20:11:46 10.245.62.0   - GET /wp-admin/profile.php 200
20:11:44 10.245.207.64 - POST /wp-admin/admin-ajax.php 200
20:11:43 10.245.62.0   - GET /wp-admin/ 200

# Kube-probes healthy on all 3 workers
20:11:48 10.0.54.11 - kube-probe/1.35 200
20:11:46 10.0.54.12 - kube-probe/1.35 200
20:11:45 10.0.54.10 - kube-probe/1.35 200
```

**Vault Agent Injection:**
```
20:10:07 ==> Vault Agent started! Log data will stream in below:
20:10:07 ==> Note: Vault Agent version does not match Vault server version.
             Vault Agent version: 1.21.2, Vault server version: 1.21.4
```

**Result:** PASS — Pod recreated in 9s, zero service interruption

**Key Insight — Sessions Remained Logged In:**

Observed: All 3 browser tabs stayed logged in despite the pod being killed.

Explanation: WordPress uses **stateless architecture** with shared session storage:
- Sessions stored in MariaDB, NOT in pod memory
- Browser holds session cookie (token)
- Any WordPress pod can validate the token against the shared database
- Pods are disposable — state lives in the database

This confirms the application is correctly designed for pod failures.

**Log Collection Methods Used:**

```bash
# CLI: Direct pod logs (real-time)
kubectl logs -n apps -l app=wordpress -f --tail=50
```

Loki/Grafana: Logs queried via Grafana web UI → Explore → Loki datasource
- Query: `{namespace="apps", app="wordpress"}`
- Used for historical log evidence in this test

**NOTE:** Discovered that Loki/promtail does NOT scrape `vault` namespace logs.
- kubectl logs works, but Grafana/Loki returns "No logs found"
- Will create troubleshooting doc: [TS-K8S-025](../../troubleshooting/kubernetes/25-promtail-vault-namespace-logs.md)
- TODO: Update promtail config to include vault namespace

**Understanding Log Timestamps (Loki vs Application):**

```
2026-04-11 20:17:53.303 10.0.54.11 - - [11/Apr/2026:18:17:53 +0000] "GET /wp-includes/images/blank.gif"
         ↑                                        ↑
    Loki timestamp                     Application timestamp
    (local time EET)                   (UTC +0000)
```

Logs contain **two timestamps**:
1. **Loki ingestion time** (prefix): Local time (EET = UTC+2) — added by promtail when log is collected
2. **Application log time** (in brackets): UTC (+0000) — written by nginx/WordPress

Both WordPress and MariaDB log in UTC (container best practice). Loki adds local timestamp prefix.
When viewing via `kubectl logs`, you see raw application time (UTC only).

**Pre-Test WordPress Logs (20:17 EET / 18:17 UTC):**
```
# Kube-probes healthy on all workers
2026-04-11 20:17:53 [18:17:53 +0000] 10.0.54.11 - kube-probe/1.35 200
2026-04-11 20:17:52 [18:17:52 +0000] 10.0.54.12 - kube-probe/1.35 200
2026-04-11 20:17:49 [18:17:49 +0000] 10.0.54.10 - kube-probe/1.35 200
2026-04-11 20:17:48 [18:17:48 +0000] 10.0.54.11 - kube-probe/1.35 200
2026-04-11 20:17:46 [18:17:46 +0000] 10.0.54.12 - kube-probe/1.35 200

# User traffic active
2026-04-11 20:17:50 [18:17:50 +0000] 10.245.62.0 - POST /wp-admin/admin-ajax.php 200
```

### Test: MariaDB Pod

**Pre-Test State (20:23 EET / 18:23 UTC):**
```bash
kubectl get pods -n database -l app=mariadb
# NAME        READY   STATUS    RESTARTS   AGE
# mariadb-0   2/2     Running   0          9h
```

**Pre-Test Logs (normal health check activity):**
```
# These "Aborted connection...unauthenticated" are NORMAL
# They are liveness/readiness probes testing DB accepts connections
2026-04-11 18:23:07 [Warning] Aborted connection to db: 'unconnected'
                              user: 'unauthenticated' host: '10.0.54.12'
# Source 10.0.54.12 = worker3 (where MariaDB runs) = local health probes
```

**Note:** MariaDB logs in UTC (container best practice). Local time EET = UTC+2.

**Action:**
```bash
date && kubectl delete pod -n database mariadb-0
# ~20:36:29 EET
```

**Shutdown Sequence (from logs):**
```
20:36:29.636 [Note] mysqld: Normal shutdown
20:36:29.637 [Note] InnoDB: FTS optimize thread exiting
20:36:29.641 ==> Vault Agent shutdown triggered
20:36:29.693 [Note] InnoDB: Starting shutdown...
20:36:29.696 [Note] InnoDB: Dumping buffer pool(s)
20:36:29.704 [Note] InnoDB: Buffer pool(s) dump completed
20:36:29.895 [ERROR] mysqld got signal 6 (pod terminated during shutdown)
```

**WordPress Impact:**
```
Error: "Error establishing a database connection"
       mysqli_real_connect(): (HY000/2002): Connection refused
       Host: mariadb-svc.database.svc.cluster.local
```

**Downtime Duration:** ~5 seconds (user observed)

**Recovery Logs (20:36:47-49):**
```
20:36:47 10.245.29.128 - GET /wp-admin/index.php 200 ← WordPress recovered
20:36:48 10.245.207.64 - GET /wp-admin/index.php 200
20:36:48 10.245.62.0   - GET /wp-json/wp/v2/users/me 200
20:36:49 10.245.207.64 - GET /wp-admin/index.php 200
# All 3 WordPress pods serving traffic again
```

**Pod Recovery Timeline:**
```
20:36:29 - Pod deleted
+0s      - Init:0/1 (vault-agent-init starting)
+2s      - PodInitializing (init container completed)
+3s      - 1/2 Running (MariaDB container ready)
+9s      - 2/2 Running (vault-agent sidecar ready)
```

**MariaDB Boot Sequence (from Loki):**
```
20:36:34.441 Starting MariaDB 10.11.11-MariaDB as process 1
20:36:34.476 InnoDB: Using crc32 + pclmulqdq instructions
20:36:34.478 InnoDB: Initializing buffer pool, total size = 128.000MiB
20:36:34.616 InnoDB: Completed initialization of buffer pool
20:36:34.808 InnoDB: Starting crash recovery from checkpoint LSN=6301694
20:36:34.829 InnoDB: End of log at LSN=7350131
20:36:34.863 InnoDB: To recover: 73 pages
20:36:35.023 InnoDB: 128 rollback segments are active
20:36:35.031 InnoDB: log sequence number 7350131; transaction id 2121
20:36:35.051 Server socket created on IP: '0.0.0.0' and '::'
20:36:35.155 InnoDB: Buffer pool(s) load completed
20:36:35.251 mysqld: ready for connections (port 3306)
```

**Key Insight:** InnoDB crash recovery ran automatically (73 pages recovered from checkpoint).
This confirms data integrity preserved despite forced termination.

**CLI Commands to Get These Logs:**
```bash
# MariaDB container logs (startup)
kubectl logs -n database mariadb-0 -c mariadb | head -100

# Vault-agent-init (init container)
kubectl logs -n database mariadb-0 -c vault-agent-init

# Vault-agent sidecar
kubectl logs -n database mariadb-0 -c vault-agent | head -20

# All containers combined
kubectl logs -n database mariadb-0 --all-containers=true | head -150
```

**Vault-Agent-Init Sequence (from kubectl logs):**
```
18:36:33.390 [INFO]  agent.sink.file: creating file sink
18:36:33.391 [INFO]  agent.auth.handler: starting auth handler
18:36:33.391 [INFO]  agent.auth.handler: authenticating
18:36:33.425 [INFO]  agent.auth.handler: authentication successful, sending token to sinks
18:36:33.425 [INFO]  agent.sink.file: token written: path=/home/vault/.vault-token
18:36:33.434 [INFO]  agent.auth.handler: renewed auth token
18:36:33.437 [INFO]  agent: (runner) rendered "(dynamic)" => "/vault/secrets/db-creds"
18:36:33.437 [INFO]  agent.template.server: template server stopped
```

**Key Insight:** Vault auth + secret injection completed in **~47ms** (33.390 → 33.437).
- Authenticated with Vault cluster
- Token written to sink
- DB credentials rendered to `/vault/secrets/db-creds`
- Init container exited, MariaDB started with secrets available

**Result:**
- Pod restart time: **9 seconds** (delete → 2/2 Running)
- WordPress downtime: **~5 seconds** (recovered when MariaDB reached 1/2 Running)
- InnoDB graceful shutdown: buffer pool dump completed before termination
- Signal 6 error: Expected during forced termination (fdatasync interrupted)
- **PASS** — StatefulSet recreated pod, PVC retained data, WordPress auto-recovered

### Test: vault-agent-injector Pod

**Pre-Test State:**
```
vault-agent-injector-58d46d9c9f-lrpjm   1/1   Running   6h
Node: k8s-master2.lab.local
Labels: app.kubernetes.io/name=vault-agent-injector, component=webhook
```

**Action:**
```bash
date && kubectl delete pod -n vault -l app.kubernetes.io/name=vault-agent-injector
# Sat Apr 11 08:56:43 PM EET 2026
```

**Pod Recovery Timeline:**
```
20:56:43 - Pod deleted
+1s      - ContainerCreating
+17s     - Running (0/1)
+22s     - Running (1/1) Ready
```

**Recovery Time:** 22 seconds

**New Pod Startup Logs:**
```
18:56:59.926 [INFO] handler.auto-tls: Generated CA
18:56:59.929 [INFO] handler: Starting handler..
                    Listening on ":8080"...
18:57:00.027 [INFO] handler.certwatcher: Updated certificate bundle received
```

**New Pod Location:**
```
vault-agent-injector-58d46d9c9f-dtm6p   1/1   Running   k8s-master1.lab.local
# Rescheduled from master2 → master1
```

**Impact:** None — WordPress continued serving (existing pods have cached secrets)

**Result:** PASS — Deployment recreated pod in 22s, no service impact

**Important Insight — Potential Race Condition:**

If WordPress pods restart AT THE SAME TIME as vault-agent-injector is down:
- WordPress pod needs vault-agent sidecar injection via mutating webhook
- If injector is down, what happens?
  - Does pod wait indefinitely?
  - Does it start WITHOUT sidecar and fail to authenticate to MariaDB?

This is a potential cascading failure scenario. Related to:
[TS-K8S-022 — Preventing Vault Injection Race Condition](../../troubleshooting/kubernetes/22-worker-node-failure-cascading-pod-failures.md#preventing-vault-injection-race-condition)

**Mitigation already implemented:**
- vault-agent-injector moved to master nodes (more stable)
- Confirmed: Pod rescheduled master2 → master1 during this test

### Race Condition Test — Vault Injector + WordPress Simultaneous Delete

**Test 1: Sequential delete (few seconds apart) — 21:09:22**
```
21:09:22 - Vault injector deleted
21:09:24 - WordPress pods deleted (injector already recovering)
21:09:24 - WordPress pods: Init:1/2 (vault-agent-init running)
21:09:26 - WordPress pods: 1/2 Running (vault-agent sidecar starting)
21:09:33 - WordPress pods: 2/2 Running ✓
```
**Result:** SUCCESS — Injector recovered before WordPress needed mutation

**Test 2: Simultaneous delete — 21:09:55**
```bash
echo "=== START: $(date) ===" && \
kubectl delete pod -n vault -l app.kubernetes.io/name=vault-agent-injector & \
kubectl delete pod -n apps -l app=wordpress && \
echo "=== DELETED: $(date) ==="
# START: Sat Apr 11 09:09:55 PM EET 2026
# DELETED: Sat Apr 11 09:09:57 PM EET 2026
```

**Timeline:**
```
21:09:55 - Both deleted simultaneously
21:09:56 - vault-agent-injector: Error state
21:09:56 - WordPress pods: Init:0/1 (NO vault-agent-init!)
21:09:58 - WordPress pods: PodInitializing (0/1 containers)
21:10:00 - WordPress pods: Running 0/1 (only wordpress, NO vault-agent!)
21:10:06 - WordPress pods: Running 1/1 (ready but MISSING sidecar!)
```

**CRITICAL OBSERVATION:**
- Pods show `1/1` Ready instead of `2/2`
- This means vault-agent sidecar was NOT injected
- Mutating webhook was unavailable when pods were created

**WordPress Error:**
```
Warning: mysqli_real_connect(): (HY000/1045):
Access denied for user 'wordpress'@'10.245.29.147' (using password: YES)

Error establishing a database connection
```

**Root Cause:**
- WordPress pod started WITHOUT vault-agent sidecar
- No secrets injected from Vault
- WordPress used incorrect/empty credentials
- MariaDB rejected the connection

**CONFIRMED: Race condition exists when vault-agent-injector and app pods restart simultaneously.**

**Mitigation (already implemented):**
- vault-agent-injector runs on master nodes (more stable)
- But if masters restart during worker pod restarts, issue can still occur

**Additional Mitigations to Consider:**
1. **Increase injector replicas (`replicas: 2`)** ← RECOMMENDED
2. Add PodDisruptionBudget for injector
3. Add readiness gate or init container dependency on injector availability

**Analysis: Why 2 replicas is necessary**

Current state (1 replica on masters) is NOT sufficient:
- Scenario: 1 master + 1 worker crash simultaneously (e.g., VMs on same Proxmox host)
- Worker pods need to reschedule immediately
- Injector on crashed master needs time to migrate to another master
- Gap exists where webhook is unavailable → pods start without sidecar

Solution: 2 replicas with anti-affinity across masters:
```yaml
# vault HelmRelease values
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

This ensures:
- Replica A on master1, Replica B on master2
- If master1 crashes → Replica B still serving immediately
- Zero gap in webhook availability
- Worker pods always get proper sidecar injection

**FIX APPLIED:**
- `kubernetes/dev/deployments/infrastructure/vault/helm-release.yaml`
- `kubernetes/prod/deployments/infrastructure/vault/helm-release.yaml`

Added `replicas: 2` with `podAntiAffinity` to spread across masters.

### Test: ingress-nginx Pod

**Action:**
```bash
# TODO
```

**Result:**
- Pod restart time:
- Traffic handling during restart:

### Test: flux Pod

**Action:**
```bash
# TODO
```

**Result:**
- Pod restart time:
- Reconciliation status:

### Test: prometheus Pod

**Action:**
```bash
# TODO
```

**Result:**
- Pod restart time:
- Scraping recovery:

### Checklist 1.1
- [ ] All pods restarted automatically
- [ ] Services remained available (or recovered quickly)
- [ ] No data loss observed

---

## Post-Test Verification

**Final Cluster State:**
```bash
# TODO
kubectl get nodes
kubectl get pods -A
```

**Final Checks:**
- [ ] WordPress accessible (browse + upload)
- [ ] DB integrity verified
- [ ] etcd healthy
- [ ] Flux reconciliation successful
- [ ] Vault unsealed
- [ ] All pods running

---

## Summary

| Component | Status | Recovery Time | Key Finding |
|-----------|--------|---------------|-------------|
| WordPress | PASS | 9s | Zero downtime, sessions preserved |
| MariaDB | PASS | 9s (5s app downtime) | InnoDB crash recovery worked |
| vault-agent-injector | PASS + FIX | 22s | Race condition found → 2 replicas fix applied |
| ingress-nginx | TODO | - | - |
| flux | TODO | - | - |
| prometheus | TODO | - | - |

**Key Findings:**
1. WordPress stateless architecture works — sessions survive pod kills
2. MariaDB InnoDB crash recovery preserves data integrity
3. Vault auth + secret injection completes in ~47ms
4. **CRITICAL:** Race condition when injector + app pods restart simultaneously → FIX APPLIED (2 replicas)
5. Loki doesn't scrape vault namespace → TODO: TS-K8S-025
