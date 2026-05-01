# TS-K8S-057 | 2026-05-01 | RESOLVED
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
Re-opened: No

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
