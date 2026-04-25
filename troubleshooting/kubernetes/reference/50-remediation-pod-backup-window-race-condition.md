# TS-K8S-050 | 2026-04-24 | WORKAROUND APPLIED | IMPROVEMENT
_____________________________________________________________________

[Info]
Domain: Kubernetes / Remediation Pod / Proxmox Backup
Sub-techs: remediation pod, vzdump backup job, Proxmox API, VM lock state
Environment: dev + prod
Re-opened: No

_____________________________________________________________________

[Issue Description]
NOT YET AN INCIDENT — preventive ticket raised from TS-PVE-015 investigation.

During TS-PVE-015 analysis, identified a potential race condition: if the
remediation pod's 5-minute health check fires during the vzdump "suspend vm
to make snapshot" phase, the worker VM will appear unresponsive. The
remediation pod could interpret this as a node failure and attempt to
reboot/reset/restore the VM via Proxmox API.

During backup, Proxmox places a lock on the VM. The remediation pod's API
call would likely get an error back, but the current behavior on error
response needs to be reviewed:
- Does it retry immediately or back off?
- Does it escalate to force-reset/restore on API error?
- Could it interfere with the backup lock state?

This is a time bomb: the backup window and health check interval are both
periodic. Eventually they will collide.

_____________________________________________________________________

[Analysis]
# TODO: Review remediation pod behavior
# 1. Read configmap.yaml — check what happens on Proxmox API error response
# 2. Check if remediation distinguishes "VM locked" from "VM unresponsive"
# 3. Check escalation logic: reboot → reset → restore — does API error
#    on reboot trigger escalation to reset/restore?
# 4. Review vzdump lock behavior — does Proxmox API return a specific error
#    code when VM is locked for backup?

_____________________________________________________________________

[Potential Solutions]
1. Add backup-awareness to remediation: skip action if vzdump is running
   (check via Proxmox API for active backup tasks before acting)
2. Add a "maintenance window" config to remediation pod (e.g. skip checks
   between 21:00-21:15 when backup runs)
3. Handle Proxmox "VM locked" error gracefully — do not escalate, wait
   and retry after lock clears
4. Reduce remediation aggressiveness: add longer cooldown between
   detection and action to ride out brief suspends

_____________________________________________________________________

[Final Root Cause]
PENDING — preventive investigation, no incident yet

_____________________________________________________________________

[Final Solution]
WORKAROUND APPLIED — k8s nodes excluded from vzdump backup (TS-PVE-020), eliminating
the collision path on dev. Dev remediation also hardened with 3-min confirmation delay.
Prod still has k8s nodes in backup but hardware handles IO without cluster impact.

_____________________________________________________________________

[Risk Level] LOW — collision path eliminated on dev, reduced on prod

_____________________________________________________________________

[References]
- Parent: TS-PVE-015 (thermal shutdown during backup — investigation surfaced this risk)
- Related: TS-PVE-014 (remediation pod triggered reboot during boot — similar race condition pattern)
- Related: TS-PVE-020 (vzdump backup destabilizes k8s — k8s nodes excluded from dev backup)
- Code: kubernetes/dev/deployments/apps/remediation/configmap.yaml (remediation logic)
