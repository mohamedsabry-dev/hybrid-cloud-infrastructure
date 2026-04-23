# TS-PVE-014 | 2026-04-11 | RESOLVED (2026-04-13)
_____________________________________________________________________

[Info]
Domain: Proxmox VE VM autostart / Kubernetes remediation
Sub-techs: VM 1021 (k8s-worker2), QEMU, Proxmox autostart, remediation pod, Terraform startup config
Environment: pve-prod (confirmed on pve-dev April 12)
Re-opened: Yes -- April 12 follow-up identified real root cause; April 13 follow-up fixed remaining race condition

_____________________________________________________________________

[Issue Description]
REAL INCIDENT -- occurred during unplanned VM crash after autostart, not planned DR testing.

Worker VM 1021 started successfully during autostart sequence but crashed/froze within ~1 minute, with no indication of cause in available logs.

```
# Proxmox task log
Apr 11 10:39:42  pve-prod  root@pam  VM 1021 - Start  OK
Apr 11 10:40:51  pve-prod  k8s-pve@pve  VM 1021 - Reboot  Error: VM quit/powerdown failed

# journalctl -u pvedaemon
Apr 11 10:41:51 pve-prod pvedaemon[9417]: VM 1021 qga command failed - VM 1021 qga command 'guest-shutdown' failed - got timeout
Apr 11 10:41:51 pve-prod pvedaemon[1352]: <k8s-pve@pve!remediation> end task [...]: VM quit/powerdown failed
```

Impact: Kubernetes worker node NotReady, pods on that node entered Unknown/Terminating state.

_____________________________________________________________________

[Analysis]
# Step 1: Initial timeline (April 11)
```
10:32:32 - 10:37:40  Proxmox autostart: LXC containers (CT 2001-2006)
10:38:39 - 10:38:50  Proxmox autostart: K8s master VMs (1010, 1011, 1012)
10:39:42 - 10:39:45  Proxmox autostart: K8s worker VMs (1020, 1021, 1022)
     |
     VM 1021 started successfully (task status: OK)
     |
     ~1 minute passes - VM running
     |
     VM 1021 crashes/freezes (no external trigger)
     |
10:40:51             Remediation pod detects worker2 NotReady
10:40:51             Remediation attempts reboot via Proxmox API
10:41:51             Reboot fails - guest agent not responding (VM already dead)
```

# Step 2: Initial investigation (found nothing)
```bash
cat /var/log/pve/tasks/index | grep 1021
journalctl -u pvedaemon --since "today" | grep 1021
kubectl get nodes
# k8s-worker2.lab.local   NotReady   <none>   15d   v1.35.3
```

| Investigation | Result |
|---------------|--------|
| Proxmox host dmesg | No OOM killer, no hardware errors |
| VM kernel logs | Not accessible -- VM stopped |
| QEMU process errors | None logged |
| Storage errors | None logged |
| Network issues | Other VMs on same host working |

# Step 3: Manual recovery (April 11)
```bash
qm start 1021
```
VM started successfully and remained stable.

# Step 4: ROOT CAUSE IDENTIFIED (April 12)
After rebooting both prod and dev servers on April 12, I observed the identical pattern on dev. The "crash" was actually the remediation pod triggering a reboot during normal worker boot sequence.

Proxmox task log (pve-dev):
```
Apr 12 19:45:52  pve-dev  root@pam  VM 1010 - Start  (master1)
Apr 12 19:45:52  pve-dev  root@pam  VM 1011 - Start  (master2)
Apr 12 19:45:52  pve-dev  root@pam  VM 1012 - Start  (master3)
Apr 12 19:45:55  pve-dev  root@pam  VM 1020 - Start  (worker1)
Apr 12 19:46:55  pve-dev  root@pam  VM 1021 - Start  (worker2)
Apr 12 19:47:08  pve-dev  root@pam  VM 1022 - Start  (worker3)
Apr 12 19:48:43  pve-dev  k8s-pve@pve  VM 1022 - Reboot  <- REMEDIATION TRIGGERED!
Apr 12 19:48:52  pve-dev  root@pam  VM 1022 - Start
```

Reboot triggered by `k8s-pve@pve` (remediation service account), NOT Proxmox autostart or VM crash.

# Step 5: Trace the race condition
```
19:45:52-55  Masters start (order 8, delay=0)
             Remediation pod starts on master
19:45:55     Worker1 starts (order 9, has up_delay=60)
             up_delay=60 delays NEXT vm, not this one!
             | 60s wait
19:46:55     Worker2 starts (up_delay=0)
19:47:08     Worker3 starts (up_delay=0)
             Workers booting, kubelet starting, Node status: NotReady (normal during boot)

~19:48:30    Remediation second check (CHECK_INTERVAL=120s)
             Worker3 uptime: ~1.5 minutes, still NotReady -> TRIGGERS REBOOT!
19:48:43     VM 1022 Reboot by k8s-pve@pve
```

Three contributing factors:
1. Proxmox `up_delay` misunderstanding -- delays NEXT VM, not current
2. Remediation CHECK_INTERVAL too short (120s) -- catches workers during boot
3. No boot protection -- no initial grace period after remediation pod starts

VM startup config verification:
```bash
qm config 1020 | grep startup
# startup: order=9,up=60,down=60  (worker1 - has delay)

qm config 1021 | grep startup
# startup: order=9,up=0,down=60   (worker2 - no delay)

qm config 1022 | grep startup
# startup: order=9,up=0,down=60   (worker3 - no delay)
```

_____________________________________________________________________

[Final Root Cause]
The "crash" was NOT a VM crash. The remediation pod detected workers as NotReady during their normal boot sequence and triggered reboots via the Proxmox API. Three factors combined: `up_delay` semantics were misunderstood (delays next VM, not current), CHECK_INTERVAL was too short (120s), and no startup grace period existed before the first health check.

_____________________________________________________________________

[Final Solution]
Applied fixes in three rounds:

April 12 -- Terraform startup order fix:
| File | Change |
|------|--------|
| `terraform/*/proxmox/vms/k8s_masters/variables.tf` | master3: `startup_delay = 0` -> `60` |
| `terraform/*/proxmox/vms/k8s_workers/variables.tf` | worker1: `startup_delay = 60` -> `0` |

This creates a 60s gap between masters and workers (master3's delay holds workers).

April 12 -- Remediation CHECK_INTERVAL fix:
| File | Change |
|------|--------|
| `kubernetes/*/deployments/apps/remediation/configmap.yaml` | `CHECK_INTERVAL = 120` -> `300` |

April 13 -- Startup delay fix (prod still had issue because first check was immediate):

Prod reboot showed remediation still triggered on worker1 despite CHECK_INTERVAL=300s. The first health check happened IMMEDIATELY when the script started.

```python
# Before
while True:
    # FIRST CHECK HAPPENS IMMEDIATELY!
    for node in nodes:
        if not healthy:
            remediate()
    time.sleep(CHECK_INTERVAL)

# After
print(f"Waiting {CHECK_INTERVAL}s before first health check (cluster stabilization)...")
time.sleep(CHECK_INTERVAL)
while True:
    for node in nodes:
        if not healthy:
            remediate()
    time.sleep(CHECK_INTERVAL)
```

Validation (dev environment):
```bash
kubectl logs -l app=remediation -n remediation -c remediation
# Waiting 300s before first health check (cluster stabilization)...  <- FIX WORKING!
```

Post-fix validation (April 13, 00:08):
```
Apr 13 00:08:36  pve-dev  VM 1010 - Start  (master1)
Apr 13 00:08:36  pve-dev  VM 1011 - Start  (master2)
Apr 13 00:08:36  pve-dev  VM 1012 - Start  (master3)
         |
         60s wait (master3's up_delay=60) <- FIX WORKING!
         |
Apr 13 00:09:37  pve-dev  VM 1020 - Start  (worker1)
Apr 13 00:09:37  pve-dev  VM 1021 - Start  (worker2)
Apr 13 00:09:38  pve-dev  VM 1022 - Start  (worker3)
```
NO remediation reboot triggered.

| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Gap between masters and workers | ~0s (same time) | 60s |
| Workers start sequence | Staggered (worker1, then 60s, worker2/3) | Together |
| Remediation reboot during boot | YES (caused "crash") | NO |

New remediation behavior: Pod starts -> Waits 5 min -> First check -> Waits 5 min -> Next check -> ...

Verified: Yes -- no false positive reboots during cluster boot sequence.

_____________________________________________________________________

[Risk Level] LOW (manual start is safe, but underlying cause needed multi-round investigation)

_____________________________________________________________________

[References]
- Terraform Proxmox Provider: https://registry.terraform.io/providers/bpg/proxmox/latest/docs/resources/virtual_environment_vm
- Related: TS-PVE-012 (VM autostart timeout -- same `up_delay` misunderstanding)
- Related: TS-K8S-021 (remediation pod API error handling)
- Related: TS-K8S-022 (cascading pod failures from worker node loss)
