# TS-GH-001 | 2026-02-16 | RESOLVED

## 1. Context
- System: GitHub Actions / Self-hosted runner
- Environment: Mac Mini runner
- Related components: GitHub Actions workflows, LaunchDaemon service

## 2. Issue
- Symptom: After Mac Mini reboot, runner doesn't start automatically. Jobs get stuck.
- Error:
```
Job is about to start running on the runner...
```
Status loops between "Waiting for runner" and "About to start". Cancel button in GitHub UI doesn't work.

**Observed behavior:**
- Runner shows as offline in Settings > Actions > Runners
- Jobs queued during downtime stuck indefinitely
- Cancel button unresponsive

## 3. Analysis

**Check 1: Runner service status**
```bash
cd ~/WorkSpace/actions-runner
./svc.sh status
```
Finding: Service not running after reboot.

**Check 2: Is runner process alive?**
```bash
ps aux | grep Runner.Listener
```
Finding: No Runner.Listener process running.

**Check 3: Was service installed as persistent?**
```bash
ls /Library/LaunchDaemons/ | grep actions
```
Finding: Service not installed as LaunchDaemon (wasn't using `sudo ./svc.sh install`).

## 4. Root Cause
> The runner service wasn't configured to start on boot. Without `sudo ./svc.sh install`, the runner only runs when manually started and doesn't survive reboots.

## 5. Solution
> Install runner as system service and force-cancel stuck jobs.

**Location:** Mac Mini runner machine

**Step 1: Start the runner service**
```bash
cd ~/WorkSpace/actions-runner
./svc.sh start
```

**Step 2: Force cancel stuck job**

If cancel button doesn't work in UI, use GitHub CLI:
```bash
# Get run ID from the Actions URL (e.g., /actions/runs/22073570387)
gh run cancel <run-id> --repo <owner>/<repo>
```

If still stuck, force cancel via API:
```bash
gh api -X POST /repos/<owner>/<repo>/actions/runs/<run-id>/force-cancel
```

**Step 3: Nuclear option - kill and restart runner**
```bash
cd ~/WorkSpace/actions-runner
./svc.sh stop
pkill -9 -f Runner
./svc.sh start
```

**Prevention - install as persistent service:**
```bash
cd ~/WorkSpace/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
```

**Verification:**
```bash
./svc.sh status
# Should show: "Running" and the plist path
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Force-canceling jobs may leave partial state - review workflow outputs

## 7. Impact After Fix
- Observed: Runner starts automatically on reboot
- Jobs process correctly
- No new issues caused

## 8. Notes

**Useful commands:**
```bash
# View stuck run details
gh run view <run-id> --repo <owner>/<repo>

# List recent runs
gh run list --repo <owner>/<repo>

# Check runner process
ps aux | grep Runner.Listener
```

## 9. Workaround (if any)
> Manually start runner after each reboot: `cd ~/WorkSpace/actions-runner && ./svc.sh start`
