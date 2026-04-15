# TS-K8S-035 | 2026-04-15 | RESOLVED

## 1. Context
- System: Kubernetes Pod Lifecycle / Container Restarts
- Environment: DEV (lab.local)
- Related components: WordPress pods, MariaDB, Grafana, vault-agent sidecar
- Discovery: **Discovered during IPA Domain Down DR Test (Part 2)**

---

## 2. Issue

During IPA Domain Down DR Test Part 2, observed unexpected pod restarts appearing in `kubectl get pods` output. The RESTARTS column values increased during the test, raising concerns about application stability.

### Initial Observation
```
apps            wordpress-56bf4b697d-87tvx   2/2     Running     1 (8m9s ago)    32m
apps            wordpress-56bf4b697d-8k8jc   2/2     Running     1 (4m24s ago)   32m
apps            wordpress-56bf4b697d-vxc69   2/2     Running     1 (3m22s ago)   31m
database        mariadb-0                    2/2     Running     8 (7m12s ago)   45h
```

### Questions to Investigate
1. Did WordPress application containers restart during IPA outage?
2. Did MariaDB restart during IPA outage?
3. What is the actual cause of the increased RESTARTS count?
4. Is service availability affected?

---

## 3. Investigation Sequence

### 3.1 Initial Pod Status Check (Before Deep Investigation)

```bash
[root@k8s-master1 k8s_admin]# kubectl get pods -A -o wide
NAMESPACE       NAME                                       READY   STATUS      RESTARTS         AGE
apps            wordpress-56bf4b697d-87tvx                 2/2     Running     1 (99s ago)      25m
apps            wordpress-56bf4b697d-8k8jc                 2/2     Running     0                25m
apps            wordpress-56bf4b697d-vxc69                 2/2     Running     0                25m
database        mariadb-0                                  2/2     Running     8 (42s ago)      45h
```

**Note:** Caught live restart with no apparent reason - even for DB.

### 3.2 Describe Pod for Detailed Info

```bash
[root@k8s-master1 k8s_admin]# kubectl describe pod mariadb-0 -n database | grep -A10 "Last State\|Restart Count"
    Restart Count:  3
    Limits:
      cpu:     500m
      memory:  128Mi
    Requests:
      cpu:     250m
      memory:  64Mi
    Environment:
      NAMESPACE:         database (v1:metadata.namespace)
      HOST_IP:            (v1:status.hostIP)
      POD_IP:             (v1:status.podIP)
--
    Last State:     Terminated
      Reason:       Unknown
      Exit Code:    255
      Started:      Tue, 14 Apr 2026 20:05:03 +0200
      Finished:     Wed, 15 Apr 2026 19:44:33 +0200
    Ready:          True
    Restart Count:  3
    ...
--
    Last State:     Terminated
      Reason:       Error
      Exit Code:    1
      Started:      Wed, 15 Apr 2026 20:45:41 +0200
      Finished:     Wed, 15 Apr 2026 22:12:04 +0200
    Ready:          True
    Restart Count:  5
```

**Key Finding:** Two different containers in the same pod with different exit codes and timestamps!

### 3.3 Check Per-Container Restart Details

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

vault	vault-agent-injector-5877589b57-4h2ts
--

vault	vault-agent-injector-5877589b57-cwh5f
```

**Key Finding:** vault-agent containers have "Error" reason, app containers have "Unknown" reason.

### 3.4 Detailed Exit Code and Timestamp Analysis

```bash
[root@k8s-master1 k8s_admin]# for pod in mariadb-0 wordpress-56bf4b697d-87tvx wordpress-56bf4b697d-8k8jc wordpress-56bf4b697d-vxc69; do
    ns=$(kubectl get pods -A | grep $pod | awk '{print $1}')
    echo "=== $pod ($ns) ==="
    kubectl get pod $pod -n $ns -o jsonpath='{range .status.containerStatuses[*]}{.name}: exitCode={.lastState.terminated.exitCode}
  finished={.lastState.terminated.finishedAt}{"\n"}{end}'
    echo ""
done

=== mariadb-0 (database) ===
mariadb: exitCode=255
  finished=2026-04-15T17:44:33Z
vault-agent: exitCode=1
  finished=2026-04-15T20:12:04Z

=== wordpress-56bf4b697d-87tvx (apps) ===
vault-agent: exitCode=1
  finished=2026-04-15T20:11:07Z
wordpress: exitCode=
  finished=

=== wordpress-56bf4b697d-8k8jc (apps) ===
vault-agent: exitCode=1
  finished=2026-04-15T20:14:52Z
wordpress: exitCode=
  finished=

=== wordpress-56bf4b697d-vxc69 (apps) ===
vault-agent: exitCode=1
  finished=2026-04-15T20:15:54Z
wordpress: exitCode=
  finished=
```

### 3.5 Grafana and Remediation Pods Check

```bash
[root@k8s-master1 k8s_admin]# kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{range .items[*]}Pod: {.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}:
  exitCode={.lastState.terminated.exitCode} finished={.lastState.terminated.finishedAt}{"\n"}{end}{"\n"}{end}'

Pod: kube-prometheus-stack-grafana-5f6554dcf5-lrvqq
  grafana:
  exitCode=255 finished=2026-04-15T17:44:33Z
  grafana-sc-dashboard:
  exitCode=255 finished=2026-04-15T17:44:33Z
  grafana-sc-datasources:
  exitCode=255 finished=2026-04-15T17:44:33Z
  vault-agent:
  exitCode=1 finished=2026-04-15T20:12:16Z

Pod: kube-prometheus-stack-grafana-5f6554dcf5-mqbk5
  grafana:
  exitCode=255 finished=2026-04-15T17:44:23Z
  grafana-sc-dashboard:
  exitCode=255 finished=2026-04-15T17:44:23Z
  grafana-sc-datasources:
  exitCode=255 finished=2026-04-15T17:44:23Z
  vault-agent:
  exitCode=1 finished=2026-04-15T20:13:03Z

Pod: kube-prometheus-stack-grafana-5f6554dcf5-pbbn6
  grafana:
  exitCode=255 finished=2026-04-15T17:44:31Z
  grafana-sc-dashboard:
  exitCode=255 finished=2026-04-15T17:44:31Z
  grafana-sc-datasources:
  exitCode=255 finished=2026-04-15T17:44:31Z
  vault-agent:
  exitCode=1 finished=2026-04-15T20:15:26Z

[root@k8s-master1 k8s_admin]# kubectl get pod -n remediation -o jsonpath='{range .items[*]}Pod: {.metadata.name}{"\n"}{range .status.containerStatuses[*]}  {.name}:
  exitCode={.lastState.terminated.exitCode} finished={.lastState.terminated.finishedAt}{"\n"}{end}{"\n"}{end}'

Pod: remediation-56bdddfcd7-t8fvv
  remediation:
  exitCode=255 finished=2026-04-15T17:42:46Z
  vault-agent:
  exitCode=1 finished=2026-04-15T20:14:25Z
```

---

## 4. Evidence Summary

### 4.1 Exit Code Meaning Table
| Exit Code | Meaning | Context |
|-----------|---------|---------|
| 255 | SIGKILL from kubelet | Node/kubelet restart, OOM kill |
| 1 | Application error | DNS lookup failure, auth failure |
| (empty) | Never terminated | Container has been running since pod creation |

### 4.2 Timeline Separation Table
```
┌────────────────┬───────────┬──────────────┬─────────────────────┐
│ Container Type │ Exit Code │  Time (UTC)  │        Event        │
├────────────────┼───────────┼──────────────┼─────────────────────┤
│ App containers │ 255       │ 17:42-17:44Z │ Node restart (PAST) │
├────────────────┼───────────┼──────────────┼─────────────────────┤
│ vault-agent    │ 1         │ 20:11-20:15Z │ IPA DNS down (TEST) │
└────────────────┴───────────┴──────────────┴─────────────────────┘
```

### 4.3 Detailed Evidence by Container Type

**App Containers (Exit 255) - Node Event @ ~17:44Z (BEFORE IPA TEST):**
```
mariadb:           17:44:33Z
grafana (pod 1):   17:44:33Z
grafana (pod 2):   17:44:23Z
grafana (pod 3):   17:44:31Z
remediation:       17:42:46Z
```

**vault-agent (Exit 1) - IPA Test @ ~20:12Z (DURING IPA TEST):**
```
mariadb:           20:12:04Z
wordpress (pod 1): 20:11:07Z
wordpress (pod 2): 20:14:52Z
wordpress (pod 3): 20:15:54Z
grafana (pod 1):   20:12:16Z
grafana (pod 2):   20:13:03Z
grafana (pod 3):   20:15:26Z
remediation:       20:14:25Z
```

**WordPress containers: NEVER CRASHED**
```
wordpress: exitCode=  finished=   ← Empty = no crash history
```

---

## 5. RESTARTS Column Misconception

### 5.1 How RESTARTS Works
```
NAME        READY   STATUS    RESTARTS   AGE
mariadb-0   2/2     Running   8          2d    ← 8 = mariadb(3) + vault-agent(5)
```

**Common Misconception:** RESTARTS: 8 means pod restarted 8 times.

**Reality:**
- mariadb container: 3 restarts
- vault-agent container: 5 restarts
- Total shown: 8

### 5.2 Command to See Per-Container Restarts
```bash
kubectl get pod mariadb-0 -n database -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.restartCount}{"\n"}{end}'
```

### 5.3 Pod vs Container Restart Behavior
```
┌───────────────────┬──────────────────────────────────────────────────────────────┐
│       What        │                           Behavior                           │
├───────────────────┼──────────────────────────────────────────────────────────────┤
│ Pod restart       │ All containers killed, pod recreated, AGE resets             │
├───────────────────┼──────────────────────────────────────────────────────────────┤
│ Container restart │ Only that container restarts, AGE stays, RESTARTS increments │
└───────────────────┴──────────────────────────────────────────────────────────────┘
```

---

## 6. Container Uptime Verification

### 6.1 Misleading Uptime Command

```bash
root@wordpress-56bf4b697d-87tvx:/var/www/html# uptime
 20:32:39 up  2:49,  0 users,  load average: 0.13, 0.17, 0.17
```

**Question:** Why does uptime show 2:49 if pod was created ~1 hour ago?

**Answer:** `uptime` inside a container shows NODE uptime, NOT container uptime!

### 6.2 Correct Commands for Container Age

```bash
# Pod creation time (doesn't change on container restart)
kubectl get pod wordpress-56bf4b697d-87tvx -n apps -o jsonpath='{.status.startTime}'
2026-04-15T19:47:02Z

# Container start time (changes after restart)
kubectl get pod mariadb-0 -n database -o jsonpath='{.status.containerStatuses[?(@.name=="mariadb")].state.running.startedAt}'
2026-04-15T17:45:24Z

# All containers in a pod
kubectl get pod mariadb-0 -n database -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.state.running.startedAt}{"\n"}{end}'
```

### 6.3 Correct Method Table
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

---

## 7. WordPress Container Logs (No Crash Evidence)

```bash
[root@k8s-master1 k8s_admin]# kubectl logs wordpress-56bf4b697d-87tvx -n apps --previous
Error from server (BadRequest): previous terminated container "wordpress" in pod "wordpress-56bf4b697d-87tvx" not found
```

**Confirms:** WordPress container has no previous termination - it never crashed.

```bash
[root@k8s-master1 k8s_admin]# kubectl logs wordpress-56bf4b697d-87tvx -n apps
Defaulted container "wordpress" out of: wordpress, vault-agent, wait-for-mariadb (init), vault-agent-init (init)
WordPress not found in /var/www/html - copying now...
WARNING: '/var/www/html/wp-content/themes/twentytwentyfive' exists! (not copying the WordPress version)
WARNING: '/var/www/html/wp-content/themes/twentytwentyfour' exists! (not copying the WordPress version)
WARNING: '/var/www/html/wp-content/themes/twentytwentythree' exists! (not copying the WordPress version)
Complete! WordPress has been successfully copied to /var/www/html
No 'wp-config.php' found in /var/www/html, but 'WORDPRESS_...' variables supplied; copying 'wp-config-docker.php'...
AH00558: apache2: Could not reliably determine the server's fully qualified domain name, using 10.244.29.160...
[Wed Apr 15 19:47:09.405744 2026] [mpm_prefork:notice] [pid 1:tid 1] AH00163: Apache/2.4.66 (Debian) PHP/8.2.30 configured -- resuming normal operations
[Wed Apr 15 19:47:09.405791 2026] [core:notice] [pid 1:tid 1] AH00094: Command line: 'apache2 -D FOREGROUND'
10.0.64.12 - - [15/Apr/2026:19:47:13 +0000] "GET /wp-content/index.php HTTP/1.1" 200 192 "-" "kube-probe/1.3
```

**Confirms:** WordPress container started normally and has been running continuously.

---

## 8. Events Check

```bash
[root@k8s-master1 k8s_admin]# kubectl get events -n database --field-selector involvedObject.name=mariadb-0 --sort-by='.lastTimestamp'
LAST SEEN   TYPE     REASON    OBJECT          MESSAGE
9m51s       Normal   Pulled    pod/mariadb-0   Container image "hashicorp/vault:1.21.2" already present on machine and can be accessed by the pod
9m50s       Normal   Created   pod/mariadb-0   Container created
9m50s       Normal   Started   pod/mariadb-0   Container started
```

**Note:** Events show vault-agent container restart, not mariadb container restart.

---

## 9. Conclusions

### 9.1 Final Confirmation Table
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

### 9.2 Root Causes Identified
- **17:44Z (Exit 255):** Node/kubelet restart event ~2.5 hours before IPA test
- **20:11-20:15Z (Exit 1):** vault-agent DNS failures during IPA Down test

### 9.3 Impact on Service
- WordPress application: **NOT affected** - containers kept running
- MariaDB application: **NOT affected** - container kept running
- Grafana application: **NOT affected** - containers kept running
- vault-agent sidecars: **Restarted** - but apps already had cached secrets

---

## 10. Key Learnings

1. **RESTARTS column is aggregate** - Sum of all containers, not pod restarts
2. **Exit code 255 vs 1** - Different causes (node event vs app error)
3. **`uptime` inside container** - Shows node uptime, NOT container uptime
4. **Correct container age command:** `.status.containerStatuses[].state.running.startedAt`
5. **vault-agent crash != app crash** - Sidecar isolation works correctly

---

## 11. Resolution

**No action required for application stability.**

The observed "restarts" during IPA Down test were exclusively vault-agent sidecar restarts caused by DNS resolution failures. The application containers (WordPress, MariaDB, Grafana) remained stable throughout the test.

For vault-agent restart solution, see: **TS-K8S-033** (`troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md`)

---

## 12. Related Documentation

| File | Description |
|------|-------------|
| `troubleshooting/kubernetes/33-vault-agent-dns-failure-new-pod-blocking.md` | TS-K8S-033: Vault Agent DNS failure and solution |
| `troubleshooting/kubernetes/34-wordpress-external-dns-slowness.md` | TS-K8S-034: WordPress external DNS timeouts |
| `disaster-recovery/tmp-ipa-domain-down-part2.md` | Part 2 DR test documentation |

---

## 13. Useful Commands Reference

```bash
# See per-container restarts
kubectl get pod <pod> -n <ns> -o jsonpath='{range .status.containerStatuses[*]}{.name}: {.restartCount}{"\n"}{end}'

# See container exit codes and timestamps
kubectl get pod <pod> -n <ns> -o jsonpath='{range .status.containerStatuses[*]}{.name}: exitCode={.lastState.terminated.exitCode} finished={.lastState.terminated.finishedAt}{"\n"}{end}'

# See container current start time (actual uptime)
kubectl get pod <pod> -n <ns> -o jsonpath='{range .status.containerStatuses[*]}{.name}: started={.state.running.startedAt}{"\n"}{end}'

# Get all pods with restarts > 0
kubectl get pods -A | awk '$5 > 0'
```
