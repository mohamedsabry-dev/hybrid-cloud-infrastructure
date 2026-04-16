# TS-K8S-021 | 2026-04-11 | RESOLVED
# REAL INCIDENT — unplanned production failure (worker VM crash exposed remediation bug).
_____________________________________________________________________

[Info]
Author:
Domain: Kubernetes / Proxmox
Sub-techs: Remediation pod, proxmoxer Python library, Proxmox API, VM status,
           CrashLoopBackOff, self-healing, exception handling
Environment: PROD production cluster | remediation namespace | VM 1021 (k8s-worker2)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Remediation pod crashes with Python exception when attempting to reboot a VM
that is already stopped. Pod enters CrashLoopBackOff instead of recovering the node.

  Traceback:
  proxmoxer.core.ResourceException: 500 Internal Server Error: VM 1021 not running

  File remediation.py line 118:
    proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.reboot.post()

Impact: self-healing mechanism fails completely. Node remains down, pods stay
in Unknown/Terminating state, manual intervention required.

Related tickets:
  TS-PVE-014 — worker VM crash (the incident that exposed this bug)
  TS-K8S-022 — cascading failures from worker node loss

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Traced the crash through the exception and Proxmox logs.

Current remediation logic (flawed):
  1. Check node health every 120 seconds
  2. If node NotReady → call reboot_vm(vmid)
  3. reboot_vm() calls: proxmox.nodes(NODE).qemu(vmid).status.reboot.post()

Problem: code assumes VM is running but unresponsive. If VM is already stopped
(crashed, powered off), Proxmox API returns 500 — cannot reboot a stopped VM.

Proxmox API behaviour by VM state:
  Running  → reboot.post() succeeds
  Paused   → reboot.post() succeeds
  Stopped  → reboot.post() returns 500 "VM not running"

Proxmox daemon logs confirming the sequence:
  10:40:51  pvedaemon: requesting reboot of VM 1021
  10:41:51  pvedaemon: VM 1021 qga command failed - got timeout
  10:41:51  pvedaemon: VM quit/powerdown failed
  10:47:11  pvedaemon: VM 1021 qmp command failed - VM 1021 not running
  10:47:11  pvedaemon: VM 1021 not running

Why pod enters CrashLoopBackOff:
  1. Remediation detects unhealthy node
  2. Calls reboot API → ResourceException raised
  3. Exception not caught → Python process exits with error
  4. Kubernetes restarts pod
  5. Pod starts, checks again, same error → crash again
  6. Exponential backoff begins (CrashLoopBackOff)


# Suspected Root Cause
Remediation script calls reboot API without first checking VM status.
No exception handling for stopped VM scenario — unhandled exception exits
Python process, triggering repeated pod restarts.


# More Checks Notes:
N/A — exception trace and Proxmox logs confirmed the exact failure sequence.


# Suspected Solution
Add get_vm_status() check before taking action. Handle stopped, running, and
paused states correctly. Add exception handling so pod does not crash on error.


# Test
Applied fix to configmap.yaml (dev and prod), redeployed remediation pod.
Simulated stopped VM scenario:

Command:
  qm stop 1021
  kubectl logs -n remediation -f remediation-<pod>

Result: PASS — logs show "VM 1021 is stopped, starting..." instead of exception.
Pod did not crash. VM started successfully.

_____________________________________________________________________

[Final Root Cause]
Remediation script assumed VM was running but unresponsive and called
reboot API unconditionally. When VM was stopped (actual crash), Proxmox
returned 500 "VM not running". The exception was not caught — Python process
exited, triggering repeated pod restarts and CrashLoopBackOff. Self-healing
mechanism was itself broken by the scenario it was meant to handle.

_____________________________________________________________________

[Final Solution]
Added get_vm_status() function and status-aware remediation logic.

  def get_vm_status(proxmox, vmid):
      status = proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.current.get()
      return status.get("status", "unknown")

  Modified reboot_vm() to check status first:
    stopped  → calls start.post()
    running  → calls reboot.post()
    paused   → calls resume.post() then reboot.post()
    unknown  → attempts start.post() with exception handling

  Exception handling added — pod logs error and continues monitoring
  instead of crashing:
    except ResourceException as e:
      if "not running" in str(e):
        logging.warning(f"VM not running, attempting start")
        proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.start.post()
      else:
        raise
    except Exception as e:
      logging.error(f"Remediation failed: {e}")
      # Don't crash — log and continue monitoring

Files changed:
  kubernetes/dev/deployments/apps/remediation/configmap.yaml
  kubernetes/prod/deployments/apps/remediation/configmap.yaml

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Code change to remediation script requires container image rebuild
and redeployment. No infrastructure impact.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Proxmox API reference for VM state management:
  GET  /nodes/{node}/qemu/{vmid}/status/current  → returns status: running|stopped|paused
  POST /nodes/{node}/qemu/{vmid}/status/start     → start stopped VM
  POST /nodes/{node}/qemu/{vmid}/status/reboot    → reboot running VM
  POST /nodes/{node}/qemu/{vmid}/status/shutdown  → stop VM gracefully
  POST /nodes/{node}/qemu/{vmid}/status/stop      → stop VM force

Current remediation config:
  Check interval:     120s
  Pod failure threshold: 70%
  Monitored nodes:    k8s-worker1, k8s-worker2, k8s-worker3

Workaround until fix deployed:
  Monitor for CrashLoopBackOff in remediation namespace.
  If occurs:
    qm start <vmid>
    kubectl delete pod -n remediation remediation-<pod-name>