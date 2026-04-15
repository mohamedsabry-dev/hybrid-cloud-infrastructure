# TS-K8S-033 | 2026-04-15 | IN PROGRESS

## 1. Context
- **System:** Vault Agent Sidecar / CoreDNS / FreeIPA DNS
- **Environment:** DEV (lab.local)
- **Related Components:** Vault Agent, vault-agent-init, CoreDNS, WordPress, MariaDB, Grafana, Remediation
- **Discovery:** **Discovered during IPA Domain Down DR Test (Part 2)**
- **Related Cases:**
  - TS-IDN-009 — Ansible SSSD KnownHostsCommand timeout
  - TS-K8S-034 — WordPress external DNS slowness

---

## 2. Issue

Two related problems observed when FreeIPA DNS is unavailable:

### Issue A: Running Vault Agent Sidecars Crash (~10 minutes)
Vault Agent sidecars in existing pods crash after approximately 10 minutes of DNS failure due to retry exhaustion.

### Issue B: New Pods Cannot Start (Critical)
New pods with Vault Agent init containers cannot start at all because `vault-agent-init` cannot authenticate to Vault.

---

## 3. Evidence - Issue A: Vault Agent Crash

### IPA Stop Command
```bash
[root@ansible dev]#  ssh root@freeipa 'ipactl stop'
ipa: INFO: The ipactl command was successful
Stopping ipa-dnskeysyncd Service
Stopping ipa-otpd Service
Stopping pki-tomcatd Service
Stopping ipa-custodia Service
Stopping httpd Service
Stopping named Service
Stopping kadmin Service
Stopping krb5kdc Service
Stopping Directory Service
[root@ansible dev]# date
Wed Apr 15 10:00:49 PM EET 2026
```

### Immediate Vault Agent Errors (T+0 to T+2 minutes)
```bash
[root@k8s-master1 k8s_admin]# kubectl logs -l app=wordpress -n apps -c vault-agent
2026-04-15T19:47:07.403Z [INFO]  agent.auth.handler: renewed auth token
2026-04-15T20:01:33.700Z [ERROR] agent: (runner) sending server error back to caller
2026-04-15T20:01:33.700Z [ERROR] agent.template.server: template server: could not extract error response
2026-04-15T20:01:33.700Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config): vault.read(secret/data/wordpress/config): Get "https://vault.lab.local:8200/v1/secret/data/wordpress/config": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving (retry attempt 1 after "250ms")
2026-04-15T20:01:58.328Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config): vault.read(secret/data/wordpress/config): Get "https://vault.lab.local:8200/v1/secret/data/wordpress/config": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving (retry attempt 2 after "500ms")
2026-04-15T20:01:58.328Z [ERROR] agent: (runner) sending server error back to caller
2026-04-15T20:01:58.328Z [ERROR] agent.template.server: template server: could not extract error response
2026-04-15T20:02:20.006Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config): vault.read(secret/data/wordpress/config): Get "https://vault.lab.local:8200/v1/secret/data/wordpress/config": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving (retry attempt 3 after "1s")
```

### Exponential Backoff Pattern (T+5 to T+10 minutes)
```bash
[root@k8s-master1 k8s_admin]# kubectl logs -l app=wordpress -n apps -c vault-agent
2026-04-15T20:05:35.159Z [ERROR] agent.template.server: template server: could not extract error response
2026-04-15T20:07:00.639Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config): ... (retry attempt 10 after "1m0s")
2026-04-15T20:07:00.639Z [ERROR] agent: (runner) sending server error back to caller
2026-04-15T20:08:18.875Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config): ... (retry attempt 11 after "1m0s")
2026-04-15T20:08:18.875Z [ERROR] agent: (runner) sending server error back to caller
2026-04-15T20:09:43.342Z [WARN]  agent: (view) vault.read(secret/data/wordpress/config): ... (retry attempt 12 after "1m0s")
```

### Retry Backoff Timeline
```
┌─────────┬──────────────────┬──────────────┐
│ Attempt │ Backoff Duration │ Elapsed Time │
├─────────┼──────────────────┼──────────────┤
│ 1       │ 250ms            │ ~0s          │
│ 2       │ 500ms            │ ~25s         │
│ 3       │ 1s               │ ~47s         │
│ ...     │ ...              │ ...          │
│ 7       │ 16s              │ ~5min        │
│ 8       │ 32s              │ ~6min        │
│ 9-12    │ 1m0s (max)       │ ~10min       │
└─────────┴──────────────────┴──────────────┘
```

### Vault Agent Exit Code Analysis
```bash
[root@k8s-master1 k8s_admin]# kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}{"\t"}restarts: {.restartCount}{"\t"}reason: {.lastState.terminated.reason}{"\n"}{end}{"\n"}{end}' | grep -B1 vault-agent
apps	wordpress-56bf4b697d-87tvx
  vault-agent	restarts: 1	reason: Error
--
apps	wordpress-56bf4b697d-8k8jc
  vault-agent	restarts: 1	reason: Error
--
apps	wordpress-56bf4b697d-vxc69
  vault-agent	restarts: 1	reason: Error
--
  mariadb	restarts: 3	reason: Unknown
  vault-agent	restarts: 5	reason: Error
--
  grafana-sc-datasources	restarts: 4	reason: Unknown
  vault-agent	restarts: 5	reason: Error
--
  grafana-sc-datasources	restarts: 3	reason: Unknown
  vault-agent	restarts: 5	reason: Error
--
  grafana-sc-datasources	restarts: 3	reason: Unknown
  vault-agent	restarts: 5	reason: Error
--
  remediation	restarts: 4	reason: Unknown
  vault-agent	restarts: 5	reason: Error
```

### Vault Agent Crash Timestamps (Exit Code 1)
```bash
[root@k8s-master1 k8s_admin]# for pod in mariadb-0 wordpress-56bf4b697d-87tvx wordpress-56bf4b697d-8k8jc wordpress-56bf4b697d-vxc69; do
  ns=$(kubectl get pods -A | grep $pod | awk '{print $1}')
  echo "=== $pod ($ns) ==="
  kubectl get pod $pod -n $ns -o jsonpath='{range .status.containerStatuses[*]}{.name}: exitCode={.lastState.terminated.exitCode} finished={.lastState.terminated.finishedAt}{"\n"}{end}'
  echo ""
done

=== mariadb-0 (database) ===
mariadb: exitCode=255 finished=2026-04-15T17:44:33Z
vault-agent: exitCode=1 finished=2026-04-15T20:12:04Z

=== wordpress-56bf4b697d-87tvx (apps) ===
vault-agent: exitCode=1 finished=2026-04-15T20:11:07Z
wordpress: exitCode= finished=

=== wordpress-56bf4b697d-8k8jc (apps) ===
vault-agent: exitCode=1 finished=2026-04-15T20:14:52Z
wordpress: exitCode= finished=

=== wordpress-56bf4b697d-vxc69 (apps) ===
vault-agent: exitCode=1 finished=2026-04-15T20:15:54Z
wordpress: exitCode= finished=
```

### Grafana Pod Vault Agent Crashes
```bash
[root@k8s-master1 k8s_admin]# kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{range .items[*]}Pod: {.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}: exitCode={.lastState.terminated.exitCode} finished={.lastState.terminated.finishedAt}{"\n"}{end}{"\n"}{end}'

Pod: kube-prometheus-stack-grafana-5f6554dcf5-lrvqq
  grafana: exitCode=255 finished=2026-04-15T17:44:33Z
  grafana-sc-dashboard: exitCode=255 finished=2026-04-15T17:44:33Z
  grafana-sc-datasources: exitCode=255 finished=2026-04-15T17:44:33Z
  vault-agent: exitCode=1 finished=2026-04-15T20:12:16Z

Pod: kube-prometheus-stack-grafana-5f6554dcf5-mqbk5
  grafana: exitCode=255 finished=2026-04-15T17:44:23Z
  grafana-sc-dashboard: exitCode=255 finished=2026-04-15T17:44:23Z
  grafana-sc-datasources: exitCode=255 finished=2026-04-15T17:44:23Z
  vault-agent: exitCode=1 finished=2026-04-15T20:13:03Z

Pod: kube-prometheus-stack-grafana-5f6554dcf5-pbbn6
  grafana: exitCode=255 finished=2026-04-15T17:44:31Z
  grafana-sc-dashboard: exitCode=255 finished=2026-04-15T17:44:31Z
  grafana-sc-datasources: exitCode=255 finished=2026-04-15T17:44:31Z
  vault-agent: exitCode=1 finished=2026-04-15T20:15:26Z
```

### Remediation Pod Vault Agent Crash
```bash
[root@k8s-master1 k8s_admin]# kubectl get pod -n remediation -o jsonpath='{range .items[*]}Pod: {.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}: exitCode={.lastState.terminated.exitCode} finished={.lastState.terminated.finishedAt}{"\n"}{end}{"\n"}{end}'

Pod: remediation-56bdddfcd7-t8fvv
  remediation: exitCode=255 finished=2026-04-15T17:42:46Z
  vault-agent: exitCode=1 finished=2026-04-15T20:14:25Z
```

---

## 4. Evidence - Issue B: New Pods Cannot Start

### Rollout Restart Command (IPA Still Down)
```bash
[root@k8s-master1 k8s_admin]# kubectl rollout restart deployment wordpress -n apps
deployment.apps/wordpress restarted
```

### New Pod Stuck in Init State
```bash
[k8s_admin@k8s-master1 ~]$ kubectl get pods -n apps -w &
NAME                         READY   STATUS    RESTARTS      AGE
wordpress-56bf4b697d-87tvx   2/2     Running   1 (35m ago)   59m
wordpress-56bf4b697d-8k8jc   2/2     Running   1 (31m ago)   59m
wordpress-56bf4b697d-vxc69   2/2     Running   1 (30m ago)   59m
wordpress-7b8c7d879-xbzfr    0/2     Pending   0             0s
wordpress-7b8c7d879-xbzfr    0/2     Pending   0             1s
wordpress-7b8c7d879-xbzfr    0/2     Init:0/2   0             1s
wordpress-7b8c7d879-xbzfr    0/2     Init:0/2   0             2s
wordpress-7b8c7d879-xbzfr    0/2     Init:0/2   0             2s
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0             6s
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0             8s
```

### vault-agent-init Logs (New Pod)
```bash
[root@k8s-master1 k8s_admin]# kubectl logs -n apps wordpress-7b8c7d879-xbzfr -c vault-agent-init
==> Vault Agent started! Log data will stream in below:

==> Vault Agent configuration:

           Api Address 1: http://bufconn
                     Cgo: disabled
               Log Level: info
                 Version: Vault v1.21.2, built 2026-01-06T08:33:05Z
             Version Sha: 781ba452d731fe2d59ccbc1b37ca7c5a18edb998

2026-04-15T20:46:37.406Z [INFO]  agent.sink.file: creating file sink
2026-04-15T20:46:37.406Z [INFO]  agent.sink.file: file sink configured: path=/home/vault/.vault-token mode=-rw-r----- owner=100 group=1000
2026-04-15T20:46:37.407Z [INFO]  agent.exec.server: starting exec server
2026-04-15T20:46:37.407Z [INFO]  agent.exec.server: no env templates or exec config, exiting
2026-04-15T20:46:37.407Z [INFO]  agent.auth.handler: starting auth handler
2026-04-15T20:46:37.407Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:46:37.407Z [INFO]  agent.sink.server: starting sink server
2026-04-15T20:46:37.407Z [INFO]  agent.template.server: starting template server
2026-04-15T20:46:37.407Z [INFO]  agent: (runner) creating new runner (dry: false, once: false)
2026-04-15T20:46:37.408Z [INFO]  agent: (runner) creating watcher
2026-04-15T20:46:43.437Z [ERROR] agent.auth.handler: error authenticating: error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving" backoff=820ms
2026-04-15T20:46:44.266Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:46:52.308Z [ERROR] agent.auth.handler: error authenticating: error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving" backoff=820ms
2026-04-15T20:46:53.817Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:46:57.850Z [ERROR] agent.auth.handler: error authenticating: error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving" backoff=1.5s
2026-04-15T20:47:00.393Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:47:06.425Z [ERROR] agent.auth.handler: error authenticating: error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving" backoff=2.54s
2026-04-15T20:47:10.770Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:47:14.803Z [ERROR] agent.auth.handler: error authenticating: error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\": dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving" backoff=4.34s
```

### Pod Status After 29 Minutes (Still Stuck)
```bash
NAME                         READY   STATUS     RESTARTS      AGE
wordpress-56bf4b697d-87tvx   2/2     Running    1 (37m ago)   61m
wordpress-56bf4b697d-8k8jc   2/2     Running    1 (33m ago)   61m
wordpress-56bf4b697d-vxc69   2/2     Running    1 (32m ago)   61m
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0             2m16s  ← STUCK for 29 minutes!
```

### Rolling Update Protection
Note: Old pods were NOT deleted because new pod never became Ready:
```
wordpress-56bf4b697d-87tvx   2/2     Running    ← Still serving traffic
wordpress-56bf4b697d-8k8jc   2/2     Running    ← Still serving traffic
wordpress-56bf4b697d-vxc69   2/2     Running    ← Still serving traffic
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   ← New pod stuck
```

**Service remained available because rolling update strategy keeps old pods until new ones are Ready.**

---

## 5. Evidence - Recovery After IPA Restore

### IPA Start
```bash
ssh root@freeipa 'ipactl start'
```

### Pod Recovery Sequence
```bash
[root@k8s-master1 k8s_admin]# kubectl get pods -n apps -w
NAME                         READY   STATUS     RESTARTS      AGE
wordpress-56bf4b697d-87tvx   2/2     Running    1 (64m ago)   88m
wordpress-56bf4b697d-8k8jc   2/2     Running    1 (60m ago)   88m
wordpress-56bf4b697d-vxc69   2/2     Running    1 (59m ago)   88m
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0             29m
wordpress-7b8c7d879-xbzfr    0/2     PodInitializing   0             29m   ← IPA restored!
wordpress-7b8c7d879-xbzfr    1/2     Running           0             29m
wordpress-7b8c7d879-xbzfr    2/2     Running           0             29m   ← SUCCESS
wordpress-56bf4b697d-8k8jc   2/2     Terminating       1 (61m ago)   89m   ← Old pod cleanup
...
```

### Final State After Recovery
```bash
[root@k8s-master1 k8s_admin]# kubectl get pods -n apps -w
NAME                        READY   STATUS    RESTARTS   AGE
wordpress-7b8c7d879-27b9j   2/2     Running   0          3m37s
wordpress-7b8c7d879-7tzht   2/2     Running   0          3m24s
wordpress-7b8c7d879-xbzfr   2/2     Running   0          33m
```

---

## 6. Analysis

### DNS Resolution Chain
```
Pod (vault-agent-init)
  └─► DNS query for vault.lab.local
        └─► CoreDNS (10.96.0.10)
              └─► Forwards to FreeIPA DNS (10.0.60.10)
                    └─► FreeIPA DOWN → "server misbehaving"
```

### Key Error Message
```
dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving
```
- `10.96.0.10` = CoreDNS service IP
- CoreDNS forwards `.lab.local` queries to FreeIPA
- FreeIPA down = DNS resolution fails

### Impact Summary
```
┌────────────────────────────────────┬────────────────────────┬─────────────────┐
│              Scenario              │       Pods Using       │     Result      │
│                                    │      Vault Agent       │                 │
├────────────────────────────────────┼────────────────────────┼─────────────────┤
│ IPA down, existing pods            │ Already has secrets    │ ✅ Works (slow) │
├────────────────────────────────────┼────────────────────────┼─────────────────┤
│ IPA down, new pods (restart/scale) │ vault-agent-init fails │ ❌ CANNOT START │
├────────────────────────────────────┼────────────────────────┼─────────────────┤
│ IPA restored                       │ Init completes         │ ✅ Recovers     │
└────────────────────────────────────┴────────────────────────┴─────────────────┘
```

### Affected Pods (All with Vault Agent)
- WordPress (3 replicas)
- MariaDB (1 replica)
- Grafana (3 replicas)
- Remediation (1 replica)
- Any future pod with Vault sidecar injection

---

## 7. Operational Guidelines During IPA Outage

**DO NOT:**
- Restart deployments (`kubectl rollout restart`)
- Scale up pods (`kubectl scale`)
- Delete pods (will attempt reschedule)
- Perform node maintenance (pods can't reschedule)

**SAFE:**
- Leave existing pods running (they already have credentials)
- Monitor pod health
- Wait for IPA restoration

**CRITICAL:**
> Node failure during IPA outage = pods cannot reschedule to other nodes

---

## 8. Root Cause

Vault Agent uses hostname `vault.lab.local` for Vault server address. Pod-level DNS resolution goes through CoreDNS, which forwards `.lab.local` domain queries to FreeIPA DNS. When FreeIPA is down:

1. **Running vault-agent sidecars**: Eventually crash after ~10 minutes of retries (but app containers continue running with cached credentials)

2. **New vault-agent-init containers**: Cannot complete initial authentication, blocking pod startup indefinitely

---

## 9. Solution

**Status:** Not implemented yet - documenting for future resolution

**Potential solutions to evaluate:**
1. Add `vault.lab.local` static entry to CoreDNS hosts plugin
2. Configure Vault Agent to use IP address instead of hostname
3. Add fallback DNS (8.8.8.8) to CoreDNS for external resolution
4. Increase Vault Agent retry tolerance

---

## 10. Related Files

- `disaster-recovery/tmp-ipa-domain-down-part2.md` — DR test documentation
- `troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md` — Related WordPress slowness issue
- `troubleshooting/kubernetes/35-pod-restart-investigation-ipa-down.md` — Pod restart investigation
