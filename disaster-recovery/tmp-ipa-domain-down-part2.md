# IPA Domain Down - Part 2
# Date: 2026-04-15
# Result: COMPLETED

---

## Test Scope

Continue IPA outage testing after Part 1, focusing on:
- Vault Agent behavior during DNS failure
- Pod restart/scaling impact during outage
- WordPress performance degradation root cause
- Ansible automation slowness investigation
- Recovery behavior after IPA restoration

---

## Test Timeline

| Time (EET) | Time (UTC) | Event |
|------------|------------|-------|
| 22:00:49 | 20:00:49Z | IPA stopped |
| 22:11-22:15 | 20:11-20:15Z | vault-agent containers crash (DNS failure) |
| 22:30 | 20:30Z | WordPress slowness investigation |
| 22:46 | 20:46Z | Triggered rollout restart (test new pod behavior) |
| 22:51 | 20:51Z | Ansible delay issue discovered |
| 23:17 | 21:17Z | IPA restored |
| 23:20 | 21:20Z | Pod recovery observed |

---

## Baseline (Pre-Test)

### Pod Distribution Before IPA Stop
```
NAMESPACE     NAME                                       NODE
apps          wordpress-56bf4b697d-87tvx                 k8s-worker3.lab.local
apps          wordpress-56bf4b697d-8k8jc                 k8s-worker3.lab.local
apps          wordpress-56bf4b697d-vxc69                 k8s-worker1.lab.local
database      mariadb-0                                  k8s-worker3.lab.local
monitoring    grafana-545d8797c9-nfxrx                   k8s-worker3.lab.local
monitoring    grafana-545d8797c9-wblch                   k8s-worker1.lab.local
monitoring    grafana-545d8797c9-xh8dp                   k8s-worker2.lab.local
monitoring    remediation-6d7d4f67dd-jt7pj               k8s-worker1.lab.local
flux-system   helm-controller-6fbc97d94-w6mfq            k8s-worker2.lab.local
flux-system   source-controller-855bc567db-k8rh4        k8s-worker2.lab.local
```

**Note:** WordPress pods have anti-affinity but 2/3 scheduled on worker3 due to soft preference (see TS-K8S-031: `troubleshooting/kubernetes/31-wordpress-antiaffinity-scheduling.md`)

---

## Test Execution

### Stop IPA
```bash
[root@k8s-master1 k8s_admin]# ssh root@freeipa 'ipactl stop'
Stopping IPA services: ...
[root@k8s-master1 k8s_admin]# date
Wed Apr 15 10:00:49 PM EET 2026
```

---

## Finding #1: Vault Agent DNS Failure (Immediate)

### Symptom
Vault Agent sidecars immediately began failing to authenticate.

### Evidence
```bash
kubectl logs -n apps wordpress-56bf4b697d-87tvx -c vault-agent --tail=20
```

```
2026-04-15T20:03:03.437Z [ERROR] agent.auth.handler: error authenticating:
  error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving"
  backoff=820ms
2026-04-15T20:03:04.266Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:03:12.308Z [ERROR] agent.auth.handler: error authenticating:
  error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving"
  backoff=820ms
2026-04-15T20:03:13.817Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:03:17.850Z [ERROR] agent.auth.handler: error authenticating:
  ...
  backoff=1.5s
2026-04-15T20:03:20.393Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:03:26.425Z [ERROR] agent.auth.handler: error authenticating:
  ...
  backoff=2.54s
2026-04-15T20:03:30.770Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:03:34.803Z [ERROR] agent.auth.handler: error authenticating:
  ...
  backoff=4.34s
```

### Analysis
- Error: `lookup vault.lab.local on 10.96.0.10:53: server misbehaving`
- 10.96.0.10 = CoreDNS service IP
- CoreDNS forwards `.lab.local` queries to FreeIPA (10.0.60.10)
- FreeIPA down → DNS resolution fails → Vault Agent cannot authenticate
- **Exponential backoff pattern**: 820ms → 1.5s → 2.54s → 4.34s (doubles each retry)

### Result
After ~10 minutes of retries, vault-agent containers crashed (exit code 1).

---

## Finding #2: Exit Code Analysis - Separating Past Events from Test

### Hypothesis
Are all the container restarts we see caused by our IPA test?

### Investigation
```bash
kubectl get pods -n apps -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.name}{"\t"}{.restartCount}{"\t"}{.lastState.terminated.exitCode}{"\t"}{.lastState.terminated.finishedAt}{"\n"}{end}{end}'
```

### Evidence Table
```
┌────────────────┬───────────┬──────────────┬─────────────────────┐
│   Container    │ Exit Code │  Timestamp   │       Cause         │
├────────────────┼───────────┼──────────────┼─────────────────────┤
│ mariadb        │ 255       │ 17:44:33Z    │ Node restart (PAST) │
├────────────────┼───────────┼──────────────┼─────────────────────┤
│ grafana        │ 255       │ 17:44:23-33Z │ Node restart (PAST) │
├────────────────┼───────────┼──────────────┼─────────────────────┤
│ remediation    │ 255       │ 17:42:46Z    │ Node restart (PAST) │
├────────────────┼───────────┼──────────────┼─────────────────────┤
│ vault-agent    │ 1         │ 20:11-20:15Z │ IPA DNS down (TEST) │
└────────────────┴───────────┴──────────────┴─────────────────────┘
```

### Exit Code Meanings
| Exit Code | Meaning | Context |
|-----------|---------|---------|
| 255 | SIGKILL from kubelet | Node/kubelet restart, OOM kill |
| 1 | Application error | DNS lookup failure, auth failure |

### Key Insight
- **Exit 255 @ 17:42-17:44Z**: Previous node restart event (~2.5 hours before test)
- **Exit 1 @ 20:11-20:15Z**: vault-agent DNS failures during our IPA test
- **WordPress container**: NEVER crashed (empty exitCode/finishedAt)

### Conclusion
```
┌───────────────────────────────────────────────────┬───────────────────────────────┐
│                      Finding                      │           Confirmed           │
├───────────────────────────────────────────────────┼───────────────────────────────┤
│ vault-agent crashes are separate from app crashes │ ✅ Yes (~2.5 hour gap)        │
├───────────────────────────────────────────────────┼───────────────────────────────┤
│ App container restarts happened before IPA test   │ ✅ Yes (17:44Z vs 20:12Z)     │
├───────────────────────────────────────────────────┼───────────────────────────────┤
│ vault-agent crash does NOT cause app crash        │ ✅ Yes                        │
├───────────────────────────────────────────────────┼───────────────────────────────┤
│ WordPress container never crashed                 │ ✅ Yes (only vault-agent did) │
└───────────────────────────────────────────────────┴───────────────────────────────┘
```

---

## Finding #3: Container Age vs Pod Age vs Node Uptime

### Misleading Observation
```bash
kubectl exec -n apps wordpress-56bf4b697d-87tvx -- uptime
 20:32:39 up  2:49,  0 users,  load average: 0.13, 0.17, 0.17
```
**Question:** Why does uptime show 2:49 if we just did a rollout restart 1 hour ago?

### Investigation
```bash
# This shows NODE uptime, NOT container uptime!
kubectl exec -n apps wordpress-56bf4b697d-87tvx -- uptime

# Correct command for container start time:
kubectl get pod wordpress-56bf4b697d-87tvx -n apps \
  -o jsonpath='{.status.containerStatuses[?(@.name=="wordpress")].state.running.startedAt}'
```

### Evidence
```bash
[root@k8s-master1]# kubectl get pod wordpress-56bf4b697d-87tvx -n apps -o jsonpath='{.status.startTime}'
2026-04-15T19:47:02Z

[root@k8s-master1]# date
Wed Apr 15 10:35:41 PM EET 2026
```

### Key Lesson Learned
```
┌─────────────────────────────────────────────────────┬─────────────────┬───────────────────────────────┐
│                       Command                       │      Shows      │            Use For            │
├─────────────────────────────────────────────────────┼─────────────────┼───────────────────────────────┤
│ uptime (inside container)                           │ Node uptime     │ Misleading - AVOID            │
├─────────────────────────────────────────────────────┼─────────────────┼───────────────────────────────┤
│ kubectl get pods AGE column                         │ Pod creation    │ When pod was first created    │
├─────────────────────────────────────────────────────┼─────────────────┼───────────────────────────────┤
│ .status.startTime                                   │ Pod creation    │ When pod was first created    │
├─────────────────────────────────────────────────────┼─────────────────┼───────────────────────────────┤
│ .status.containerStatuses[].state.running.startedAt │ Container start │ After restart - actual uptime │
└─────────────────────────────────────────────────────┴─────────────────┴───────────────────────────────┘
```

### Correct Command for Container Start Time
```bash
# Single container:
kubectl get pod mariadb-0 -n database \
  -o jsonpath='{.status.containerStatuses[?(@.name=="mariadb")].state.running.startedAt}'

# All containers in a pod:
kubectl get pod mariadb-0 -n database \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state.running.startedAt}{"\n"}{end}'
```

---

## Finding #4: RESTARTS Column Aggregates All Containers

### Observation
```
NAME        READY   STATUS    RESTARTS   AGE
mariadb-0   2/2     Running   8          2d    ← 8 = mariadb(3) + vault-agent(5)
```

### Misconception
RESTARTS: 8 doesn't mean pod restarted 8 times.

### Reality
- mariadb container: 3 restarts
- vault-agent container: 5 restarts
- Total shown: 8

### Command to See Per-Container Restarts
```bash
kubectl get pod mariadb-0 -n database \
  -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.restartCount}{"\n"}{end}'
```

### Key Insight
vault-agent restarts inflated the RESTARTS count, making pods look worse than they were. WordPress and MariaDB application containers stayed running.

---

## Finding #5: WordPress Slowness Root Cause (External DNS Timeouts)

### Symptom
WordPress admin pages taking 4-12 seconds to load during IPA outage.

### Browser DevTools Analysis
```
wp-admin/                200  document   4.27 s     ← Initial page load
admin-ajax.php           200  xhr        12.16 s    ← AJAX calls
favicon.ico              302  redirect   4.14 s     ← Redirect
gravatar.com images      304  jpeg       148 ms     ← External avatars
```

### DNS Resolution Test (From K8s Node)
```bash
[root@k8s-master1]# nslookup gravatar.com
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; no servers could be reached

[root@k8s-master1]# nslookup api.wordpress.org
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; communications error to 10.0.60.10#53: connection refused
;; no servers could be reached
```

### Root Cause Analysis
```
┌─────────────────────────┬──────────────────────┬────────────────────────┐
│         Service         │       Purpose        │      DNS Required      │
├─────────────────────────┼──────────────────────┼────────────────────────┤
│ Gravatar (gravatar.com) │ User avatars         │ ✅ Yes                 │
├─────────────────────────┼──────────────────────┼────────────────────────┤
│ api.wordpress.org       │ Plugin/update checks │ ✅ Yes                 │
├─────────────────────────┼──────────────────────┼────────────────────────┤
│ admin-ajax.php          │ WP backend calls     │ May call external APIs │
└─────────────────────────┴──────────────────────┴────────────────────────┘
```

### Delay Calculation
```
┌───────────────────┬────────────────────────────┬───────────┐
│      Request      │        What Happens        │  Result   │
├───────────────────┼────────────────────────────┼───────────┤
│ gravatar.com      │ DNS timeout                │ +5s delay │
├───────────────────┼────────────────────────────┼───────────┤
│ api.wordpress.org │ DNS timeout                │ +5s delay │
├───────────────────┼────────────────────────────┼───────────┤
│ admin-ajax.php    │ Multiple DNS calls timeout │ 12s total │
└───────────────────┴────────────────────────────┴───────────┘
```

### Conclusion
WordPress slowness is caused by external DNS resolution timeouts, NOT by IPA outage directly affecting WordPress functionality.

---

## Finding #6: Critical - New Pods Cannot Start During IPA Outage

### Test
Triggered rollout restart while IPA was still down:
```bash
kubectl rollout restart deployment wordpress -n apps
```

### Observation
```bash
kubectl get pods -n apps -w
NAME                         READY   STATUS     RESTARTS      AGE
wordpress-56bf4b697d-87tvx   2/2     Running    1 (35m ago)   59m   ← Old pod (working)
wordpress-56bf4b697d-8k8jc   2/2     Running    1 (31m ago)   59m   ← Old pod (working)
wordpress-56bf4b697d-vxc69   2/2     Running    1 (30m ago)   59m   ← Old pod (working)
wordpress-7b8c7d879-xbzfr    0/2     Pending    0             0s    ← New pod
wordpress-7b8c7d879-xbzfr    0/2     Init:0/2   0             1s    ← STUCK!
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2   0             6s    ← vault-agent-init failing
```

### vault-agent-init Logs (New Pod)
```bash
kubectl logs -n apps wordpress-7b8c7d879-xbzfr -c vault-agent-init
```
```
2026-04-15T20:46:37.406Z [INFO]  agent.sink.file: creating file sink
2026-04-15T20:46:37.407Z [INFO]  agent.auth.handler: starting auth handler
2026-04-15T20:46:37.407Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:46:43.437Z [ERROR] agent.auth.handler: error authenticating:
  error="Put \"https://vault.lab.local:8200/v1/auth/kubernetes/login\":
  dial tcp: lookup vault.lab.local on 10.96.0.10:53: server misbehaving"
  backoff=820ms
2026-04-15T20:46:44.266Z [INFO]  agent.auth.handler: authenticating
2026-04-15T20:46:52.308Z [ERROR] agent.auth.handler: error authenticating:
  ...
  backoff=820ms
```

**Pod remained stuck in Init:1/2 for 29 minutes until IPA was restored.**

### Critical DR Implication
```
┌────────────────────────────────────┬────────────────────────┬─────────────────┐
│              Scenario              │       WordPress        │     Result      │
├────────────────────────────────────┼────────────────────────┼─────────────────┤
│ IPA down, existing pods            │ Already has secrets    │ ✅ Works (slow) │
├────────────────────────────────────┼────────────────────────┼─────────────────┤
│ IPA down, new pods (restart/scale) │ vault-agent-init fails │ ❌ CANNOT START │
└────────────────────────────────────┴────────────────────────┴─────────────────┘
```

### Operational Guidelines During IPA Outage
- **DO NOT** restart deployments during IPA outage
- **DO NOT** scale up pods during IPA outage
- **WARNING**: Node failure during IPA outage = pods cannot reschedule
- **SAFE**: Leave existing pods running (they already have credentials)

### Why Service Stayed Available
Rolling update strategy ensures old pods are NOT deleted until new pods are Ready:
```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 1
    maxSurge: 1
```

---

## Finding #7: Ansible 28-Second Delay Issue (TS-IDN-009)

### Symptom
```bash
[root@ansible dev]# time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping
10.0.64.10 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}

real    0m34.479s   ← 34 SECONDS!
user    0m0.856s
sys     0m0.318s
```

### Comparison: Raw Module (Fast)
```bash
[root@ansible dev]# time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m raw -a 'hostname'
10.0.64.10 | CHANGED | rc=0 >>
k8s-worker1.lab.local

real    0m0.716s    ← 0.7 seconds (FAST)
user    0m0.378s
sys     0m0.087s
```

### Investigation Trail

#### Hypothesis 1: Python Interpreter Discovery (WRONG)
```bash
time ansible ... -m ping -e 'ansible_python_interpreter=/usr/bin/python3'
real    0m28.253s   ← Still slow - NOT the cause
```

#### Hypothesis 2: Kerberos/GSSAPI Authentication (WRONG)
```bash
# Added to inventory:
ansible_ssh_common_args='-o PreferredAuthentications=publickey'
# Result: Still slow ~28 seconds
```

#### Hypothesis 3: Kerberos Tickets (WRONG)
```bash
kdestroy
time ansible ... -m ping
# Result: Still slow ~28 seconds
```

#### Hypothesis 4: SSH UseDNS (WRONG)
```bash
ssh root@10.0.64.10 'grep -i usedns /etc/ssh/sshd_config'
#UseDNS no   ← Already disabled
```

### Root Cause Found (via -vvvv)
```bash
time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping -vvvv
```

**Critical finding in debug output:**
```
debug3: subprocess: KnownHostsCommand-ORDER command "/usr/bin/sss_ssh_knownhosts 10.0.64.10" running as root
debug3: subprocess: KnownHostsCommand-HOSTNAME command "/usr/bin/sss_ssh_knownhosts 10.0.64.10" running as root
```

This is configured by FreeIPA in `/etc/ssh/ssh_config.d/04-ipa.conf`:
```
Match exec "true"
    KnownHostsCommand /usr/bin/sss_ssh_knownhosts %H
```

### Delay Calculation
```
┌──────────────────────────────────────┬───────┐
│              Component               │ Count │
├──────────────────────────────────────┼───────┤
│ SSH connections per ansible ping     │ 7-8   │
├──────────────────────────────────────┼───────┤
│ sss_ssh_knownhosts calls per SSH     │ 2     │
├──────────────────────────────────────┼───────┤
│ Total SSSD lookups                   │ 14-16 │
├──────────────────────────────────────┼───────┤
│ Timeout per lookup (approx)          │ ~2s   │
├──────────────────────────────────────┼───────┤
│ Total delay                          │ ~28s  │
└──────────────────────────────────────┴───────┘
```

### Solution
Add to Ansible inventory:
```ini
[all:vars]
ansible_ssh_common_args='-o KnownHostsCommand=none'
```

### Verification
```bash
[root@ansible dev]# time ansible -i inventory/first_setup_inventory.ini 10.0.64.10 -m ping
10.0.64.10 | SUCCESS => {...}

real    0m2.996s    ← 3 seconds (FIXED!)
```

**Full troubleshooting case documented: `troubleshooting/identity/9-ansible-sssd-knownhosts-timeout.md`**

---

## Finding #8: IPA Restoration and Pod Recovery

### IPA Restore
```bash
ssh root@freeipa 'ipactl start'
ssh root@freeipa 'ipactl status'
```

### Pod Recovery Observation
```bash
kubectl get pods -n apps -w
NAME                         READY   STATUS           RESTARTS      AGE
wordpress-56bf4b697d-87tvx   2/2     Running          1 (64m ago)   88m
wordpress-56bf4b697d-8k8jc   2/2     Running          1 (60m ago)   88m
wordpress-56bf4b697d-vxc69   2/2     Running          1 (59m ago)   88m
wordpress-7b8c7d879-xbzfr    0/2     Init:1/2         0             29m   ← Was STUCK
wordpress-7b8c7d879-xbzfr    0/2     PodInitializing  0             29m   ← IPA restored!
wordpress-7b8c7d879-xbzfr    1/2     Running          0             29m
wordpress-7b8c7d879-xbzfr    2/2     Running          0             29m   ← SUCCESS
wordpress-56bf4b697d-8k8jc   2/2     Terminating      1 (61m ago)   89m   ← Old pod cleanup
...
```

### Final State (After Recovery)
```bash
kubectl get pods -n apps
NAME                        READY   STATUS    RESTARTS   AGE
wordpress-7b8c7d879-27b9j   2/2     Running   0          3m37s
wordpress-7b8c7d879-7tzht   2/2     Running   0          3m24s
wordpress-7b8c7d879-xbzfr   2/2     Running   0          33m
```

### Recovery Timeline
- Stuck pod (29 minutes) → Recovered in seconds after IPA restored
- Rolling update completed successfully
- All old pods gracefully terminated

---

## Summary of Findings

### What Works During IPA Outage
| Component | Status | Notes |
|-----------|--------|-------|
| K8s cluster | ✅ Works | Uses IPs internally |
| Existing pods | ✅ Works | Already have credentials |
| Node SSH (with /etc/hosts) | ✅ Works | IP-based fallback |
| WordPress (basic function) | ⚠️ Slow | External DNS timeouts |

### What Breaks During IPA Outage
| Component | Status | Notes |
|-----------|--------|-------|
| New pods (restart/scale) | ❌ Fails | vault-agent-init cannot authenticate |
| External DNS resolution | ❌ Fails | All lookups timeout |
| FluxCD/Helm | ❌ Fails | Cannot pull from external repos |
| Ansible (default config) | ❌ Slow | SSSD KnownHostsCommand timeouts |

---

## Implemented Fixes

### Fix 1: Ansible SSH Known Hosts Timeout
**Location:** `ansible/dev/inventory/first_setup_inventory.ini`
```ini
[all:vars]
ansible_ssh_common_args='-o KnownHostsCommand=none'
```
**Result:** Ansible commands execute in ~3 seconds regardless of IPA availability

---

## Recommendations

### Immediate (Low Risk)
1. ✅ **DONE** - Add `KnownHostsCommand=none` to all Ansible inventories (TS-IDN-009)
2. ✅ **DONE** - Add fallback DNS to Linux nodes via `zzz-ipa.conf` (TS-LNX-010)
3. Document operational guidelines for IPA outage scenarios

### Medium Term
1. Consider CoreDNS forward policy change (forward to multiple DNS including fallback)
2. Add Vault Agent error tolerance configuration
3. Configure WordPress to disable external API calls (Gravatar, update checks) during degraded mode

### Long Term
1. Evaluate IPA high availability (replica)
2. Consider caching DNS resolver for external domains
3. Test node failure scenario during IPA outage

---

## Related Documentation

| File | Description |
|------|-------------|
| `troubleshooting/identity/9-ansible-sssd-knownhosts-timeout.md` | TS-IDN-009: Ansible SSSD delay |
| `troubleshooting/kubernetes/31-wordpress-antiaffinity-scheduling.md` | TS-K8S-031: Pod scheduling behavior |
| `troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md` | TS-K8S-033: Vault Agent DNS failure + new pod blocking |
| `troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md` | TS-K8S-034: WordPress external DNS timeouts |
| `troubleshooting/kubernetes/35-pod-restart-investigation-ipa-down.md` | TS-K8S-035: Pod restart investigation (vault-agent vs app) |
| `troubleshooting/linux/3-linux-nodes-dns-fallback.md` | TS-LNX-003: Linux nodes DNS fallback fix |
| `disaster-recovery/tmp-ipa-domain-down-part1.md` | Part 1 test results |

---

## Conclusion

Part 2 testing confirmed and expanded upon Part 1 findings:

1. **Existing workloads survive** IPA outage but experience slowness
2. **New workloads cannot start** during IPA outage (vault-agent-init dependency)
3. **Rolling update strategy** protects service availability
4. **Ansible delay** was SSSD-based SSH host key lookup, not Kerberos
5. **Recovery is automatic** once IPA is restored

**Critical operational rule:** During IPA outage, DO NOT restart/scale deployments that use Vault secrets.
