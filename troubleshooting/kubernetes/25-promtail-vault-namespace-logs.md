# TS-K8S-025 | 2026-04-11 | OPEN
# Placeholder — identified during DR Task 1 pod kill testing, not yet investigated.
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / Monitoring
Sub-techs: Promtail, Loki, Vault namespace, log collection, DaemonSet
Environment: DEV k8s-dev cluster
Re-opened: No

_____________________________________________________________________

[Issue Description]
Promtail not collecting logs from Vault namespace. Observed during DR Task 1
pod kill testing. Not yet investigated.

Related: DR Task 1 RESULTS — pod kill testing where issue was observed.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Not yet investigated.


# Suspected Root Cause
Unknown. Possible causes to investigate:
  - Vault namespace excluded from Promtail scraping configuration
  - Permission issue preventing Promtail from accessing Vault pod logs
  - Vault pods have special log configuration or path


# More Checks Notes:
N/A — pending investigation.


# Suspected Solution
Pending investigation.


# Test
Not yet performed.

_____________________________________________________________________

[Final Root Cause]
Not yet determined.

_____________________________________________________________________

[Final Solution]
Pending investigation.

Verified: No

_____________________________________________________________________

[Risk Level] Unknown — pending investigation.

_____________________________________________________________________

[References]
- disaster-recovery/task-1-pod-kill/RESULTS.md

_____________________________________________________________________

[Draft Notes]

Investigation checklist:
  [ ] Check Promtail configuration for namespace exclusions
  [ ] Verify Promtail can access Vault pod logs
  [ ] Check if Vault pods have special log configurations
  [ ] Review Loki for any existing Vault namespace logs