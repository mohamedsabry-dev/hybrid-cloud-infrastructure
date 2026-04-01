# Troubleshooting: Dev SVC Network Down - ER605 Port 4 Instability

**Date**: March 2026
**Duration**: ~45 minutes troubleshooting
**Affected**: Dev environment - all VMs/LXCs on SVC VLANs (60-65)
**Resolution**: Force 100M Full-duplex + Enable Flow Control on ER605 Port 4

---

## Symptoms

- All Dev VMs/LXCs lost connectivity to gateway
- VMs could see their own IPs but couldn't ping gateway (10.0.6x.1)
- Proxmox svc0 interface showed UP state
- Inter-VLAN routing not working

**From k8s-master1 (10.0.61.10):**
```
ping 10.0.61.1
PING 10.0.61.1 (10.0.61.1) 56(84) bytes of data.
From 10.0.61.10 icmp_seq=1 Destination Host Unreachable
ping: sendmsg: No route to host

traceroute to 10.0.61.1
1  k8s-master1.lab.local (10.0.61.10)  3069.872 ms !H  3069.831 ms !H
```

**Proxmox interface status:**
```
3: svc0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
```

---

## Network Path

```
Proxmox Dev (svc0)
       │
       │ VLAN tagged traffic (60-65)
       ▼
FS308GP Switch Port 7
       │
       │ Internal switch fabric
       ▼
FS308GP Switch Port 3 (Dev_SVC_ALL trunk)
       │
       │ Trunk: VLANs 60-65
       ▼
ER605 Port 4 (Dev_SVC) ◄── PROBLEM HERE
       │
       ▼
Gateway (10.0.6x.1)
```

---

## Troubleshooting Sequence

### Test 1: Initial Check
| Check | Result |
|-------|--------|
| Proxmox svc0 interface | UP |
| Router (ER605) LEDs | All UP |
| Switch (FS308GP) LEDs | All UP except Port 3 |
| Switch Web UI - Port 3 | `Dev_SVC_ALL` showed **offline** |

**Action**: Reseat cable on Switch Port 3
**Result**: Service restored temporarily

**Initial Hypothesis**: Loose cable connection
**Outcome**: WRONG - issue recurred

---

### Test 2: Cable Replacement
**Action**: Replaced Ethernet cable between FS308GP Port 3 and ER605 Port 4
**Result**: Issue recurred after ~1 minute

**Hypothesis**: Faulty cable
**Outcome**: WRONG - new cable had same issue

---

### Test 3: PVID Change (Isolate Router vs Switch)
**Action**: Changed ER605 Port 4 PVID from 60 to 61
**Result**: Port came online briefly when config applied, then went offline again

**Analysis**: The act of saving config on ER605 triggered port reconnection, confirming issue is on **router side**, not switch side.

**Hypothesis**: Switch port issue
**Outcome**: WRONG - confirmed router side

---

### Test 4: Port Came Online Spontaneously
**Observation**: While discussing, port came back online without any intervention
**Analysis**: Intermittent failure pattern - worst kind to troubleshoot

---

### Test 5: Switch Port Settings
**Changes on FS308GP Port 3:**
| Setting | Before | After |
|---------|--------|-------|
| Flow Control | Disabled | Enabled |
| PoE | Off | Default |
| LLDP-MED | Enabled | Disabled |

**Result**: Issue recurred - port went down again

**Hypothesis**: Switch-side settings causing instability
**Outcome**: WRONG - switch settings unrelated

---

### Test 6: Force 100M + Flow Control on ER605 (SOLUTION)
**Changes on ER605 Port 4:**
| Setting | Before | After |
|---------|--------|-------|
| Speed/Duplex | Auto | 100M Full-duplex |
| Flow Control | Disabled | Enabled |

**Result**: Port stable for 30+ minutes - **ISSUE RESOLVED**

---

## Root Cause

**Gigabit auto-negotiation failure on ER605 Port 4**

The port was failing to maintain stable Gigabit link. Possible causes:
- ER605 Port 4 PHY (physical layer chip) degrading
- Firmware bug in auto-negotiation
- Signal integrity issues at Gigabit speeds
- Incompatibility between ER605 and FS308GP at Gigabit

Forcing 100M Full-duplex bypasses the problematic Gigabit negotiation.

---

## Why Port Migration Was Not Chosen

**Recommendation given**: Move trunk from ER605 Port 4 to Port 5

**User decision**: Keep Port 5 available for potential Prod expansion

**Reasoning**:
- Port 5 is the last available port on ER605
- May be needed for future Prod network segment
- 100M speed is sufficient for Dev environment
- ISP speed is only 30-70 Mbps anyway

**Trade-off accepted**: Dev SVC runs at 100M instead of 1G, port preserved for Prod.

---

## Final Configuration

**ER605 Port 4 (Dev_SVC):**
- Speed: 100M Full-duplex (forced)
- Flow Control: Enabled
- PVID: 60
- Tagged VLANs: 60, 61, 62, 63, 64, 65

---

## Recommendations

### Should All Router Ports Be Set to 100M?

**Opinion: No, not recommended**

| Port | Current Use | Recommendation |
|------|-------------|----------------|
| Port 1 (WAN) | ISP Connection | Keep Auto - ISP may require Gigabit negotiation |
| Port 2 | Management/VLAN 5 | Keep Auto - low traffic, working fine |
| Port 3 | Prod_SVC trunk | Keep Auto - working fine, don't touch |
| Port 4 | Dev_SVC trunk | **100M Forced** - problematic port |
| Port 5 | Reserved | Keep Auto - reserve for future |

**Reasoning:**
- Only Port 4 has shown instability
- Changing working ports risks introducing new issues
- "If it ain't broke, don't fix it"
- ISP speed (30-70 Mbps) doesn't mean internal network should be limited

### Should Flow Control Be Enabled on All Ports?

**Opinion: Yes, can enable on all LAN ports**

**Benefits:**
- Prevents packet loss during traffic bursts
- Helps with switch-to-router communication
- Low overhead, minimal downside

**Suggested:**
- Port 1 (WAN): Leave as-is (ISP controls this)
- Ports 2-5 (LAN): Enable Flow Control

**Note**: Flow control alone didn't fix Port 4 - it was the combination with 100M that stabilized it.

---

## Monitoring

Watch for:
- Port 4 going offline again (check switch web UI)
- Performance issues on Dev VLANs (unlikely at 100M for typical workloads)

If Port 4 fails again at 100M, then migrate to Port 5 as last resort.

---

## Update: Ongoing Intermittent Failure

**Observation**: Even with 100M Full-duplex + Flow Control, port still drops intermittently.

| Pattern | Details |
|---------|---------|
| Frequency | ~Every 2 hours |
| Duration | ~30 seconds |
| Impact | Dev SVC network briefly unreachable |

**Conclusion**: **ER605 Port 4 is hardware defective**. The 100M + Flow Control setting reduced frequency but did not eliminate the issue.

**Decision**: Accept for now since it's Dev environment only. Prod uses different port (Port 3) which is stable.

**Future Action**:
- Replace ER605 if issue becomes unacceptable
- Or migrate to Port 5 (but prefer to reserve for Prod expansion)

---

## Lessons Learned

1. **Intermittent failures are hard** - required multiple tests to isolate
2. **Don't assume cable first** - was not the cable
3. **Config changes can reveal clues** - PVID change showed router was the source
4. **Auto-negotiation can fail** - forcing speed/duplex is valid fix
5. **100M is often enough** - especially when ISP is slower anyway
6. **Keep spare ports** - user wisely preserved Port 5 for Prod
7. **ER605 has no CLI** - limited troubleshooting options, no debug logs

---

## ER605 Diagnostic Logs Analysis

**Date**: March 2026
**Purpose**: Investigate Port 4 intermittent failures via SSH diagnostic commands

### Commands Executed

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa admin@10.0.5.1
```

**Note**: ER605 uses legacy SSH key algorithms (ssh-rsa), requiring explicit compatibility flags.

### Logs Analyzed

| Command | Purpose | Result |
|---------|---------|--------|
| `ps` | Process list | Normal - ~50 processes running |
| `ifconfig` | Interface status | All interfaces UP, **0 errors** on all ports |
| `netstat -rn` | Routing table | Correct routes for all VLANs |
| `iptables -L -n -v` | Firewall rules | Normal NAT/filter rules |
| `top` (snapshot) | CPU/Memory | CPU ~3%, Memory ~50% free |
| `df` | Disk usage | tmpfs filesystems, plenty of space |

### Key Findings

**System Health: Normal**
- CPU utilization: ~3% (idle 97%)
- Memory: ~50% free (32MB used of 64MB)
- No runaway processes
- No memory pressure

**Network Interfaces: No Errors**
```
eth0 (WAN):     RX errors:0 dropped:0 | TX errors:0 dropped:0
eth1 (Port 2):  RX errors:0 dropped:0 | TX errors:0 dropped:0
eth2 (Port 3):  RX errors:0 dropped:0 | TX errors:0 dropped:0
eth3 (Port 4):  RX errors:0 dropped:0 | TX errors:0 dropped:0  ← Problem port shows 0 errors!
eth4 (Port 5):  RX errors:0 dropped:0 | TX errors:0 dropped:0
```

**VLAN Interfaces: Normal**
- All VLAN interfaces (br5, br40, br50, br60-65) showing traffic
- No errors on any bridge interface

### Conclusion

**The Port 4 failure is NOT visible in software-level diagnostics.**

| Layer | Status | Evidence |
|-------|--------|----------|
| Software/OS | ✅ Normal | CPU, memory, processes all healthy |
| Network stack | ✅ Normal | 0 errors reported on eth3 |
| Firewall | ✅ Normal | Rules correct, no drops |
| **PHY/Hardware** | ❌ **Suspected** | Issue occurs below software visibility |

The intermittent link drops are happening at the **physical layer (PHY)** - the hardware component that handles electrical signaling and auto-negotiation. This level of failure:
- Is not logged by the Linux kernel on ER605
- Shows no errors in ifconfig statistics
- Cannot be diagnosed via SSH/CLI

**Recommendation**:
- Continue with 100M Full-duplex workaround
- Monitor for complete failure
- Replace ER605 if issue worsens or affects Prod ports

---

## FS308GP Switch Logs Analysis

**Date**: March 21, 2026
**Purpose**: Analyze switch-side logs to correlate with ER605 Port 4 failures

### Log Files Collected

| File | Content |
|------|---------|
| syslog.log | System events including link state changes |
| switchCfg.cfg | Running configuration |
| cpuUltilization.txt | CPU usage |
| meminfo | Memory stats |
| dmesg | Kernel boot messages |
| ecs.log | Cloud controller logs |

### Critical Finding: Link Flapping

**Switch Port 3 (Gi1/0/3)** - connected to ER605 Port 4:
```
#2026-03-21 19:01:41,[Link]/5/Gi1/0/3 changed state to down.
#2026-03-21 19:01:41,[Link]/5/Gi1/0/3 changed state to up.
#2026-03-21 19:01:35,[Link]/5/Gi1/0/3 changed state to down.
#2026-03-21 19:01:31,[Link]/5/Gi1/0/3 changed state to up.
#2026-03-21 19:01:29,[Link]/5/Gi1/0/3 changed state to down.
... (pattern continues)
```

**Total link down events in log: 445**

### Link State Change Comparison

| Port | Function | Link Events | Status |
|------|----------|-------------|--------|
| Gi1/0/2 | Prod_SVC trunk | 2 | ✅ Stable |
| **Gi1/0/3** | **Dev_SVC trunk (to ER605 Port 4)** | **445** | ❌ **FLAPPING** |
| Gi1/0/4 | Dev_SVC (Proxmox) | 6 | ✅ Normal |
| Gi1/0/5 | Prod_SVC (Proxmox) | 4 | ✅ Normal |
| Gi1/0/7 | Management | 1 | ✅ Normal |
| Gi1/0/8 | Management | 2 | ✅ Normal |

### Flapping Pattern Analysis

```
Time Window: 18:55 - 19:01 (6 minutes)
Link Changes: ~80 down/up cycles
Average: ~13 flaps per minute (one every ~5 seconds)

Pattern: Link drops, immediately comes back up, drops again
Duration of down state: <1 second to ~30 seconds
```

### Switch Health Status

| Metric | Value | Status |
|--------|-------|--------|
| CPU | 1-8% | ✅ Normal |
| Memory | 36MB free / 125MB (29%) | ✅ Normal |
| Load Average | 0.10 | ✅ Normal |
| Other Ports | Stable | ✅ Normal |

### Switch Port 3 Configuration

```
interface gigabitEthernet 1/0/3
  flow-control
  switchport general allowed vlan 99 untagged
  switchport general allowed vlan 60-65 tagged
  switchport pvid 99
  no switchport general allowed vlan 1
  lldp med-status
  power inline supply disable
```

**Note**: Flow control is enabled on switch side (as recommended during troubleshooting).

### Conclusion

The switch logs **confirm the ER605 Port 4 PHY failure**:

1. **Only Port 3** shows excessive link flapping (445 events)
2. All other ports are stable (normal 1-6 events)
3. Switch CPU/memory is healthy - not a switch overload issue
4. The link flaps on both sides simultaneously (switch detects ER605 port going down)
5. Pattern matches PHY-layer auto-negotiation failure

**Evidence Summary**:
- ER605 logs: No errors visible (PHY failures below software layer)
- Switch logs: **445 link down events on Port 3 only**
- Both devices: Health metrics normal
- Root cause: **ER605 Port 4 hardware PHY failure at Gigabit speeds**

The 100M Full-duplex workaround reduces but doesn't eliminate the issue, suggesting progressive hardware degradation.

---

## Detailed Flapping Pattern Analysis

### Overview

| Metric | Value |
|--------|-------|
| Total link down events | 445 |
| Time span | ~22 hours (Mar 20 21:33 - Mar 21 19:01) |
| Pattern | **NOT consistent** - varies by time of day |

### Timeline Breakdown

| Period | Time Range | Events | Flap Rate | Analysis |
|--------|------------|--------|-----------|----------|
| Night (before fix) | Mar 20 21:33 - Mar 21 03:17 | ~50 | 1 per 2-5 min | Moderate instability |
| Early morning | 03:17 - 08:09 | ~7 | 1 per 30-60 min | **Most stable period** |
| Morning active | 10:45 - 11:40 | ~70 | 1 per 2-10 sec | **SEVERE flapping** |
| Troubleshooting | 11:40 - 17:40 | ~180 | 1 per 2-30 sec | Very unstable |
| **After 100M fix** | 17:51 - 18:55 | **0** | **STABLE** | 1 hour gap |
| Flapping resumed | 18:55 - 19:01 | ~40 | 1 per 2-10 sec | Issue returned |

### Key Findings

1. **Morning events ARE recorded before the 100M fix**
   - 348 link down events occurred before 17:40 (when 100M was applied)
   - Confirms the issue existed throughout the day

2. **100M + Flow Control DID provide temporary stability**
   - Clear 1-hour gap with zero flaps: 17:51 → 18:55
   - This proves the fix had some effect

3. **But the issue returned**
   - After 18:55, flapping resumed at severe rate
   - 40 events in 6 minutes

4. **Pattern correlates with activity/heat**
   - Worst: Daytime active hours (every 2-10 seconds)
   - Best: Early morning 03:00-08:00 (every 30-60 minutes)
   - Suggests thermal-related PHY degradation

### Root Cause Hypothesis: Thermal PHY Failure

The varying flap rate suggests **temperature-dependent hardware failure**:

```
Low activity (night) → Less heat → PHY more stable → ~1 flap/hour
High activity (day)  → More heat → PHY unstable  → ~1 flap/5 sec
100M mode           → Less power → Cooler        → Temporarily stable
Continued operation → Heat builds → Failure returns
```

**Conclusion**: ER605 Port 4 PHY chip has thermal issues. Lower speeds generate less heat, temporarily masking the failure, but the underlying hardware is degrading.

---

## Critical Discovery: Router Reboot Correlation

### ER605 Uptime Analysis

**Screenshot captured**: Mar 21, 19:17:39

| Field | Value |
|-------|-------|
| System Time | 03/21/2026 19:17:39 |
| Running Time | 0 Day, 21 Hour, 43 Min, 41 Sec |
| **Calculated Reboot Time** | **Mar 20, ~21:33:58** |

### Switch Log Correlation

**First flapping event in switch syslog:**
```
#2026-03-20 21:33:20,[Link]/5/Gi1/0/3 changed state to down.
```

**Match: The timestamps align within seconds!**

### Significance

| Finding | Implication |
|---------|-------------|
| First flap = Router boot time | Flapping started **immediately** after reboot |
| No stable period after boot | Port 4 was broken from the moment it came online |
| Not gradual degradation | PHY hardware is **consistently faulty** |

### What This Tells Us

1. **The router reboot on Mar 20 ~21:33 was to change WireGuard VPN port** (unrelated to Port 4)
2. **Port 4 started flapping the instant it came up** after reboot
3. **The PHY failure is not thermal/progressive** - it's a persistent hardware defect
4. **The port never worked correctly** since the last reboot

### Reboot Test Results (Mar 21, 19:37)

Router rebooted to verify the pattern. **ER605 logs confirm immediate flapping:**

```
2026-03-21 19:37:42  [LAN4] was down
2026-03-21 19:37:34  [LAN4] was up
2026-03-21 19:37:33  [LAN4] was down
2026-03-21 19:37:23  [LAN4] was up
2026-03-21 19:37:22  [LAN4] was down
```

**Verdict**: Port 4 flaps immediately on cold boot - confirms persistent PHY hardware defect.

---

## Permanent Fix Applied

**Date**: March 21, 2026

### Solution: Migrate from Port 4 to Port 2

Since Port 4 is hardware defective, migrated the Dev_SVC trunk to Port 2.

### Changes Made

**ER605 Router:**

| Setting | Port 4 (Old - Defective) | Port 2 (New) |
|---------|--------------------------|--------------|
| Function | Dev_SVC trunk | Dev_SVC trunk |
| Tagged VLANs | 60, 61, 62, 63, 64, 65 | 60, 61, 62, 63, 64, 65 |
| PVID | 60 | 60 |
| Status | **Abandoned** | **Active** |

**Additional**: Port Mirroring configured (Port 4 → Port 2, Ingress+Egress) for any residual traffic.

**FS308GP Switch:**

| Setting | Before | After |
|---------|--------|-------|
| Port 3 destination | ER605 Port 4 | ER605 Port 2 |

### New Network Path

```
Proxmox Dev (svc0)
       │
       │ VLAN tagged traffic (60-65)
       ▼
FS308GP Switch Port 7
       │
       │ Internal switch fabric
       ▼
FS308GP Switch Port 3 (Dev_SVC_ALL trunk)
       │
       │ Trunk: VLANs 60-65
       ▼
ER605 Port 2 (Dev_SVC) ◄── NEW - Healthy port
       │
       ▼
Gateway (10.0.6x.1)
```

### Port Allocation After Fix

| Port | Function | Status |
|------|----------|--------|
| Port 1 | WAN (ISP) | ✅ Active |
| Port 2 | **Dev_SVC trunk** | ✅ Active (moved here) |
| Port 3 | Prod_SVC trunk | ✅ Active |
| Port 4 | ~~Dev_SVC~~ | ❌ **Defective - Abandoned** |
| Port 5 | Internal AP uplink (Mgmt plane) | ✅ Active |

### Result

✅ **Dev SVC network stable** - no more flapping after migration to Port 2.

---

## Summary

**Issue**: ER605 Port 4 PHY hardware defect causing persistent link flapping (445 events in 22 hours).

**Root Cause**: Physical layer (PHY) chip failure - port cannot maintain stable Gigabit or 100M link.

**Evidence**:
- Switch logs: 445 link down events on Port 3 (connected to ER605 Port 4)
- ER605 logs: LAN4 flapping immediately after every reboot
- Router uptime correlated exactly with first flap timestamp
- All other ports stable

**Temporary Fix**: 100M Full-duplex + Flow Control (reduced severity but didn't eliminate)

**Permanent Fix**: Migrated Dev_SVC trunk from Port 4 to Port 2

**Status**: ⚠️ Partially Resolved - See Update Below

---

## Update: Issue Recurrence (March 26, 2026)

**Related Case**: `57-svc-network-instability-force-100m.md`

### Issue Returned

The Dev SVC network issue recurred ~1-2 weeks after the original fix, despite:
- Migration from ER605 Port 4 to Port 2
- Port mirroring configuration
- Previous 100M + Flow Control settings

### Extended Troubleshooting Performed

| Action | Result |
|--------|--------|
| Changed USB-Ethernet adapter | Issue remained |
| Changed Ethernet cable | Issue remained |
| Changed server USB port | Issue remained |
| Swapped switch ports (3 ↔ 4) | Issue remained |
| Bypassed switch (direct to router) | Initially failed, then worked randomly |
| Tested with MikroTik router | Same issue |
| Disabled port mirror on ER605 Port 2 | Partial improvement |
| Forced 100M on ER605 ports | **STABLE** |

### Root Cause: UNIDENTIFIED

After extensive isolation, the exact root cause could NOT be definitively identified. The behavior was inconsistent:
- Same setup would fail, then work without changes
- Port mirror: was solution in one case, problem in another
- Multiple components suspected but none confirmed

### Confirmed Workaround

**Force 100M speed on ALL SVC router ports.**

| Port | Setting | Reason |
|------|---------|--------|
| ER605 Port 2 | 100M Full | Dev SVC uplink |
| ER605 Port 4 | 100M Full | Dev SVC (if used) |
| ER605 Port 5 | Auto (100M default) | Prod SVC - stable because Prod server has built-in NIC that defaults to 100M |

### Why Prod is Stable

Prod server uses **built-in Ethernet** which negotiates at 100M by default. Dev server uses **USB-Ethernet adapter** which attempts Gigabit negotiation - this is where instability occurs.

### Updated Recommendation

| Previous | Updated |
|----------|---------|
| Only force 100M on problem port | Force 100M on ALL SVC ports |
| Migrate to different port | Keep 100M regardless of port |
| Trust auto-negotiation on working ports | Don't trust auto-negotiation for SVC |

### Lessons Learned (Updated)

1. **Intermittent network issues may never have a clear root cause**
2. **USB-Ethernet adapters + Gigabit negotiation = unreliable**
3. **100M is sufficient and more stable for this environment**
4. **"Working" ports can develop same issues over time**
5. **Document the workaround even when root cause is unknown**

### Current Status

✅ **Stable** - All SVC ports forced to 100M from router side
