# TS-NET-003 | 2026-03-21 to 2026-03-27 | RESOLVED

## 1. Context
- System: Dev SVC Network (VLANs 60-65)
- Environment: Proxmox Dev server → FS308GP Switch → ER605 Router
- Related components: USB-Ethernet adapter (UGREEN 2.5G, ASIX AX88179B), ER605 ports, FS308GP switch
- Total Duration: 6 days of investigation across 4 phases (~6+ hours troubleshooting)

## 2. Issue
- Symptom: Dev VMs intermittently lose gateway connectivity. Pattern: Works → Fails → Works (cyclical every 2-30 seconds)
- Error:
```
From 10.0.60.10 icmp_seq=1 Destination Host Unreachable
From 10.0.60.10 icmp_seq=2 Destination Host Unreachable
```

**Kernel evidence (link flapping):**
```
[Sun Mar 22 11:43:16 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered forwarding state
[Sun Mar 22 11:43:20 2026] vmbr0: port 1(svc0) entered disabled state
... (pattern repeats every 2-3 seconds)
```

**Key observation:** Prod environment always stable, only Dev affected.

---

# ═══════════════════════════════════════════════════════════════════
# PHASE 1: ER605 Port 4 Gigabit Negotiation Failure
# Date: 2026-03-21
# Duration: ~45 minutes troubleshooting
# Result: PARTIALLY RESOLVED (issue recurred)
# ═══════════════════════════════════════════════════════════════════

## Phase 1 — Symptoms

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

## Phase 1 — Network Path

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

## Phase 1 — Troubleshooting Sequence

### Test 1: Initial Physical Check

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

### Test 4: Spontaneous Recovery

**Observation**: While discussing, port came back online without any intervention
**Analysis**: Intermittent failure pattern - worst kind to troubleshoot

---

### Test 5: Switch Port Settings Adjustment

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

### Test 6: Force 100M + Flow Control on ER605 (TEMPORARY SOLUTION)

**Changes on ER605 Port 4:**
| Setting | Before | After |
|---------|--------|-------|
| Speed/Duplex | Auto | 100M Full-duplex |
| Flow Control | Disabled | Enabled |

**Result**: Port stable for 30+ minutes - **APPEARED RESOLVED**

---

## Phase 1 — Root Cause Hypothesis

**Gigabit auto-negotiation failure on ER605 Port 4**

The port was failing to maintain stable Gigabit link. Possible causes:
- ER605 Port 4 PHY (physical layer chip) degrading
- Firmware bug in auto-negotiation
- Signal integrity issues at Gigabit speeds
- Incompatibility between ER605 and FS308GP at Gigabit

Forcing 100M Full-duplex bypasses the problematic Gigabit negotiation.

---

## Phase 1 — Why Port Migration Was Not Chosen

**Recommendation given**: Move trunk from ER605 Port 4 to Port 5

**User decision**: Keep Port 5 available for potential Prod expansion

**Reasoning**:
- Port 5 is the last available port on ER605
- May be needed for future Prod network segment
- 100M speed is sufficient for Dev environment
- ISP speed is only 30-70 Mbps anyway

**Trade-off accepted**: Dev SVC runs at 100M instead of 1G, port preserved for Prod.

---

## Phase 1 — Configuration After Fix

**ER605 Port 4 (Dev_SVC):**
- Speed: 100M Full-duplex (forced)
- Flow Control: Enabled
- PVID: 60
- Tagged VLANs: 60, 61, 62, 63, 64, 65

---

## Phase 1 — Should All Router Ports Be Set to 100M?

**Opinion: No, not recommended at this point**

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

---

## Phase 1 — Should Flow Control Be Enabled on All Ports?

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

## Phase 1 — Update: Ongoing Intermittent Failure

**Observation**: Even with 100M Full-duplex + Flow Control, port still drops intermittently.

| Pattern | Details |
|---------|---------|
| Frequency | ~Every 2 hours |
| Duration | ~30 seconds |
| Impact | Dev SVC network briefly unreachable |

**Conclusion**: **ER605 Port 4 is hardware defective**. The 100M + Flow Control setting reduced frequency but did not eliminate the issue.

**Decision**: Accept for now since it's Dev environment only. Prod uses different port (Port 3) which is stable.

---

## Phase 1 — ER605 Diagnostic Logs Analysis

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

### System Health: Normal

- CPU utilization: ~3% (idle 97%)
- Memory: ~50% free (32MB used of 64MB)
- No runaway processes
- No memory pressure

### Network Interfaces: No Errors

```
eth0 (WAN):     RX errors:0 dropped:0 | TX errors:0 dropped:0
eth1 (Port 2):  RX errors:0 dropped:0 | TX errors:0 dropped:0
eth2 (Port 3):  RX errors:0 dropped:0 | TX errors:0 dropped:0
eth3 (Port 4):  RX errors:0 dropped:0 | TX errors:0 dropped:0  ← Problem port shows 0 errors!
eth4 (Port 5):  RX errors:0 dropped:0 | TX errors:0 dropped:0
```

### VLAN Interfaces: Normal

- All VLAN interfaces (br5, br40, br50, br60-65) showing traffic
- No errors on any bridge interface

### Conclusion from ER605 Logs

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

---

## Phase 1 — FS308GP Switch Logs Analysis

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

---

## Phase 1 — Detailed Flapping Pattern Analysis

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

## Phase 1 — Critical Discovery: Router Reboot Correlation

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

## Phase 1 — Permanent Fix: Migrate from Port 4 to Port 2

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

### Port Allocation After Phase 1 Fix

| Port | Function | Status |
|------|----------|--------|
| Port 1 | WAN (ISP) | ✅ Active |
| Port 2 | **Dev_SVC trunk** | ✅ Active (moved here) |
| Port 3 | Prod_SVC trunk | ✅ Active |
| Port 4 | ~~Dev_SVC~~ | ❌ **Defective - Abandoned** |
| Port 5 | Reserved | Available |

### Phase 1 Result

✅ **Dev SVC network stable** - no more flapping after migration to Port 2.

---

## Phase 1 — Summary

**Issue**: ER605 Port 4 PHY hardware defect causing persistent link flapping (445 events in 22 hours).

**Root Cause (Suspected)**: Physical layer (PHY) chip failure - port cannot maintain stable Gigabit or 100M link.

**Evidence**:
- Switch logs: 445 link down events on Port 3 (connected to ER605 Port 4)
- ER605 logs: LAN4 flapping immediately after every reboot
- Router uptime correlated exactly with first flap timestamp
- All other ports stable

**Temporary Fix**: 100M Full-duplex + Flow Control (reduced severity but didn't eliminate)

**Permanent Fix**: Migrated Dev_SVC trunk from Port 4 to Port 2

**Status**: ⚠️ Appeared resolved - but would recur in Phase 2

---

# ═══════════════════════════════════════════════════════════════════
# PHASE 2: Switch Port 4 Link Flapping — "Loose Cable" Investigation
# Date: 2026-03-22 (next day)
# Duration: ~1.5 hours troubleshooting
# Result: FALSELY RESOLVED (root cause was wrong)
# ═══════════════════════════════════════════════════════════════════

## Phase 2 — Related to Phase 1

**Previous Day (2026-03-21)**: ER605 Router Port 4 failure - migrated to Port 2
- That issue was diagnosed as router-side PHY failure
- Today's issue is on switch Port 4 (Proxmox connection), different location
- Same symptom pattern though

---

## Phase 2 — Symptoms

- All Dev VMs/LXCs lost connectivity to gateway intermittently
- VMs could ping gateway briefly, then connection dropped for ~30 seconds
- Pattern: Works → Fails → Works → Fails (cyclical)
- Proxmox `svc0` interface showing link flapping in dmesg

**From FreeIPA VM (10.0.60.10):**
```bash
[root@freeipa ~]# ping 10.0.60.1
PING 10.0.60.1 (10.0.60.1) 56(84) bytes of data.
From 10.0.60.10 icmp_seq=1 Destination Host Unreachable
From 10.0.60.10 icmp_seq=2 Destination Host Unreachable
...
```

**From NGINX LXC (10.0.65.10) - showing intermittent pattern:**
```bash
64 bytes from 10.0.65.1: icmp_seq=6 ttl=64 time=2.05 ms
64 bytes from 10.0.65.1: icmp_seq=7 ttl=64 time=1.95 ms
From 10.0.65.10 icmp_seq=40 Destination Host Unreachable
From 10.0.65.10 icmp_seq=41 Destination Host Unreachable
... (30+ seconds of unreachable)
64 bytes from 10.0.65.1: icmp_seq=94 ttl=64 time=1029 ms
64 bytes from 10.0.65.1: icmp_seq=95 ttl=64 time=4.12 ms
... (works for ~30 seconds)
From 10.0.65.10 icmp_seq=129 Destination Host Unreachable
... (cycle repeats)
```

---

## Phase 2 — Network Path

```
Proxmox Dev (svc0 NIC)
       │
       │ Ethernet cable ← LOOSE CONNECTION HERE (suspected)
       ▼
FS308GP Switch Port 4 (Dev_SVC downlink)
       │
       │ Internal switch fabric
       ▼
FS308GP Switch Port 3 (Dev_SVC_ALL trunk)
       │
       │ Trunk: VLANs 60-65
       ▼
ER605 Port 2 (Dev_SVC) ← Working fine (fixed yesterday)
       │
       ▼
Gateway (10.0.6x.1)
```

---

## Phase 2 — Troubleshooting Sequence

### Step 1: Initial VM-Level Diagnosis

**Goal**: Verify if VM networking is functional at Layer 2/3

**Commands executed on new test VM (DHCP):**
```bash
# Check IP assignment
ip a
# Result: 10.0.63.200/24 assigned via DHCP ✓

# Self-ping
ping 10.0.63.200
# Result: Works ✓

# Gateway ping
ping 10.0.63.1
# Result: Hanging, no response ✗
```

**DHCP Server Log (Router):**
```
2026-03-22 11:49:10  DHCP Server allocated IP address 10.0.63.200 for [client:XX:XX:XX:XX:XX:XX]
```

**Analysis**: DHCP works (Layer 2 broadcast successful), but Layer 3 routing fails.

---

### Step 2: ARP/MAC Layer Check

**Goal**: Verify if Layer 2 communication reaches gateway

**Commands:**
```bash
# Check ARP resolution
arping -I ens18 10.0.63.1
```

**Result:**
```
ARPING 10.0.63.1 from 10.0.63.200 ens18
Unicast reply from 10.0.63.1 [XX:XX:XX:XX:XX:XX]  2.551ms
Unicast reply from 10.0.63.1 [XX:XX:XX:XX:XX:XX]  2.531ms
Unicast reply from 10.0.63.1 [XX:XX:XX:XX:XX:XX]  2.477ms
```

**Analysis**:
- ARP works ✓ (Layer 2 OK)
- Gateway MAC learned: `XX:XX:XX:XX:XX:XX`
- But ICMP ping fails (Layer 3 issue or intermittent connectivity)

---

### Step 3: Proxmox Host Network Check

**Goal**: Verify Proxmox host connectivity and interface status

**Commands:**
```bash
# Check interfaces
cat /etc/network/interfaces

# Check link status
ip a

# WiFi management (VLAN 5) - test path
ping 10.0.5.1
# Result: Works ✓

ping 10.0.5.110
# Result: Works (self) ✓
```

**Key finding**: WiFi management plane works, only `svc0` (service VLAN trunk) affected.

**Interface status:**
```
3: svc0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
5: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
```

Interfaces show UP but traffic not passing.

---

### Step 4: Router-Side Diagnosis

**Goal**: Check if router can reach VMs

**Router diagnostic tool** (ER605 Web UI → Diagnostics → Ping):
```
Destination IP: 10.0.60.10
Interface: Dev_Identity

Result:
PING 10.0.60.10 (10.0.60.10) from 10.0.60.1: 64 data bytes
Request timed out!
Request timed out!
Request timed out!
Request timed out!
```

**Analysis**: Router cannot ping VMs either - bidirectional failure. Issue is between switch and Proxmox.

---

### Step 5: Proxmox dmesg Analysis (CRITICAL FINDING)

**Goal**: Check kernel logs for network events

**Command:**
```bash
dmesg -T | grep svc0 | tail -30
```

**Result - LINK FLAPPING DETECTED:**
```
[Sun Mar 22 11:43:16 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered forwarding state
[Sun Mar 22 11:43:20 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 11:43:23 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 11:43:23 2026] vmbr0: port 1(svc0) entered forwarding state
... (pattern repeats every 2-3 seconds)
```

**Analysis**: Bridge port constantly cycling: disabled → blocking → forwarding → disabled

---

### Step 6: ethtool Link Status Check

**Command:**
```bash
ethtool svc0
```

**Result:**
```
Settings for svc0:
    Speed: Unknown!
    Duplex: Unknown! (255)
    Auto-negotiation: off
    Link detected: no    ← LINK DOWN!
```

**Analysis**: Physical link is DOWN. The interface shows UP in `ip a` because it's a bridge port, but actual physical link is lost.

---

### Step 7: Switch Log Analysis

**Location**: `logs/new port 4 down /syslog.log`

**Port 4 (Gi1/0/4) - Proxmox connection:**
```
#2026-03-22 12:08:50,[Link]/5/Gi1/0/4 changed state to up.
#2026-03-22 12:08:43,[Link]/5/Gi1/0/4 changed state to down.
#2026-03-22 12:08:34,[Link]/5/Gi1/0/4 changed state to up.
#2026-03-22 12:08:31,[Link]/5/Gi1/0/4 changed state to down.
#2026-03-22 12:08:31,[Link]/5/Gi1/0/4 changed state to up.
#2026-03-22 12:08:05,[Link]/5/Gi1/0/4 changed state to down.
... (100+ events in 25 minutes)
```

**Timeline Analysis:**
| Time | Event |
|------|-------|
| 2026-03-21 19:47:30 | Last stable state before server shutdown |
| 2026-03-21 23:00 | Server shutdown (expected link down) |
| 2026-03-22 08:45:42 | Server boot - link comes up |
| 2026-03-22 09:52-09:58 | Normal boot negotiation (brief flaps OK) |
| **2026-03-22 11:43:16** | **First ABNORMAL flap - problem starts** |
| 2026-03-22 11:43 - 12:08 | Continuous flapping (every 2-6 seconds) |

**Port 3 Check (yesterday's issue):**
```bash
grep "Gi1/0/3" syslog.log | grep "2026-03-22"
# Result: No events
```

**Confirmed**: Port 3 (router uplink) stable since yesterday's fix. Only Port 4 affected.

---

### Step 8: Switch UI Status

**Switch Web UI showed:**
| Port | Status | Profile |
|------|--------|---------|
| Port 3 | Orange (warning) | Dev_SVC... |
| Port 4 | Gray (down/abnormal) | Dev_SVC... |

---

### Step 9: Rule Out Candidates

| Component | Status | Evidence |
|-----------|--------|----------|
| Cable | Changed yesterday | Same issue with new cable |
| Router port | Changed yesterday (Port 4 → Port 2) | Port 2 working, no flaps |
| Switch Port 3 (uplink) | Stable | No logs after yesterday fix |
| **Switch Port 4 (Proxmox)** | **FLAPPING** | 100+ events in switch log |
| **Proxmox NIC (svc0)** | **Link down** | ethtool shows no link |

**Isolation needed**: Is it Switch Port 4 or Proxmox NIC?

---

## Phase 2 — Solution Applied

### Action Taken

**Reseat cable on both ends:**

1. Unplug cable from Proxmox NIC (svc0 USB-Ethernet adapter)
2. Plug back firmly
3. Unplug cable from Switch Port 4
4. Plug back firmly

### Result

```bash
dmesg -T | grep svc0 | tail -5
```

**Output:**
```
[Sun Mar 22 12:11:11 2026] vmbr0: port 1(svc0) entered forwarding state
[Sun Mar 22 12:11:17 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 12:11:23 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 12:11:23 2026] vmbr0: port 1(svc0) entered forwarding state
```

**Link stable since 12:11:23** - no more flapping.

**Verification:**
```bash
ping 10.0.63.1
# Result: Works ✓

ping 10.0.60.10  # (from another VM)
# Result: Works ✓
```

---

## Phase 2 — Root Cause (WRONG - Later Disproven)

**Loose cable connection** - either at Proxmox USB-Ethernet adapter or Switch Port 4.

The connector was not fully seated, causing intermittent electrical contact:
- Good contact → Link up → Traffic flows
- Contact breaks → Link down → "Destination Host Unreachable"
- Cycle repeats every few seconds

---

## Phase 2 — Why DHCP Worked But Ping Failed

| Protocol | Behavior | Result |
|----------|----------|--------|
| DHCP | Broadcast, retries automatically | Succeeded during brief "up" window |
| ARP | Broadcast, cached | Succeeded, MAC learned |
| ICMP Ping | Unicast, requires stable connection | Failed during "down" windows |

DHCP and ARP are more tolerant of intermittent connectivity because they use broadcasts and have retry mechanisms. ICMP ping requires continuous unicast connectivity.

---

## Phase 2 — Commands Reference

### VM/LXC Level
```bash
ip a                              # Check IP assignment
ping <gateway>                    # Test connectivity
arping -I <interface> <gateway>   # Test Layer 2 ARP
```

### Proxmox Host Level
```bash
cat /etc/network/interfaces       # Check network config
ip a                              # Check interface status
ethtool <interface>               # Check link status (speed, duplex, link detected)
dmesg -T | grep <interface>       # Check kernel logs with timestamps
ip -s link show <interface>       # Check interface statistics/errors
```

### Switch Level
```bash
# Collect from switch diagnostic export:
syslog.log                        # Link state changes
switchCfg.cfg                     # Current configuration
cpuUtilization.txt                # CPU health
meminfo                           # Memory health
```

---

## Phase 2 — Evidence Files

Collected in: `logs/new port 4 down /`

| File | Content |
|------|---------|
| syslog.log | 100+ link flap events on Gi1/0/4 |
| switchCfg.cfg | Switch configuration |
| cpuUltilization.txt | Switch CPU (normal: 1-8%) |
| meminfo | Switch memory (normal: 29% free) |
| dmesg | Switch boot logs |

---

## Phase 2 — Lessons Learned (Later Proven Incomplete)

1. **Check physical layer first** - loose cables cause intermittent issues that look like complex problems
2. **dmesg reveals link flapping** - `entered disabled state` cycling = physical layer issue
3. **ethtool shows true link status** - `Link detected: no` is definitive
4. **DHCP success doesn't mean network is healthy** - broadcasts are resilient, unicast is not
5. **ARP can mislead** - getting ARP replies doesn't mean stable connectivity
6. **Switch logs confirm the issue** - correlate Proxmox dmesg with switch syslog
7. **Reseat before replacing** - simple fix solved complex-looking problem

---

## Phase 2 — Prevention (Later Updated)

1. **Use quality cables** - Cat6 minimum for Gigabit
2. **Secure connections** - ensure click/lock engages
3. **Avoid USB-Ethernet adapters** - less reliable than onboard NICs
4. **Monitor link status** - script to alert on link flaps
5. **Label cables** - easier to identify for troubleshooting

---

## Phase 2 — Monitoring Script (Optional)

```bash
#!/bin/bash
# Monitor link status on svc0
while true; do
    STATUS=$(cat /sys/class/net/svc0/operstate)
    if [ "$STATUS" != "up" ]; then
        echo "$(date): svc0 link DOWN!" | mail -s "Link Alert" admin@example.com
    fi
    sleep 10
done
```

---

## Phase 2 — Status

⚠️ **Falsely Resolved** - The "loose cable" diagnosis was WRONG. Issue would recur in Phase 3.

---

# ═══════════════════════════════════════════════════════════════════
# PHASE 3: Recurrence & Force 100M Resolution
# Date: 2026-03-26 (~4 days later)
# Duration: ~2+ hours troubleshooting
# Result: RESOLVED (actual fix found)
# ═══════════════════════════════════════════════════════════════════

## Phase 3 — Issue Returned

The link flapping issue recurred ~4 days later, despite:
- Reseating cable connections (Phase 2 fix)
- Replacing cables
- Replacing USB-Ethernet adapter
- Migrating from ER605 Port 4 to Port 2 (Phase 1 fix)

---

## Phase 3 — Symptoms

- Dev VMs cannot ping gateway (10.0.6x.1)
- Same-VLAN traffic works (VM to VM on same VLAN)
- Prod environment stable
- svc0 interface shows UP but no incoming traffic from router
- Kernel logs show svc0 entering "disabled state" intermittently

**Kernel evidence:**
```
[  807.326651] vmbr0: port 1(svc0) entered disabled state
[  826.782521] vmbr0: port 1(svc0) entered forwarding state
[ 1522.340213] vmbr0: port 1(svc0) entered disabled state
[ 1525.156136] vmbr0: port 1(svc0) entered forwarding state
```

**ethtool stats:**
```
tx_reason_timeout: 49635  <- High TX timeouts
```

---

## Phase 3 — Extended Troubleshooting

### Isolation Attempts

| Action | Result |
|--------|--------|
| Check switch VLAN config | Correct - VLANs 60-65 tagged on ports 3 & 4 |
| Check Proxmox bridge config | Correct - identical to working Prod |
| Changed USB-Ethernet adapter | Issue remained |
| Changed Ethernet cable | Issue remained |
| Changed server USB port | Issue remained |
| Swapped switch ports 3 ↔ 4 | Issue remained |
| Bypassed switch (direct to router) | Initially failed, then worked randomly |
| Tested with MikroTik router | Same issue occurred |

---

### Key Discovery

After swapping switch ports, both ports showed UP in switch logs but traffic still didn't flow.

**Test results:**
- Same-VLAN ping (VM to VM): **WORKS**
- Gateway ping: **FAILS**
- Problem isolated to: Switch ↔ ER605 uplink path

---

### Port Mirror Confusion

ER605 Port 2 had port mirroring enabled (leftover from Phase 1 debugging).

| Action | Result |
|--------|--------|
| Port 2 with mirror enabled | Traffic blocked |
| Changed to Port 4 | Traffic worked |
| Disabled mirror on Port 2 | Traffic worked |

But behavior was inconsistent - port mirror was "solution" in one case, "problem" in another.

---

### Final Fix Discovery

User recalled that **100M forced + flow control** was the original fix from Phase 1, but had been reverted to Auto at some point.

**Re-applied:**
- ER605 Port 4: 100M Full-duplex + Flow Control
- ER605 Port 2: 100M Full-duplex + Flow Control (if used)

**Result:** Stable connectivity restored.

---

## Phase 3 — Root Cause Analysis

### What We Know

1. **Prod server is always stable** - uses built-in 100M NIC
2. **Dev server is unstable** - uses USB Gigabit adapter
3. **Gigabit auto-negotiation fails** intermittently
4. **Forcing 100M resolves** the instability

### What We Don't Know

The exact hardware/firmware component causing the failure:
- ER605 PHY chip?
- USB-Ethernet adapter chipset (ASIX AX88179B)?
- Interaction between the two?
- EMI/power issue?

### Conclusion

**Root cause is UNIDENTIFIED** but workaround is confirmed.

---

## Phase 3 — Architecture Assessment

### Original Setup (Over-Engineered)

```
Server svc0 → Switch Port 4 → Switch Port 3 → ER605 Port 2
                    ↑
              Does nothing useful
```

The switch provides **zero benefit** for SVC traffic - just forwards tagged VLANs.

### Simplified Option

```
Server svc0 → ER605 Port (direct)
```

Fewer failure points, simpler troubleshooting.

### Decision

Keep switch for now, but acknowledge it adds complexity without benefit for SVC path.

---

## Phase 3 — Final Configuration

### ER605 Port Settings

| Port | Function | Speed | Flow Control |
|------|----------|-------|--------------|
| Port 2 | Dev SVC uplink | **100M Full** | **Enabled** |
| Port 4 | Dev SVC (backup) | **100M Full** | **Enabled** |
| Port 5 | Prod SVC uplink | Auto (100M default) | Enabled |

### Why Prod Doesn't Need Forcing

Prod server uses **built-in Ethernet NIC** which negotiates at 100M by default. The instability only occurs with USB Gigabit adapters attempting Gigabit negotiation.

---

## Phase 3 — Previous False Root Causes Identified

| Phase | Suspected Cause | Why It Was Wrong |
|-------|-----------------|------------------|
| Phase 1 | ER605 Port 4 PHY failure | Migrating to Port 2 didn't fix it |
| Phase 2 | Loose cable connection | Replacing cables didn't fix it |
| Phase 2 | Bad USB-Ethernet adapter | Replacing adapter didn't fix it |
| Phase 3 | Switch port issue | Swapping ports didn't fix it |

---

## Phase 3 — Why Each "Fix" Appeared to Work Temporarily

| "Fix" | Why It Seemed to Work |
|-------|----------------------|
| Cable reseat | Random timing — link was cycling anyway |
| 100M forced | Actually works — bypasses broken negotiation |
| Port migration | Coincidental stability window |
| Flow control | Minor improvement, not the solution |

---

## Phase 3 — Recommendations

### Immediate

- [x] Force 100M on all SVC router ports
- [x] Disable port mirror when not actively debugging
- [x] Update documentation with recurrence info

### Future Considerations

- Consider removing switch from SVC path (direct server → router)
- Consider replacing USB adapters with PCIe NICs
- Consider replacing ER605 with MikroTik (more diagnostic capability)

---

## Phase 3 — Status

✅ **Stable** - All SVC ports forced to 100M from router side

**Monitor for:** Any future instability even at 100M (would indicate hardware failure requiring replacement)

---

# ═══════════════════════════════════════════════════════════════════
# PHASE 4: Driver Analysis Discovery
# Date: 2026-03-27 (next day)
# Duration: ~1 hour research
# Result: TRUE ROOT CAUSE IDENTIFIED
# ═══════════════════════════════════════════════════════════════════

## Phase 4 — Hardware Discovery

| Component | Details |
|-----------|---------|
| Dev Server | **ASUS VivoBook 15** (economy laptop) |
| USB Adapter | **UGREEN 2.5G** (ASIX AX88179B chipset) |
| USB Topology | Single physical chip, multiple ports |
| Prod Server | Dedicated laptop with **built-in Ethernet** on mainboard |

---

## Phase 4 — Driver Investigation

**Problem Identified:** The AX88179B adapter is using the **wrong kernel driver**.

```bash
# Expected driver
driver: ax88179_178a  (native ASIX driver with proper negotiation)

# Actual driver in use
driver: cdc_ncm       (generic CDC NCM fallback - limited functionality)
```

**ethtool output with cdc_ncm:**
```
Speed: 100Mb/s
Duplex: Unknown! (255)    <- PROBLEM: No duplex negotiation
Auto-negotiation: off
Link detected: yes
```

---

## Phase 4 — Why cdc_ncm Causes Instability

The `cdc_ncm` driver is a **generic USB network driver** that:
- Does NOT support proper speed/duplex negotiation
- Shows "Duplex: Unknown! (255)"
- Cannot communicate link parameters to switch/router
- Causes intermittent link flapping

The native `ax88179_178a` driver:
- Supports full auto-negotiation
- Reports correct speed/duplex
- Handles link state properly

---

## Phase 4 — Attempted Fix

```bash
# 1. Driver module exists
modinfo ax88179_178a  # ✓ Available in kernel

# 2. Loaded the proper driver
modprobe ax88179_178a  # ✓ Loaded

# 3. But adapter still binds to cdc_ncm first
ethtool -i svc0  # Still shows driver: cdc_ncm
```

**Root Cause:** The AX88179B presents itself as a CDC NCM device first, and the kernel binds to `cdc_ncm` before `ax88179_178a` can claim it.

---

## Phase 4 — Proposed Permanent Fix

Blacklist `cdc_ncm` to force binding to native driver:

```bash
# Create blacklist
echo "blacklist cdc_ncm" > /etc/modprobe.d/blacklist-cdc_ncm.conf

# Update initramfs
update-initramfs -u

# Reboot
```

**Status:** Pending testing

---

## Phase 4 — Why Prod Server is Stable

| Server | NIC Type | Driver | Negotiation | Stability |
|--------|----------|--------|-------------|-----------|
| **Dev** (VivoBook 15) | USB adapter (AX88179B) | cdc_ncm (wrong) | Broken | ❌ Unstable |
| **Prod** | Built-in Ethernet | Native driver | Works | ✅ Stable |

The Prod server has a **dedicated Ethernet port on the mainboard**, which uses native drivers with proper negotiation. It defaults to 100M naturally without issues.

---

## Phase 4 — Current Configuration

Both Dev and Prod SVC cables connected to **router** (not through switch):

| Server | Cable Path | Router Port | Speed Setting |
|--------|------------|-------------|---------------|
| Dev | Direct to router | Port 2 or 4 | 100M Forced |
| Prod | Direct to router | Port 5 | Auto (100M default) |

---

## Phase 4 — Next Steps

- [ ] Reboot Dev server with `cdc_ncm` blacklisted
- [ ] Verify `ax88179_178a` driver binds on boot
- [ ] Test if proper driver allows Gigabit without flapping
- [ ] If still unstable, keep 100M forced as permanent workaround
- [ ] Consider replacing USB adapter with PCIe NIC for Dev server

---

# ═══════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════

## 4. Root Cause (FINAL)

> **Multi-layered issue with true root cause discovered in Phase 4:**
>
> **Primary:** Wrong kernel driver (`cdc_ncm` instead of `ax88179_178a`) causing broken duplex negotiation on USB-Ethernet adapter
>
> **Secondary:** USB Gigabit adapters + ER605 Gigabit auto-negotiation = unreliable combination
>
> **Red herrings that were NOT the root cause:**
> - Loose cables (Phase 2)
> - ER605 Port 4 PHY failure (Phase 1)
> - Switch port issues (Phase 3)
> - Bad USB adapter (Phase 3)

## 5. Solution

> **Working fix:** Force 100M Full-duplex on all SVC router ports.

**Final Configuration:**
| Port | Function | Speed | Flow Control |
|------|----------|-------|--------------|
| ER605 Port 2 | Dev SVC uplink | **100M Full** | **Enabled** |
| ER605 Port 4 | Dev SVC (backup) | **100M Full** | **Enabled** |
| ER605 Port 5 | Prod SVC uplink | Auto (100M default) | Enabled |

**Permanent fix (pending testing):**
```bash
echo "blacklist cdc_ncm" > /etc/modprobe.d/blacklist-cdc_ncm.conf
update-initramfs -u
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Dev SVC limited to 100Mbps (sufficient — ISP is 30-70 Mbps anyway)

## 7. Impact After Fix
- Observed: All SVC ports stable at 100M
- No more link flapping
- Dev and Prod environments both functional

## 8. Notes

### Complete Investigation Timeline

| Phase | Date | Duration | Suspected Cause | Actual Status |
|-------|------|----------|-----------------|---------------|
| 1 | 2026-03-21 | ~45 min | ER605 Port 4 PHY failure | ❌ Wrong |
| 2 | 2026-03-22 | ~1.5 hrs | Loose cable connection | ❌ Wrong |
| 3 | 2026-03-26 | ~2+ hrs | Various (all wrong) | ✅ Force 100M works |
| 4 | 2026-03-27 | ~1 hr | Driver binding issue | ✅ TRUE ROOT CAUSE |

### Key Diagnostic Commands

**Proxmox Host:**
```bash
dmesg -T | grep svc0           # Link flapping evidence
ethtool svc0                   # Link status, speed, duplex
ethtool -i svc0                # Driver info (critical!)
ip -s link show svc0           # Interface statistics
```

**Switch (FS308GP):**
```bash
# Collect syslog.log from diagnostic export
grep "Gi1/0/4" syslog.log      # Link state changes
```

**Router (ER605):**
```bash
ssh -o HostKeyAlgorithms=+ssh-rsa admin@10.0.5.1
ifconfig                        # Interface errors
```

### Lessons Learned (Complete)

1. **Previous "root causes" were incomplete** — loose cable and PHY failure were symptoms
2. **USB Gigabit adapters are unreliable** with ER605 at Gigabit speeds
3. **Driver matters critically** — `cdc_ncm` vs `ax88179_178a` makes huge difference
4. **"Duplex: Unknown! (255)" is a red flag** — indicates broken negotiation
5. **100M is sufficient** — especially when ISP is slower anyway
6. **Document workarounds even without confirmed root cause**
7. **Intermittent issues may need multiple investigation sessions over days**
8. **Economy laptops have shared USB controllers** — single chip, multiple ports
9. **Built-in NICs are more reliable** than USB adapters
10. **Kernel driver binding order** can cause wrong driver to be used
11. **Switch in SVC path provides zero benefit** — adds complexity

### Architecture Recommendation

The switch provides **zero benefit** for SVC traffic path:
```
Current:    Server svc0 → Switch → Router  (unnecessary hop)
Simplified: Server svc0 → Router (direct)
```
Consider removing switch from SVC path in future.

## 9. Workaround (if any)
> **Current workaround:** Force 100M on all SVC router ports.
>
> **If 100M is unacceptable:** Blacklist `cdc_ncm` driver and test with native `ax88179_178a`.
>
> **If still unstable:** Replace USB adapter with PCIe NIC.
