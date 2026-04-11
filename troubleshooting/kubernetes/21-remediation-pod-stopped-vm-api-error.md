# TS-K8S-021 | 2026-04-11 | RESOLVED

## 1. Context
- System: Kubernetes remediation pod (custom self-healing)
- Environment: Production cluster (prod)
- Related components: remediation pod, Proxmox API (proxmoxer), VM 1021

## 2. Issue
- Symptom: Remediation pod crashes with Python exception when attempting to reboot a VM that is already stopped. Pod enters CrashLoopBackOff instead of recovering the node.
- Error:
```python
--- Health check at 2026-04-11 08:58:34 ---
k8s-worker1.lab.local: Healthy
k8s-worker2.lab.local: UNHEALTHY! (Node NotReady)
[Attempt 1] Remediating k8s-worker2.lab.local (VM 1021)
  -> Rebooting VM 1021
Traceback (most recent call last):
  File "/scripts/remediation.py", line 242, in <module>
    main()
  File "/scripts/remediation.py", line 237, in main
    remediate(proxmox, node_name, vmid)
  File "/scripts/remediation.py", line 198, in remediate
    reboot_vm(proxmox, vmid)
  File "/scripts/remediation.py", line 118, in reboot_vm
    proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.reboot.post()
  File "/usr/local/lib/python3.11/site-packages/proxmoxer/core.py", line 173, in post
    return self(args)._request("POST", data=data)
  File "/usr/local/lib/python3.11/site-packages/proxmoxer/core.py", line 148, in _request
    raise ResourceException(
proxmoxer.core.ResourceException: 500 Internal Server Error: VM 1021 not running
```

**Impact:** Self-healing mechanism fails completely. Node remains down, pods stay in Unknown/Terminating state, manual intervention required.

## 3. Analysis

### Current Remediation Logic (Flawed)

```
1. Check node health every 120 seconds
2. If node NotReady → call reboot_vm(vmid)
3. reboot_vm() calls: proxmox.nodes(NODE).qemu(vmid).status.reboot.post()
```

**Problem:** The code assumes the VM is running but unresponsive. If the VM is already stopped (crashed, powered off), the Proxmox API returns 500 error because you cannot reboot a stopped VM.

### Proxmox API Behavior

| VM State | reboot.post() Result |
|----------|---------------------|
| Running | Success - VM reboots |
| Paused | Success - VM reboots |
| Stopped | **500 Error - VM not running** |

### Evidence from Proxmox Logs

```bash
# journalctl -u pvedaemon
Apr 11 10:40:51 pve-prod pvedaemon[1352]: <k8s-pve@pve!remediation> starting task [...]:qmreboot:1021
Apr 11 10:40:51 pve-prod pvedaemon[9417]: requesting reboot of VM 1021
Apr 11 10:41:51 pve-prod pvedaemon[9417]: VM 1021 qga command failed - got timeout
Apr 11 10:41:51 pve-prod pvedaemon[1352]: end task [...]: VM quit/powerdown failed

# Later attempts show VM not running
Apr 11 10:47:11 pve-prod pvedaemon[1351]: VM 1021 qmp command failed - VM 1021 not running
Apr 11 10:47:11 pve-prod pvedaemon[1351]: VM 1021 not running
```

### Why Pod Enters CrashLoopBackOff

1. Remediation detects unhealthy node
2. Calls reboot API → Exception raised
3. Exception not caught → Python process exits with error
4. Kubernetes restarts pod
5. Pod starts, checks again, same error → crash again
6. Exponential backoff begins (CrashLoopBackOff)

## 4. Root Cause
> Remediation script calls `reboot` API without first checking VM status. Proxmox cannot reboot a stopped VM, returning 500 error. The script has no exception handling for this case, causing the pod to crash.

## 5. Solution
> Modify remediation script to check VM status before action and handle stopped VMs appropriately.

### Proposed Code Fix

**File: `/scripts/remediation.py` (or wherever the script lives)**

```python
def get_vm_status(proxmox, vmid):
    """Get current VM status from Proxmox"""
    try:
        status = proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.current.get()
        return status.get('status', 'unknown')
    except Exception as e:
        logging.error(f"Failed to get VM {vmid} status: {e}")
        return 'unknown'

def remediate_vm(proxmox, vmid):
    """Remediate VM based on its current status"""
    status = get_vm_status(proxmox, vmid)
    logging.info(f"VM {vmid} current status: {status}")

    if status == 'stopped':
        logging.info(f"VM {vmid} is stopped, starting...")
        proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.start.post()
    elif status == 'running':
        logging.info(f"VM {vmid} is running but node unhealthy, rebooting...")
        proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.reboot.post()
    elif status == 'paused':
        logging.info(f"VM {vmid} is paused, resuming then rebooting...")
        proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.resume.post()
        time.sleep(5)
        proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.reboot.post()
    else:
        logging.warning(f"VM {vmid} in unknown state '{status}', attempting start...")
        try:
            proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.start.post()
        except Exception as e:
            logging.error(f"Failed to start VM {vmid}: {e}")
```

### Add Exception Handling

```python
def reboot_vm(proxmox, vmid):
    """Reboot VM with proper error handling"""
    try:
        remediate_vm(proxmox, vmid)
    except ResourceException as e:
        if "not running" in str(e):
            logging.warning(f"VM {vmid} not running, attempting start instead")
            proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.start.post()
        else:
            raise
    except Exception as e:
        logging.error(f"Remediation failed for VM {vmid}: {e}")
        # Don't crash - log and continue monitoring
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Code change to remediation script, requires rebuild of container image and redeployment

## 7. Impact After Fix
- Remediation now handles both running (reboot) and stopped (start) VMs
- No more CrashLoopBackOff on stopped VM scenarios
- Automatic recovery without manual intervention

**Fix Applied:**
- `kubernetes/dev/deployments/apps/remediation/configmap.yaml`
- `kubernetes/prod/deployments/apps/remediation/configmap.yaml`

Added `get_vm_status()` function that calls Proxmox API before taking action:
```python
def get_vm_status(proxmox, vmid):
    status = proxmox.nodes(PROXMOX_NODE).qemu(vmid).status.current.get()
    return status.get("status", "unknown")
```

Modified `reboot_vm()` to check status first:
- `stopped` → calls `start_vm()`
- `running` → calls reboot
- `paused` → resume then reboot
- `unknown` → attempts start

## 8. Notes

### Proxmox API Reference

```bash
# Check VM status
GET /nodes/{node}/qemu/{vmid}/status/current
# Returns: { "status": "running|stopped|paused", ... }

# Start stopped VM
POST /nodes/{node}/qemu/{vmid}/status/start

# Reboot running VM
POST /nodes/{node}/qemu/{vmid}/status/reboot

# Stop VM (graceful)
POST /nodes/{node}/qemu/{vmid}/status/shutdown

# Stop VM (force)
POST /nodes/{node}/qemu/{vmid}/status/stop
```

### Testing the Fix

```bash
# Simulate stopped VM scenario
qm stop 1021

# Run remediation manually or wait for check interval
kubectl logs -n remediation -f remediation-<pod>

# Should see: "VM 1021 is stopped, starting..."
# Instead of: Exception and crash
```

### Current Remediation Config

```
Check interval: 120s
Pod failure threshold: 70%
Monitored nodes: k8s-worker1, k8s-worker2, k8s-worker3
```

### Related Cases
- TS-PVE-014: Worker VM crash (the incident that exposed this bug)
- TS-K8S-022: Cascading failures from worker node loss

## 9. Workaround (if any)
> Until fix is implemented: Monitor for CrashLoopBackOff in remediation namespace. If occurs, manually start the stopped VM via Proxmox, then delete the remediation pod to reset the crash counter.

```bash
# Manual recovery
qm start 1021
kubectl delete pod -n remediation remediation-<pod-name>
```
