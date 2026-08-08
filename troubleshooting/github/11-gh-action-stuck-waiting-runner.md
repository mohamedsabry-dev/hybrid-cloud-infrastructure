# TS Case 11 — GitHub Actions Job Stuck "Waiting for a runner to pick up this job" (Label Mismatch)

## Environment
- Repo: `mohamedsabry-dev/hybrid-cloud-infrastructure`
- Workflow: `[DEV] jenkins - Full Setup` (`dev-jenkins-full-setup.yml`)
- Self-hosted runner: `dev-local-runner` (Linux, X64)
- Runner host: `local-runner` (recently FreeIPA-joined, hostname now `local-runner.lab.local`)

## Symptom
Workflow job `3. Setup Jenkins Deployment` hangs indefinitely on:
```
Requested labels: dev-local-runner
Job defined at: mohamedsabry-dev/hybrid-cloud-infrastructure/.github/workflows/dev-jenkins-full-setup.yml@refs/heads/dev
Waiting for a runner to pick up this job...
```
Meanwhile the Repo → Actions → Runners dashboard shows `dev-local-runner` as **Idle** (green), not offline or busy — the runner appears healthy but the job never starts.

## Diagnostic Steps
1. **Ruled out runner process health** — checked the service directly on the runner host rather than trusting the dashboard status alone:
   ```bash
   sudo systemctl status actions.runner.*
   ```
   → `active (running)`, no crashes, consistent uptime.

2. **Checked live logs for actual polling activity:**
   ```bash
   journalctl -u actions.runner.* -f
   ```
   → Confirmed `√ Connected to GitHub`, `Listening for Jobs`, repeating on schedule with no gaps or errors. Ruled out a dead/hung listener loop.

3. **Restarted the runner service and rebooted the runner host entirely** as a first-pass fix.
   → No change. Job remained queued after both.

4. **Checked for a job silently already occupying the runner** (self-hosted runners are single-job by default):
   ```bash
   ps aux | grep Runner.Worker
   ```
   → No worker process running; runner genuinely idle. Ruled out "runner busy with another job."

5. **Checked the runner's actual registered labels** — the step that identified the real cause:
   ```bash
   cat /opt/actions-runner/.runner
   ```
   → Labels registered: `self-hosted, Linux, X64, dev`. The label `dev-local-runner` — which the workflow's `runs-on:` requests — was **not** present. GitHub Actions runner name and runner label are separate concepts; the runner was *named* `dev-local-runner` in the dashboard, but that name is not automatically a label.

## Root Cause
GitHub Actions matches jobs to self-hosted runners by **label set**, not by runner name. The workflow specified:
```yaml
runs-on: dev-local-runner
```
but the runner's actual configured labels were `self-hosted, Linux, X64, dev` — no `dev-local-runner` label existed on any runner in the repo. The runner was fully healthy, connected, and listening the entire time, but had nothing matching the job's required label, so GitHub queued the job indefinitely with no error or timeout surfaced to the user — it simply waits forever by design.

The dashboard's "Idle" status describes runner health/connectivity, not label-match eligibility, which is why the runner looking idle was misleading during initial triage.

## Resolution
Added the missing label to the runner's registration:
```bash
cd /opt/actions-runner
sudo ./svc.sh stop
./config.sh remove --token <removal-token-from-GitHub-Settings>
./config.sh --url https://github.com/mohamedsabry-dev/hybrid-cloud-infrastructure \
    --token <new-registration-token> \
    --labels self-hosted,Linux,X64,dev,dev-local-runner
sudo ./svc.sh start
```
Both tokens obtained from Repo → Settings → Actions → Runners → runner → reconfigure/remove.

After re-registration with the correct label set, the queued job picked up immediately.

## Prevention
- When creating a new self-hosted runner, decide the label set deliberately and confirm it matches every workflow's `runs-on:` value **before** relying on it — don't assume the runner's display name doubles as a label.
- When a job hangs on "Waiting for a runner to pick up this job" with an apparently healthy/idle runner showing in the dashboard, check labels (`cat /opt/actions-runner/.runner` on the host, or the runner's label chips in the dashboard) **before** spending time on service restarts or reboots — a label mismatch produces identical symptoms to a genuinely stuck runner, but reboot/restart cannot fix it.
- Consider standardizing on `runs-on:` values that exactly match one of the runner's default labels (`self-hosted`, OS, arch) plus one clear custom label, to avoid this kind of silent mismatch across environments (dev/prod runners visible in the same runner list use different label sets — `prod-local-runner` shown offline in the same dashboard is a separate risk to double-check when prod work resumes).

## Cross-References
- None yet — first incident of this specific failure mode logged.