# TS-PVE-014 | 2026-04-11 | UNRESOLVED

> **REAL INCIDENT** — This case occurred during an unplanned production failure (VM crash after autostart), not planned DR testing. Documented before DR test phase began.

## 1. Context
- System: Proxmox VE VM autostart
- Environment: pve-prod
- Related components: VM 1021 (k8s-worker2), QEMU, Proxmox autostart sequence

## 2. Issue
- Symptom: Worker VM 1021 started successfully during autostart sequence but crashed/froze within approximately 1 minute, with no indication of cause in available logs.
- Error:
```
# Proxmox task log
Apr 11 10:39:42  pve-prod  root@pam  VM 1021 - Start  OK
Apr 11 10:40:51  pve-prod  k8s-pve@pve  VM 1021 - Reboot  Error: VM quit/powerdown failed

# journalctl -u pvedaemon
Apr 11 10:41:51 pve-prod pvedaemon[9417]: VM 1021 qga command failed - VM 1021 qga command 'guest-shutdown' failed - got timeout
Apr 11 10:41:51 pve-prod pvedaemon[1352]: <k8s-pve@pve!remediation> end task [...]: VM quit/powerdown failed
```

**Impact:** Kubernetes worker node NotReady, pods on that node entered Unknown/Terminating state, cascading failures to applications depending on that node.

## 3. Analysis

### Timeline Reconstruction

```
10:32:32 - 10:37:40  Proxmox autostart: LXC containers (CT 2001-2006)
10:38:39 - 10:38:50  Proxmox autostart: K8s master VMs (1010, 1011, 1012)
10:39:42 - 10:39:45  Proxmox autostart: K8s worker VMs (1020, 1021, 1022)
     ↓
     VM 1021 started successfully (task status: OK)
     ↓
     ~1 minute passes - VM running
     ↓
     VM 1021 crashes/freezes (no external trigger)
     ↓
10:40:51             Remediation pod detects worker2 NotReady
10:40:51             Remediation attempts reboot via Proxmox API
10:41:51             Reboot fails - guest agent not responding (VM already dead)
     ↓
     VM remains stopped, no auto-recovery
```

### What Was Checked

**Proxmox task logs:**
```bash
cat /var/log/pve/tasks/index | grep 1021
# Shows successful start at 10:39:45, failed reboot at 10:40:51
```

**Proxmox daemon logs:**
```bash
journalctl -u pvedaemon --since "today" | grep 1021
# Shows guest-shutdown timeout, VM not running errors
```

**Kubernetes node status:**
```bash
kubectl get nodes
# k8s-worker2.lab.local   NotReady   <none>   15d   v1.35.3
```

**VM kernel logs:** Not available - VM was stopped, no crash dump captured

### What Was NOT Found

| Investigation | Result |
|---------------|--------|
| Proxmox host dmesg | No OOM killer, no hardware errors |
| VM kernel logs | Not accessible - VM stopped |
| QEMU process errors | None logged |
| Storage errors | None logged |
| Network issues | Other VMs on same host working |

### Suspected Causes (Unconfirmed)

1. **OOM (Out of Memory)** - VM may have exhausted memory during boot
2. **Kernel panic** - Rocky Linux kernel issue during service startup
3. **Storage I/O hang** - NFS or local storage timeout
4. **Race condition** - Services starting before dependencies ready

Cannot confirm any of these without kernel logs from inside the VM.

## 4. Root Cause
> **UNDETERMINED** - VM crashed within ~1 minute of successful boot. No evidence available to identify the specific cause. The crash occurred before remediation attempted any action, ruling out remediation as the cause.

## 5. Solution
> **Manual intervention required** - Started VM manually via Proxmox GUI/CLI after confirming it was stopped.

```bash
# Manual start
qm start 1021
```

VM started successfully and remained stable after manual start.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Manual start is safe, but underlying cause may recur

## 7. Impact After Fix
- Observed: VM running stable after manual start
- Kubernetes worker2 returned to Ready state
- Pods rescheduled and recovered
- No recurrence observed during session

## 8. Notes

### Why Remediation Didn't Help

The remediation pod detected the issue correctly but:
1. VM was already stopped (not just unresponsive)
2. Remediation called `reboot` API on stopped VM → 500 error
3. Remediation crashed instead of recovering

See: TS-K8S-021 for remediation improvement needed.

### Prevention Considerations

| Approach | Benefit | Effort |
|----------|---------|--------|
| Enable VM watchdog | Auto-reboot on hang | Medium |
| Serial console logging | Capture kernel panics | Low |
| Increase VM memory | Prevent OOM | Low |
| Add VM health monitoring | Earlier detection | Medium |

### Commands for Future Investigation

If this recurs, capture before manual intervention:
```bash
# On Proxmox host
qm status 1021 --verbose
dmesg | tail -100
journalctl -u pve* --since "10 minutes ago"

# If VM is frozen but not stopped
qm monitor 1021
# Then: info status, info cpus, info mem

# Check QEMU process
ps aux | grep 1021
```

### Related Cases
- TS-K8S-021: Remediation pod API error handling
- TS-K8S-022: Cascading pod failures from worker node loss
- TS-PVE-012: VM autostart timeout (NFS related - different root cause)

## 9. Workaround (if any)
> Monitor for NotReady nodes and manually start VMs if remediation fails. Long-term: improve remediation to handle stopped VMs by using `start` instead of `reboot`.
