# TS-K8S-057 | 2026-05-01 | SUSPENDED
_____________________________________________________________________

[Info]
Domain: Kubernetes / CronJob / Vault Integration
Sub-techs: CronJob, Vault agent injector, etcd-backup, backoffLimit,
           Alertmanager KubeJobFailed, boot sequencing
Environment: DEV + PROD k8s clusters | etcd-backup namespace
Severity: LOW
Discovered during: Alertmanager fired 3 x KubeJobFailed for etcd-backup
                   namespace — investigated why
Related: etcd-backup-s3-validation (DR test), TS-PVE-017 (IO watchdog —
         related boot sequencing context)
Re-opened: 2026-05-04

_____________________________________________________________________

[Issue Description]
Alertmanager firing 3 KubeJobFailed alerts for etcd-backup namespace.
The CronJob runs daily at 20:30 Cairo time — but I work at night and
the cluster is usually powered off during that window. When I boot the
cluster next day, the queued job fires immediately. Problem: Vault
isn't ready yet.

_____________________________________________________________________

[Analysis]

# The alert

Alertmanager showed 3 firing alerts, all KubeJobFailed, all in
etcd-backup namespace. Three different job names:
- etcd-backup-29598120
- etcd-backup-29623290
- etcd-backup-29624730

# Current state — not all jobs are failing

```
kubectl get jobs -n etcd-backup
NAME                   STATUS     COMPLETIONS   DURATION   AGE
etcd-backup-29598120   Failed     0/1           20d        20d
etcd-backup-29620410   Complete   1/1           5m31s      4d15h
etcd-backup-29621850   Complete   1/1           95s        3d15h
etcd-backup-29623290   Failed     0/1           2d14h      2d14h
etcd-backup-29624730   Failed     0/1           25h        25h
etcd-backup-29626170   Complete   1/1           99s        15h
```

3 failed, 3 completed. The job works — it just fails intermittently.
The completed ones ran fine (95s, 99s). The failed ones are the ones
that fired during boot-time.

# Why the alerts keep piling up

`failedJobsHistoryLimit: 3` — Kubernetes keeps 3 failed Job objects
around. Each one triggers a KubeJobFailed alert. So even though the
latest run succeeded, 3 stale failures are sitting there keeping the
alerts firing.

# Cross-referencing with boot times

The failed job `etcd-backup-29624730`:
- Scheduled: 2026-04-29 at 20:30 (cluster was off)
- Actually started: 2026-04-30 at 10:52
- Server boot time: `last reboot` shows 2026-04-30 at 10:51

The job fired within 1 minute of the boot. Same pattern for the
20-day-old failure — `etcd-backup-29598120`:
- Scheduled: 2026-04-11 at 06:00 UTC
- Boot time: 2026-04-11 at 10:38

The job fires as soon as the cluster is up. Every time.

# Why it fails at boot — Vault isn't ready

The CronJob uses `vault.hashicorp.com/agent-pre-populate-only: "true"`.
This means the Vault agent runs as an init container — not a sidecar.
It must complete before the backup container starts.

At boot time, Vault pods are still starting up. The webhook injector
pod goes through sandbox recreation:

```
Events:
  Normal  SandboxChanged  38m  kubelet  Pod sandbox changed, it will be killed and re-created.
  Normal  Pulled          38m  kubelet  Container image "hashicorp/vault-k8s:1.7.2" already present
  Normal  Created         38m  kubelet  Container created
  Normal  Started         38m  kubelet  Container started
```

Vault needs several minutes to stabilize — sandbox recreation, unsealing,
the injector pod becoming ready. The backup job's Vault init container
tries to connect, Vault isn't ready, init container fails, main backup
container never starts. That's why `kubectl logs job/<failed-job>` returns
nothing — the backup script never ran.

# The retry math that kills it

`backoffLimit: 2` = 3 total attempts. Kubernetes exponential backoff
between retries: ~10s, ~20s, ~40s. All 3 attempts burned within about
1 minute. Vault needs 3-5 minutes minimum after boot. The job exhausts
its retries before Vault is even up.

# Suspected Root Cause

Boot-time race condition: CronJob fires queued job immediately on boot,
Vault init container can't reach Vault (still starting), backoffLimit
too low to survive the wait.

_____________________________________________________________________

[Final Root Cause]
The etcd-backup CronJob is scheduled at 20:30 — cluster is usually off.
When the cluster boots next day, Kubernetes fires the missed job
immediately. The Vault agent init container fails because Vault pods
are still stabilizing (sandbox recreation, unsealing). With
`backoffLimit: 2`, the job only gets 3 attempts over ~1 minute —
not enough time for Vault to come up. Job is marked Failed.

The 3 alerts are stale Failed job objects kept around by
`failedJobsHistoryLimit: 3`.

_____________________________________________________________________

[Final Solution]

Two changes to the CronJob spec (applied to both dev and prod):

1. `backoffLimit: 2` → `backoffLimit: 6`

   Gives ~6 retries with exponential backoff (10s, 20s, 40s, 80s,
   160s, 320s ≈ 10 minutes total). Vault stabilizes within 3-5
   minutes after boot, so the later retries will succeed.

   This is the actual fix — gives the job enough breathing room to
   outlast the Vault startup window.

2. `failedJobsHistoryLimit: 3` → `failedJobsHistoryLimit: 1`

   Keeps only 1 failed Job instead of 3. Prevents stale failures
   from piling up alerts. If a job fails, 1 alert fires instead
   of accumulating 3 over time.

Considered and rejected `startingDeadlineSeconds` — it would skip
the queued job entirely if the boot happens hours after the schedule.
I'd rather have a backup attempt that retries and succeeds than a
clean skip with no backup at all.

Cleanup — delete the 3 stale failed jobs to clear current alerts:
```
kubectl delete job etcd-backup-29598120 etcd-backup-29623290 etcd-backup-29624730 -n etcd-backup
```

Files changed:
- kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml
- kubernetes/prod/deployments/apps/etcd-backup/cronjob.yaml

Verified: Pending — next boot cycle will confirm the retry window
is sufficient for Vault to stabilize.

_____________________________________________________________________

[Risk Level] LOW

The backup CronJob works when the cluster is stable — the 3 successful
runs prove that. The failure is a timing issue at boot, and the fix
just gives more retries. No change to the backup logic itself.

_____________________________________________________________________

[References]
- kubernetes/dev/deployments/apps/etcd-backup/cronjob.yaml — CronJob spec
- kubernetes/prod/deployments/apps/etcd-backup/cronjob.yaml — mirrored fix
- disaster-recovery/etcd-backup-s3-validation.md — proves the backup works when it runs
- Vault agent-pre-populate-only: init container mode, not sidecar — fails hard if Vault unreachable
- Kubernetes backoff: exponential with 10s base, capped at 6 min

_____________________________________________________________________

[Re-opened — 2026-05-04]

# Recurrence

Same boot-race failure happened again on 2026-05-04 despite the
backoffLimit: 6 fix from the original resolution.

```
kubectl get job -A
NAMESPACE     NAME                   STATUS     COMPLETIONS   DURATION   AGE
etcd-backup   etcd-backup-29627610   Complete   1/1           103s       3d2h
etcd-backup   etcd-backup-29629050   Complete   1/1           94s        2d2h
etcd-backup   etcd-backup-29630490   Complete   1/1           94s        26h
etcd-backup   etcd-backup-29631930   Failed     0/1           27m        27m
```

Node uptime at investigation time: 38 minutes. The failed job fired
at minute ~1 after boot — same pattern as before.

# Verification — backoffLimit is applied

```
kubectl get cronjob etcd-backup -n etcd-backup -o jsonpath='{.spec.jobTemplate.spec.backoffLimit}'
→ 6

kubectl get cronjob etcd-backup -n etcd-backup -o yaml | grep restart
→ restartPolicy: OnFailure
```

The fix from the original resolution IS deployed. But it didn't help.

# Evidence — only 1 failure counted

```
kubectl get job etcd-backup-29631930 -n etcd-backup -o jsonpath='{.status.failed}'
→ 1
```

Only 1 pod failure recorded by the job controller, despite 6 container
restarts visible in events:

```
Events (from kubectl events -A | grep etcd-backup):
  37m (x6 over 42m)  Normal   Created   Pod/etcd-backup-29631930-b6xl6  Container created
  38m (x6 over 42m)  Normal   Started   Pod/etcd-backup-29631930-b6xl6  Container started
  30m (x10 over 37m) Warning  BackOff   Pod/etcd-backup-29631930-b6xl6  Back-off restarting failed container
  30m                Warning  BackoffLimitExceeded  Job/etcd-backup-29631930  Job has reached the specified backoff limit
```

# Manual re-run — confirms the job itself is healthy

```
kubectl create job --from=cronjob/etcd-backup etcd-backup-debug -n etcd-backup
→ Completed successfully after ~2 minutes (node fully up by then)
```

# Deeper evidence — Loki + kubelet journal + crictl

CRI containers for the failed job already garbage-collected (crictl
ps -a shows no containers from etcd-backup-29631930). Only successful
job containers survive. No way to recover the actual crash output.

## Vault injector timeline (from Loki: {namespace="vault"})

```
22:44:17  vault webhook "connection refused" — injector not listening yet
22:44:20  vault injector starts, handler listening on :8080
22:44:25  cert bundles loaded
22:46:31  [ERROR] "etcdserver: request timed out" — leader election failing
22:47:53  first successful /mutate request — injector STABLE from here
```

Vault injector was NOT ready until ~22:48. The etcd-backup job fired
at 22:44 — 4 minutes before Vault could serve.

## Kubelet journal — vault injector pod (journalctl -u kubelet | grep vault)

```
22:44:18  KillPodSandboxError: Calico plugin failed (delete):
          "Get https://10.96.0.1:443/apis/crd.projectcalico.org/...: dial tcp 10.96.0.1:443: i/o timeout"
```

At boot, the vault injector's old sandbox couldn't even be cleaned up
because Calico couldn't reach the API server — networking stack wasn't
ready. This is earlier than the Loki evidence and shows the full
boot chain: API server → Calico CNI → vault injector pod sandbox →
vault injector ready → etcd-backup can succeed.

## Kubelet journal (journalctl -u kubelet | grep etcd-backup)

Full kubelet backoff sequence for the failed pod:

```
22:44:38  Volumes attached, pod scheduled
22:44:43  CrashLoopBackOff: "back-off 10s"
22:44:44  CrashLoopBackOff: "back-off 10s"
22:44:54  CrashLoopBackOff: "back-off 20s"
22:45:19  CrashLoopBackOff: "back-off 40s"
22:47:31  CrashLoopBackOff: "back-off 1m20s"
22:48:46  CrashLoopBackOff: "back-off 1m20s"
22:48:54  CrashLoopBackOff: "back-off 2m40s"
22:50:07  CrashLoopBackOff: "back-off 2m40s"
22:51:21  CrashLoopBackOff: "back-off 2m40s"
22:51:41  CrashLoopBackOff: "back-off 5m0s"  ← kubelet ceiling
22:51:42  Pod volumes cleaned up, pod deleted by job controller
```

Total window: 22:44:38 → 22:51:41 = ~7 minutes. Kubelet escalated
through 10s → 20s → 40s → 1m20s → 2m40s → 5m0s. Hit 5-minute
ceiling and job controller pulled the plug.

Vault was stable by 22:47:53 — but by then the kubelet was already
at the 1m20s–2m40s backoff range. The container may have actually
succeeded on one of the later restarts, but the kubelet's backoff
state was already poisoned from the early failures.

## Vault injector restarts

```
kubectl get pod -n vault
vault-agent-injector-778c55db9b-zb8bt  1/1  Running  14 (54m ago)  7d22h
```

14 restarts on that pod — it was also crash-looping during boot.
NodeNotReady event at 54m confirms the node itself wasn't stable.

## API server errors during boot window

```
22:44:17  vault.hashicorp.com webhook: dial tcp 10.110.14.29:443: connection refused
22:44:17  metrics.k8s.io: i/o timeout (service unavailable)
22:47:55  metrics.k8s.io: 503 service unavailable
22:48:00  apiservices conflict errors (object modified)
```

The whole control plane was still stabilizing during the job's
retry window.

# Hypothesis — why backoffLimit: 6 didn't work

With `restartPolicy: OnFailure`, the **kubelet** handles container
restarts inside the same pod — these are NOT counted by the job
controller against backoffLimit. The kubelet restarted the container
6 times with its own backoff, all within the single pod. When the
kubelet hit its 5-minute ceiling (CrashLoopBackOff), the job
controller saw 1 pod failure and marked BackoffLimitExceeded.

backoffLimit: 6 was designed to give ~10 minutes of job-controller-
level retries with exponential backoff. But with OnFailure, the job
controller never got to retry — the kubelet burned through all
attempts internally within a single pod.

The original fix was correct in intent but wrong in mechanism.
restartPolicy: OnFailure makes backoffLimit effectively useless
for boot-race scenarios.

# Proposed fix (not yet applied — needs testing)

Switch `restartPolicy` from `OnFailure` to `Never`. This forces the
**job controller** to handle retries by creating a new pod each time,
with exponential backoff (10s, 20s, 40s, 80s, 160s, 320s ≈ 10 min
total). This is what the original fix intended but didn't achieve.

Note: with `Never`, each failed attempt leaves a pod behind (up to
backoffLimit count). These get cleaned up by the job's TTL or
failedJobsHistoryLimit. Acceptable trade-off for reliability.

Status: SUSPENDED

# Root cause

The failure is a boot-stabilization timing issue. When the cluster
boots after being powered off, Kubernetes replays the missed CronJob
immediately — before the control plane dependency chain is ready
(API server → Calico CNI → Vault injector). The etcd-backup job
fires at minute ~1, Vault isn't ready until minute ~4. The original
backoffLimit fix didn't work because `restartPolicy: OnFailure`
makes the kubelet handle retries internally (not the job controller),
burning through all attempts before the cluster stabilizes.

# Solution direction (not yet applied)

Switch `restartPolicy: OnFailure` → `Never` so the job controller
handles retries with proper exponential backoff. Current
`backoffLimit: 6` should be sufficient (~10 min spread). Consider
bumping to 8 for extra margin (~22 min).

This is part of the broader boot-stabilization story — the etcd-backup
job is one symptom, but the underlying pattern (workloads firing
before dependencies are ready after boot) could affect other jobs
or services. A deeper investigation into boot-time sequencing and
readiness gates can be done later.
