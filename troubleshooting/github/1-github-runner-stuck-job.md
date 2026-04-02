# Case 1: GitHub Actions Runner - Stuck Job After Reboot

## Status: RESOLVED
## Date: 2026-03

---

## Issue
After Mac Mini reboot, the GitHub Actions self-hosted runner doesn't start automatically. Jobs triggered during downtime get stuck in "Waiting for a runner to pick up this job..." state and won't cancel via the web UI.

## Symptoms
- Job shows: "Job is about to start running on the runner"
- Status loops between "Waiting for runner" and "About to start"
- Cancel button in GitHub UI doesn't work
- Runner shows as offline in Settings > Actions > Runners

## Root Cause
The runner service wasn't configured to start on boot, or the service failed to start after reboot.

## Solution

### 1. Check Runner Service Status
```bash
cd ~/WorkSpace/actions-runner
./svc.sh status
```

### 2. Start the Runner Service
```bash
./svc.sh start
```

### 3. Force Cancel Stuck Job
If cancel button doesn't work in UI, use GitHub CLI:

```bash
# Get run ID from the Actions URL (e.g., /actions/runs/22073570387)
gh run cancel <run-id> --repo <owner>/<repo>
```

If still stuck, force cancel via API:
```bash
gh api -X POST /repos/<owner>/<repo>/actions/runs/<run-id>/force-cancel
```

### 4. Nuclear Option - Kill and Restart Runner
```bash
cd ~/WorkSpace/actions-runner
./svc.sh stop
pkill -9 -f Runner
./svc.sh start
```

## Prevention

### Install Runner as Service (Persistent)
```bash
cd ~/WorkSpace/actions-runner
sudo ./svc.sh install
sudo ./svc.sh start
```

This ensures the runner starts automatically after every reboot.

### Verify Service is Installed
```bash
./svc.sh status
# Should show: "Running" and the plist path
```

## Related Commands

```bash
# View stuck run details
gh run view <run-id> --repo <owner>/<repo>

# List recent runs
gh run list --repo <owner>/<repo>

# Check runner process
ps aux | grep Runner.Listener
```

## Date Recorded
2026-02-16
