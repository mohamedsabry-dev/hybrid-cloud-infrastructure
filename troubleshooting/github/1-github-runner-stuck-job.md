# TS-GH-001 | 2026-02-16 | RESOLVED
_____________________________________________________________________

[Info]
Domain: GitHub Actions
Sub-techs: Self-hosted runner, LaunchDaemon, GitHub CLI
Environment: Mac Mini runner
Re-opened: No

_____________________________________________________________________

[Issue Description]
After Mac Mini reboot, GitHub Actions runner does not start automatically.
Queued jobs get stuck indefinitely and the cancel button in GitHub UI stops working.

  Runner shows offline in Settings > Actions > Runners
  Job status loops: "Waiting for runner" → "About to start" → loops
  Cancel button unresponsive in GitHub UI

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked runner service status and whether the process was alive.

Command:
  cd ~/WorkSpace/actions-runner
  ./svc.sh status
  ps aux | grep Runner.Listener

Output:
  Service not running.
  No Runner.Listener process found.

Checked if the runner was installed as a persistent LaunchDaemon:

Command:
  ls /Library/LaunchDaemons/ | grep actions

Output:
  Nothing — service was never installed as a LaunchDaemon.
  sudo ./svc.sh install was never run.
  Runner only starts when manually launched and does not survive reboots.


# Suspected Root Cause
Runner service not installed as a persistent system service. Without
sudo ./svc.sh install it only runs when manually started and stops on reboot.


# More Checks Notes:
N/A — cause was clear from service status check.


# Suspected Solution
Start the runner manually to unblock jobs, force-cancel stuck jobs via GitHub CLI,
then install the runner as a persistent service to prevent recurrence.


# Test
Started runner service, force-cancelled stuck job, verified runner picks up new jobs.

Command:
  ./svc.sh start
  gh run cancel <run-id> --repo <owner>/<repo>

Result: PASS — runner online, stuck job cancelled, new jobs processing normally.

_____________________________________________________________________

[Final Root Cause]
Runner service was never installed as a persistent LaunchDaemon on the Mac Mini.
sudo ./svc.sh install was not run during initial setup. Runner only starts when
manually launched and does not survive reboots.

_____________________________________________________________________

[Final Solution]
Installed runner as a persistent system service:

  cd ~/WorkSpace/actions-runner
  sudo ./svc.sh install
  sudo ./svc.sh start

  Verify: ./svc.sh status → should show Running + plist path

For stuck jobs — cancel via GitHub CLI (UI cancel button stops working when
runner goes offline):

  # Standard cancel
  gh run cancel <run-id> --repo <owner>/<repo>

  # Force cancel if standard doesn't work
  gh api -X POST /repos/<owner>/<repo>/actions/runs/<run-id>/force-cancel

  # Nuclear — kill and restart runner if still stuck
  ./svc.sh stop
  pkill -9 -f Runner
  ./svc.sh start

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Force-canceling jobs may leave partial workflow state.
Review workflow outputs after force-cancel to confirm nothing was left half-done.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Useful commands:
  gh run view <run-id> --repo <owner>/<repo>   view stuck run details
  gh run list --repo <owner>/<repo>            list recent runs
  ps aux | grep Runner.Listener                check runner process is alive