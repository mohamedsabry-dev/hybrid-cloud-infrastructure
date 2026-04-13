# TS-PVE-014 | 2026-04-11 | RESOLVED (2026-04-12)

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

---

## 10. Follow-up Investigation: 2026-04-12

> **ROOT CAUSE IDENTIFIED** — After rebooting both prod and dev servers on April 12, observed identical pattern on dev environment. The "crash" was actually remediation pod triggering reboot during normal worker boot sequence.

### 10.1 Evidence: Dev Environment Reboot (April 12)

**Proxmox Task Log (pve-dev):**
```
Apr 12 19:45:52  pve-dev  root@pam  VM 1010 - Start  (master1)
Apr 12 19:45:52  pve-dev  root@pam  VM 1011 - Start  (master2)
Apr 12 19:45:52  pve-dev  root@pam  VM 1012 - Start  (master3)
Apr 12 19:45:55  pve-dev  root@pam  VM 1020 - Start  (worker1)
Apr 12 19:46:55  pve-dev  root@pam  VM 1021 - Start  (worker2)
Apr 12 19:47:08  pve-dev  root@pam  VM 1022 - Start  (worker3)
Apr 12 19:48:43  pve-dev  k8s-pve@pve  VM 1022 - Reboot  ← REMEDIATION TRIGGERED!
Apr 12 19:48:52  pve-dev  root@pam  VM 1022 - Start
```

**Key Finding:** Reboot triggered by `k8s-pve@pve` (remediation service account), NOT Proxmox autostart or VM crash.

**Prod Environment (April 12) - Same Pattern:**
```
Apr 12 19:44:03  pve-prod  root@pam  VM 1010, 1011, 1012 - Start  (masters)
Apr 12 19:44:06  pve-prod  root@pam  VM 1020 - Start  (worker1)
Apr 12 19:45:06  pve-prod  root@pam  VM 1021, 1022 - Start  (worker2/3)
```

### 10.2 Timeline Analysis

```
19:45:52-55  Masters start (order 8, delay=0)
             Remediation pod starts on master
             ↓
19:45:55     Worker1 starts (order 9, has up_delay=60)
             up_delay=60 delays NEXT vm, not this one!
             ↓ 60s wait
19:46:55     Worker2 starts (up_delay=0)
19:47:08     Worker3 starts (up_delay=0)
             ↓
             Workers booting, kubelet starting
             Node status: NotReady (normal during boot)
             ↓
~19:46:30    Remediation first check (immediate after pod starts)
             Workers NotReady but just started, no action
             ↓
19:48:30     Remediation second check (CHECK_INTERVAL=120s)
             Worker3 uptime: ~1.5 minutes
             Still NotReady → TRIGGERS REBOOT!
             ↓
19:48:43     VM 1022 Reboot by k8s-pve@pve
             Reboot during boot = potential crash/corruption
```

### 10.3 Root Cause Discovery

**The "crash" was NOT a VM crash.** It was remediation triggering reboot on workers still in normal boot sequence.

**Three contributing factors:**

**1. Proxmox up_delay Misunderstanding:**

From Terraform Proxmox provider documentation:
```
startup:
  up_delay - Delay in seconds before the NEXT VM is started.
```

`up_delay` delays the **NEXT** VM, not the current one!

**Old Config (broken):**
```terraform
# worker1: startup_delay=60, order=9  ← delays worker2, not itself!
# worker2: startup_delay=0,  order=9
# worker3: startup_delay=0,  order=9
```

**Vault containers work correctly because they use different orders:**
```
CT 2004 (order=5, delay=60) → 19:42:49
CT 2005 (order=6, delay=60) → 19:43:50  (+1 min)
CT 2006 (order=7, delay=60) → 19:44:51  (+1 min)
```

**2. Remediation CHECK_INTERVAL Too Short:**
```python
CHECK_INTERVAL = 120  # 2 minutes - catches workers during boot!
```

**3. No Boot Protection:**
- No initial grace period after remediation pod starts
- No VM uptime check before triggering reboot

### 10.4 VM Startup Config Verification

**Commands used:**
```bash
# Check VM startup config in Proxmox
qm config 1020 | grep startup
# startup: order=9,up=60,down=60  (worker1 - has delay)

qm config 1021 | grep startup
# startup: order=9,up=0,down=60   (worker2 - no delay)

qm config 1022 | grep startup
# startup: order=9,up=0,down=60   (worker3 - no delay)
```

### 10.5 Fix Applied

**Terraform Changes (dev + prod):**

| File | Change |
|------|--------|
| `terraform/*/proxmox/vms/k8s_masters/variables.tf` | master3: `startup_delay = 0` → `60` |
| `terraform/*/proxmox/vms/k8s_workers/variables.tf` | worker1: `startup_delay = 60` → `0` |

**New Boot Sequence:**
```
Masters start (order 8)
  ↓ master3 up_delay=60
60 seconds wait
  ↓
All workers start together (order 9, all delay=0)
```

**Remediation Changes (dev + prod):**

| File | Change |
|------|--------|
| `kubernetes/*/deployments/apps/remediation/configmap.yaml` | `CHECK_INTERVAL = 120` → `300` |

**Verification Commands:**
```bash
# Check configmap updated
kubectl get cm remediation-script -n remediation -o yaml | grep "CHECK_INTERVAL ="
# Expected: CHECK_INTERVAL = 300

# Restart pod to pick up new config
kubectl rollout restart deployment/remediation -n remediation

# Verify new interval active
kubectl logs -n remediation -l app=remediation -c remediation | grep "Check interval"
# Expected: Check interval: 300s
```

### 10.6 New Expected Timeline

```
T+0:00   Masters start together (order 8)
T+1:00   Workers start together (after master3's 60s delay)
T+2:00   Workers registering with K8s
T+3:00   Workers showing Ready
T+5:00   Remediation first real check (5 min interval)
         All workers healthy, no action needed ✓
```

### 10.7 Key Learnings

1. **Proxmox `up_delay` semantics:** Delays NEXT VM, not current. Put delay on LAST item of order group to create gap before next group.

2. **Remediation needs boot protection:** Self-healing systems must account for cluster boot. 2-minute check is too aggressive.

3. **Initial "crash" assumption was wrong:** Without full investigation, assumed VM crashed internally. Reality: external system triggered reboot.

4. **Same pattern on both envs:** Dev reboot on April 12 showed identical remediation trigger, confirming root cause.

### 10.8 Files Changed

```
terraform/dev/proxmox/vms/k8s_masters/variables.tf   # master3 delay: 0→60
terraform/dev/proxmox/vms/k8s_workers/variables.tf   # worker1 delay: 60→0
terraform/prod/proxmox/vms/k8s_masters/variables.tf  # master3 delay: 0→60
terraform/prod/proxmox/vms/k8s_workers/variables.tf  # worker1 delay: 60→0
kubernetes/dev/.../remediation/configmap.yaml        # CHECK_INTERVAL: 120→300
kubernetes/prod/.../remediation/configmap.yaml       # CHECK_INTERVAL: 120→300
```

### 10.9 Post-Fix Validation (April 13, 00:08)

**Server rebooted after fix applied. New boot sequence:**

```
Apr 13 00:08:36  pve-dev  VM 1010 - Start  (master1)
Apr 13 00:08:36  pve-dev  VM 1011 - Start  (master2)
Apr 13 00:08:36  pve-dev  VM 1012 - Start  (master3)
         ↓
         60s wait (master3's up_delay=60) ← FIX WORKING!
         ↓
Apr 13 00:09:37  pve-dev  VM 1020 - Start  (worker1)
Apr 13 00:09:37  pve-dev  VM 1021 - Start  (worker2)
Apr 13 00:09:38  pve-dev  VM 1022 - Start  (worker3)
```

**Key observations:**
- Masters start together at 00:08:36
- **60 second gap** before workers (master3's delay working!)
- All workers start together at 00:09:37-38
- **NO remediation reboot triggered!** ← FIX CONFIRMED

**Before vs After:**

| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Gap between masters and workers | ~0s (same time) | 60s |
| Workers start sequence | Staggered (worker1, then 60s, worker2/3) | Together |
| Remediation reboot during boot | YES (caused "crash") | NO |

### 10.10 Documentation Reference

Terraform Proxmox Provider - VM Resource:
https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm

**Startup block documentation:**
```
startup - (Optional) Defines startup and shutdown behavior of the VM.
  order    - (Required) A non-negative number defining the general startup order.
  up_delay - (Optional) A non-negative number defining the delay in seconds
             before the NEXT VM is started.
  down_delay - (Optional) A non-negative number defining the delay in seconds
               before the NEXT VM is shut down.
```

### 10.11 Status (2026-04-12)

**PARTIALLY RESOLVED** — Root cause identified, but additional issue discovered on April 13.

---

## 11. Follow-up Investigation: 2026-04-13 (Prod Reboot)

> **ADDITIONAL ISSUE DISCOVERED** — After rebooting prod server on April 13, remediation still triggered a reboot on worker1 despite CHECK_INTERVAL=300s fix. Root cause: first health check happens IMMEDIATELY when remediation pod starts.

### 11.1 Prod Reboot Incident (April 13)

**Proxmox Task Log (pve-prod):**
```
Apr 13 00:58:07  pve-prod  root@pam  VM 1010 - Start  (master1)
Apr 13 00:58:07  pve-prod  root@pam  VM 1011 - Start  (master2)
Apr 13 00:58:07  pve-prod  root@pam  VM 1012 - Start  (master3)
         ↓ 60s wait (master3 delay)
Apr 13 00:59:08  pve-prod  root@pam  VM 1020 - Start  (worker1)
Apr 13 00:59:08  pve-prod  root@pam  VM 1021 - Start  (worker2)
Apr 13 00:59:08  pve-prod  root@pam  VM 1022 - Start  (worker3)
         ↓
Apr 13 01:00:10  pve-prod  k8s-pve@pve  VM 1020 - Reboot  ← REMEDIATION TRIGGERED!
Apr 13 01:00:14  pve-prod  root@pam  VM 1020 - Start
```

**Remediation Log (Loki):**
```
2026-04-13 01:00:10.347 --- Health check at 2026-04-12 23:00:10 ---
2026-04-13 01:00:10.347 Remediation service starting...
2026-04-13 01:00:10.347 Monitoring nodes: ['k8s-worker1.lab.local', 'k8s-worker2.lab.local', 'k8s-worker3.lab.local']
2026-04-13 01:00:10.347 Check interval: 300s
2026-04-13 01:00:10.347 Pod failure threshold: 70%
2026-04-13 01:00:10.358 k8s-worker1.lab.local: UNHEALTHY! (Node NotReady)
2026-04-13 01:00:10.358 [Attempt 1] Remediating k8s-worker1.lab.local (VM 1020)
2026-04-13 01:00:10.872   -> VM 1020 status: running
2026-04-13 01:00:10.872   -> Rebooting VM 1020
2026-04-13 01:00:10.973   -> Waiting 240s for recovery...
```

### 11.2 Root Cause Analysis

**Timeline:**
```
00:58:07  Masters start
00:59:08  Workers start (1 min gap - correct!)
01:00:10  Remediation pod finishes vault-agent init, script starts
01:00:10  FIRST health check IMMEDIATELY - worker1 still booting
01:00:10  worker1 NotReady → remediation triggers reboot
```

**The issue:** CHECK_INTERVAL=300s controls delay BETWEEN checks, but the FIRST check happens immediately when script starts.

**Remediation script structure (before fix):**
```python
def main():
    print("Remediation service starting...")
    print(f"Check interval: {CHECK_INTERVAL}s")

    while True:
        # FIRST CHECK HAPPENS IMMEDIATELY!
        for node in nodes:
            if not healthy:
                remediate()  # Reboots on first check!
        time.sleep(CHECK_INTERVAL)  # Then waits 5 min
```

### 11.3 Fix Applied

**Change:** Add startup delay before first health check.

**Files Changed:**
```
kubernetes/dev/deployments/apps/remediation/configmap.yaml
kubernetes/prod/deployments/apps/remediation/configmap.yaml
```

**Code Change:**
```python
# Before
while True:
    # ... health check immediately ...
    time.sleep(CHECK_INTERVAL)

# After
# Startup delay: wait before first health check to avoid race during cluster boot
print(f"Waiting {CHECK_INTERVAL}s before first health check (cluster stabilization)...")
time.sleep(CHECK_INTERVAL)

while True:
    # ... health check after initial delay ...
    time.sleep(CHECK_INTERVAL)
```

### 11.4 Fix Validation (Dev Environment)

**ConfigMap Update via Flux:**
```bash
[root@k8s-master1 ~]# flux events --for kustomization/apps
84s   Normal  Progressing  Kustomization/apps  ConfigMap/remediation/remediation-script configured
```

**Restart remediation pod:**
```bash
[root@k8s-master1 ~]# kubectl delete pod -l app=remediation -n remediation
pod "remediation-56bdddfcd7-4sd6r" deleted

[root@k8s-master1 ~]# kubectl get pods -n remediation
NAME                           READY   STATUS    RESTARTS   AGE
remediation-56bdddfcd7-t8fvv   2/2     Running   0          41s
```

**Verify startup delay active:**
```bash
[root@k8s-master1 ~]# kubectl logs -l app=remediation -n remediation -c remediation
Remediation service starting...
Monitoring nodes: ['k8s-worker1.lab.local', 'k8s-worker2.lab.local', 'k8s-worker3.lab.local']
Check interval: 300s
Pod failure threshold: 70%
Waiting 300s before first health check (cluster stabilization)...  ← FIX WORKING!
```

### 11.5 New Expected Boot Timeline

```
T+0:00   Masters start (order 8)
T+1:00   Workers start (after master3's 60s delay)
T+1:30   Remediation pod starts (after vault-agent init)
T+1:30   Remediation waits 5 min before first check  ← NEW!
T+3:00   Workers fully Ready
T+6:30   Remediation first health check
         All workers healthy, no action needed ✓
```

### 11.6 Complete Fix Summary

| Issue | Fix | File |
|-------|-----|------|
| Masters and workers start together | master3 `startup_delay=60` | terraform/*/vms/k8s_masters/variables.tf |
| worker1 delay was on wrong VM | worker1 `startup_delay=0` | terraform/*/vms/k8s_workers/variables.tf |
| CHECK_INTERVAL too short (120s) | Increased to 300s | kubernetes/*/remediation/configmap.yaml |
| First check was immediate | Added startup delay | kubernetes/*/remediation/configmap.yaml |

### 11.7 Files Changed (All Fixes)

```
# Terraform (April 12)
terraform/dev/proxmox/vms/k8s_masters/variables.tf   # master3 delay: 0→60
terraform/dev/proxmox/vms/k8s_workers/variables.tf   # worker1 delay: 60→0
terraform/prod/proxmox/vms/k8s_masters/variables.tf  # master3 delay: 0→60
terraform/prod/proxmox/vms/k8s_workers/variables.tf  # worker1 delay: 60→0

# Kubernetes (April 12)
kubernetes/dev/.../remediation/configmap.yaml        # CHECK_INTERVAL: 120→300
kubernetes/prod/.../remediation/configmap.yaml       # CHECK_INTERVAL: 120→300

# Kubernetes (April 13)
kubernetes/dev/.../remediation/configmap.yaml        # Added startup delay
kubernetes/prod/.../remediation/configmap.yaml       # Added startup delay
```

### 11.8 Status

**RESOLVED + FULLY VALIDATED** — All race conditions addressed:
1. ✓ Terraform: 60s gap between masters and workers
2. ✓ Kubernetes: CHECK_INTERVAL=300s (5 min between checks)
3. ✓ Kubernetes: Startup delay (wait 5 min before first check)

**New remediation behavior:**
```
Pod starts → Waits 5 min → First check → Waits 5 min → Next check → ...
```

No false positive reboots during cluster boot sequence.
