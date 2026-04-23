# TS-NET-003 | 2026-03-21 to 2026-03-27 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Network / Physical Layer
Sub-techs: USB-Ethernet (ASIX AX88179B), ER605 Router, FS308GP Switch, Kernel Driver Binding
Environment: Proxmox Dev server -> FS308GP Switch -> ER605 Router (Dev SVC VLANs 60-65)
Re-opened: Yes (4 phases over 6 days, ~6+ hours troubleshooting)
_____________________________________________________________________

[Issue Description]

Dev VMs intermittently lose gateway connectivity. Pattern: Works -> Fails -> Works (cyclical every 2-30 seconds).

```
From 10.0.60.10 icmp_seq=1 Destination Host Unreachable
From 10.0.60.10 icmp_seq=2 Destination Host Unreachable
```

Kernel evidence (link flapping):
```
[Sun Mar 22 11:43:16 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered forwarding state
[Sun Mar 22 11:43:20 2026] vmbr0: port 1(svc0) entered disabled state
... (pattern repeats every 2-3 seconds)
```

Key observation: Prod environment always stable, only Dev affected.
_____________________________________________________________________

[Analysis]

# Phase 1: ER605 Port 4 Gigabit Negotiation Failure
Date: 2026-03-21 | Duration: ~45 min | Result: PARTIALLY RESOLVED (issue recurred)

## Symptoms

All Dev VMs/LXCs lost connectivity to gateway. VMs could see their own IPs but couldn't ping gateway (10.0.6x.1). Proxmox svc0 interface showed UP state. Inter-VLAN routing not working.

From k8s-master1 (10.0.61.10):
```
ping 10.0.61.1
PING 10.0.61.1 (10.0.61.1) 56(84) bytes of data.
From 10.0.61.10 icmp_seq=1 Destination Host Unreachable
ping: sendmsg: No route to host

traceroute to 10.0.61.1
1  k8s-master1.lab.local (10.0.61.10)  3069.872 ms !H  3069.831 ms !H
```

Proxmox interface status:
```
3: svc0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
```

## Network Path

```
Proxmox Dev (svc0)
       |
       | VLAN tagged traffic (60-65)
       v
FS308GP Switch Port 7
       |
       | Internal switch fabric
       v
FS308GP Switch Port 3 (Dev_SVC_ALL trunk)
       |
       | Trunk: VLANs 60-65
       v
ER605 Port 4 (Dev_SVC) <-- PROBLEM HERE
       |
       v
Gateway (10.0.6x.1)
```

## Troubleshooting Sequence

### Test 1: Initial Physical Check

| Check | Result |
|-------|--------|
| Proxmox svc0 interface | UP |
| Router (ER605) LEDs | All UP |
| Switch (FS308GP) LEDs | All UP except Port 3 |
| Switch Web UI - Port 3 | `Dev_SVC_ALL` showed **offline** |

Action: Reseat cable on Switch Port 3
Result: Service restored temporarily

Initial Hypothesis: Loose cable connection
Outcome: WRONG - issue recurred

### Test 2: Cable Replacement

Action: Replaced Ethernet cable between FS308GP Port 3 and ER605 Port 4
Result: Issue recurred after ~1 minute

Hypothesis: Faulty cable
Outcome: WRONG - new cable had same issue

### Test 3: PVID Change (Isolate Router vs Switch)

Action: Changed ER605 Port 4 PVID from 60 to 61
Result: Port came online briefly when config applied, then went offline again

The act of saving config on ER605 triggered port reconnection, confirming issue is on **router side**, not switch side.

Hypothesis: Switch port issue
Outcome: WRONG - confirmed router side

### Test 4: Spontaneous Recovery

Port came back online without any intervention while I was discussing the issue. Intermittent failure pattern - worst kind to troubleshoot.

### Test 5: Switch Port Settings Adjustment

Changes on FS308GP Port 3:
| Setting | Before | After |
|---------|--------|-------|
| Flow Control | Disabled | Enabled |
| PoE | Off | Default |
| LLDP-MED | Enabled | Disabled |

Result: Issue recurred - port went down again. Switch settings unrelated.

### Test 6: Force 100M + Flow Control on ER605 (TEMPORARY SOLUTION)

Changes on ER605 Port 4:
| Setting | Before | After |
|---------|--------|-------|
| Speed/Duplex | Auto | 100M Full-duplex |
| Flow Control | Disabled | Enabled |

Result: Port stable for 30+ minutes - APPEARED RESOLVED.

## Root Cause Hypothesis

Gigabit auto-negotiation failure on ER605 Port 4. The port was failing to maintain stable Gigabit link. Possible causes:
- ER605 Port 4 PHY (physical layer chip) degrading
- Firmware bug in auto-negotiation
- Signal integrity issues at Gigabit speeds
- Incompatibility between ER605 and FS308GP at Gigabit

Forcing 100M Full-duplex bypasses the problematic Gigabit negotiation.

## Why Port Migration Was Not Chosen

Recommendation given: Move trunk from ER605 Port 4 to Port 5.

I decided to keep Port 5 available for potential Prod expansion. Port 5 is the last available port on ER605 and may be needed for a future Prod network segment. 100M speed is sufficient for Dev environment - ISP speed is only 30-70 Mbps anyway.

Trade-off accepted: Dev SVC runs at 100M instead of 1G, port preserved for Prod.

## Configuration After Fix

ER605 Port 4 (Dev_SVC):
- Speed: 100M Full-duplex (forced)
- Flow Control: Enabled
- PVID: 60
- Tagged VLANs: 60, 61, 62, 63, 64, 65

## Update: Ongoing Intermittent Failure

Even with 100M Full-duplex + Flow Control, port still drops intermittently.

| Pattern | Details |
|---------|---------|
| Frequency | ~Every 2 hours |
| Duration | ~30 seconds |
| Impact | Dev SVC network briefly unreachable |

Conclusion: ER605 Port 4 is hardware defective. The 100M + Flow Control setting reduced frequency but did not eliminate the issue.

I decided to accept this for now since it's Dev environment only. Prod uses different port (Port 3) which is stable.

## ER605 Diagnostic Logs Analysis

I SSH'd into the ER605 to investigate Port 4 intermittent failures.

```bash
ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa admin@10.0.5.1
```

Note: ER605 uses legacy SSH key algorithms (ssh-rsa), requiring explicit compatibility flags.

| Command | Purpose | Result |
|---------|---------|--------|
| `ps` | Process list | Normal - ~50 processes running |
| `ifconfig` | Interface status | All interfaces UP, **0 errors** on all ports |
| `netstat -rn` | Routing table | Correct routes for all VLANs |
| `iptables -L -n -v` | Firewall rules | Normal NAT/filter rules |
| `top` (snapshot) | CPU/Memory | CPU ~3%, Memory ~50% free |
| `df` | Disk usage | tmpfs filesystems, plenty of space |

System health: Normal. CPU ~3%, Memory ~50% free (32MB used of 64MB). No runaway processes.

Network interfaces showed no errors:
```
eth0 (WAN):     RX errors:0 dropped:0 | TX errors:0 dropped:0
eth1 (Port 2):  RX errors:0 dropped:0 | TX errors:0 dropped:0
eth2 (Port 3):  RX errors:0 dropped:0 | TX errors:0 dropped:0
eth3 (Port 4):  RX errors:0 dropped:0 | TX errors:0 dropped:0  <- Problem port shows 0 errors!
eth4 (Port 5):  RX errors:0 dropped:0 | TX errors:0 dropped:0
```

All VLAN interfaces (br5, br40, br50, br60-65) showing traffic, no errors on any bridge interface.

The Port 4 failure is NOT visible in software-level diagnostics.

| Layer | Status | Evidence |
|-------|--------|----------|
| Software/OS | Normal | CPU, memory, processes all healthy |
| Network stack | Normal | 0 errors reported on eth3 |
| Firewall | Normal | Rules correct, no drops |
| **PHY/Hardware** | **Suspected** | Issue occurs below software visibility |

The intermittent link drops are happening at the physical layer (PHY) - the hardware component that handles electrical signaling and auto-negotiation. This level of failure is not logged by the Linux kernel on ER605, shows no errors in ifconfig statistics, and cannot be diagnosed via SSH/CLI.

## FS308GP Switch Logs Analysis

I collected switch diagnostic exports to correlate with ER605 Port 4 failures.

| File | Content |
|------|---------|
| syslog.log | System events including link state changes |
| switchCfg.cfg | Running configuration |
| cpuUltilization.txt | CPU usage |
| meminfo | Memory stats |
| dmesg | Kernel boot messages |
| ecs.log | Cloud controller logs |

### Critical Finding: Link Flapping

Switch Port 3 (Gi1/0/3) - connected to ER605 Port 4:
```
#2026-03-21 19:01:41,[Link]/5/Gi1/0/3 changed state to down.
#2026-03-21 19:01:41,[Link]/5/Gi1/0/3 changed state to up.
#2026-03-21 19:01:35,[Link]/5/Gi1/0/3 changed state to down.
#2026-03-21 19:01:31,[Link]/5/Gi1/0/3 changed state to up.
#2026-03-21 19:01:29,[Link]/5/Gi1/0/3 changed state to down.
... (pattern continues)
```

Total link down events in log: **445**

### Link State Change Comparison

| Port | Function | Link Events | Status |
|------|----------|-------------|--------|
| Gi1/0/2 | Prod_SVC trunk | 2 | Stable |
| **Gi1/0/3** | **Dev_SVC trunk (to ER605 Port 4)** | **445** | **FLAPPING** |
| Gi1/0/4 | Dev_SVC (Proxmox) | 6 | Normal |
| Gi1/0/5 | Prod_SVC (Proxmox) | 4 | Normal |
| Gi1/0/7 | Management | 1 | Normal |
| Gi1/0/8 | Management | 2 | Normal |

### Switch Health

| Metric | Value | Status |
|--------|-------|--------|
| CPU | 1-8% | Normal |
| Memory | 36MB free / 125MB (29%) | Normal |
| Load Average | 0.10 | Normal |
| Other Ports | Stable | Normal |

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

## Detailed Flapping Pattern Analysis

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

1. **Morning events ARE recorded before the 100M fix** - 348 link down events occurred before 17:40 (when 100M was applied). Confirms the issue existed throughout the day.

2. **100M + Flow Control DID provide temporary stability** - Clear 1-hour gap with zero flaps: 17:51 -> 18:55. This proves the fix had some effect.

3. **But the issue returned** - After 18:55, flapping resumed at severe rate. 40 events in 6 minutes.

4. **Pattern correlates with activity/heat**:
   - Worst: Daytime active hours (every 2-10 seconds)
   - Best: Early morning 03:00-08:00 (every 30-60 minutes)
   - Suggests thermal-related PHY degradation

### Thermal PHY Failure Hypothesis

```
Low activity (night) -> Less heat -> PHY more stable -> ~1 flap/hour
High activity (day)  -> More heat -> PHY unstable  -> ~1 flap/5 sec
100M mode           -> Less power -> Cooler        -> Temporarily stable
Continued operation -> Heat builds -> Failure returns
```

Conclusion: ER605 Port 4 PHY chip has thermal issues. Lower speeds generate less heat, temporarily masking the failure, but the underlying hardware is degrading.

## Critical Discovery: Router Reboot Correlation

### ER605 Uptime Analysis

Screenshot captured: Mar 21, 19:17:39

| Field | Value |
|-------|-------|
| System Time | 03/21/2026 19:17:39 |
| Running Time | 0 Day, 21 Hour, 43 Min, 41 Sec |
| **Calculated Reboot Time** | **Mar 20, ~21:33:58** |

### Switch Log Correlation

First flapping event in switch syslog:
```
#2026-03-20 21:33:20,[Link]/5/Gi1/0/3 changed state to down.
```

The timestamps align within seconds.

| Finding | Implication |
|---------|-------------|
| First flap = Router boot time | Flapping started **immediately** after reboot |
| No stable period after boot | Port 4 was broken from the moment it came online |
| Not gradual degradation | PHY hardware is **consistently faulty** |

The router reboot on Mar 20 ~21:33 was to change WireGuard VPN port (unrelated to Port 4). Port 4 started flapping the instant it came up after reboot. The PHY failure is not thermal/progressive - it's a persistent hardware defect. The port never worked correctly since the last reboot.

### Reboot Test Results (Mar 21, 19:37)

I rebooted the router to verify the pattern. ER605 logs confirm immediate flapping:

```
2026-03-21 19:37:42  [LAN4] was down
2026-03-21 19:37:34  [LAN4] was up
2026-03-21 19:37:33  [LAN4] was down
2026-03-21 19:37:23  [LAN4] was up
2026-03-21 19:37:22  [LAN4] was down
```

Verdict: Port 4 flaps immediately on cold boot - confirms persistent PHY hardware defect.

## Permanent Fix: Migrate from Port 4 to Port 2

Since Port 4 is hardware defective, I migrated the Dev_SVC trunk to Port 2.

### Changes Made

ER605 Router:

| Setting | Port 4 (Old - Defective) | Port 2 (New) |
|---------|--------------------------|--------------|
| Function | Dev_SVC trunk | Dev_SVC trunk |
| Tagged VLANs | 60, 61, 62, 63, 64, 65 | 60, 61, 62, 63, 64, 65 |
| PVID | 60 | 60 |
| Status | **Abandoned** | **Active** |

Additional: Port Mirroring configured (Port 4 -> Port 2, Ingress+Egress) for any residual traffic.

FS308GP Switch:

| Setting | Before | After |
|---------|--------|-------|
| Port 3 destination | ER605 Port 4 | ER605 Port 2 |

### New Network Path

```
Proxmox Dev (svc0)
       |
       | VLAN tagged traffic (60-65)
       v
FS308GP Switch Port 7
       |
       | Internal switch fabric
       v
FS308GP Switch Port 3 (Dev_SVC_ALL trunk)
       |
       | Trunk: VLANs 60-65
       v
ER605 Port 2 (Dev_SVC) <-- NEW - Healthy port
       |
       v
Gateway (10.0.6x.1)
```

### Port Allocation After Phase 1 Fix

| Port | Function | Status |
|------|----------|--------|
| Port 1 | WAN (ISP) | Active |
| Port 2 | **Dev_SVC trunk** | Active (moved here) |
| Port 3 | Prod_SVC trunk | Active |
| Port 4 | ~~Dev_SVC~~ | **Defective - Abandoned** |
| Port 5 | Reserved | Available |

### Phase 1 Result

Dev SVC network stable - no more flapping after migration to Port 2.

---

# Phase 2: Switch Port 4 Link Flapping -- "Loose Cable" Investigation
Date: 2026-03-22 (next day) | Duration: ~1.5 hrs | Result: FALSELY RESOLVED (root cause was wrong)

## Related to Phase 1

Previous Day (2026-03-21): ER605 Router Port 4 failure - migrated to Port 2. That issue was diagnosed as router-side PHY failure. Today's issue is on switch Port 4 (Proxmox connection), different location but same symptom pattern.

## Symptoms

All Dev VMs/LXCs lost connectivity to gateway intermittently. VMs could ping gateway briefly, then connection dropped for ~30 seconds. Pattern: Works -> Fails -> Works -> Fails (cyclical). Proxmox `svc0` interface showing link flapping in dmesg.

From FreeIPA VM (10.0.60.10):
```bash
[root@freeipa ~]# ping 10.0.60.1
PING 10.0.60.1 (10.0.60.1) 56(84) bytes of data.
From 10.0.60.10 icmp_seq=1 Destination Host Unreachable
From 10.0.60.10 icmp_seq=2 Destination Host Unreachable
...
```

From NGINX LXC (10.0.65.10) - showing intermittent pattern:
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

## Network Path

```
Proxmox Dev (svc0 NIC)
       |
       | Ethernet cable <-- LOOSE CONNECTION HERE (suspected)
       v
FS308GP Switch Port 4 (Dev_SVC downlink)
       |
       | Internal switch fabric
       v
FS308GP Switch Port 3 (Dev_SVC_ALL trunk)
       |
       | Trunk: VLANs 60-65
       v
ER605 Port 2 (Dev_SVC) <-- Working fine (fixed yesterday)
       |
       v
Gateway (10.0.6x.1)
```

## Troubleshooting Sequence

### Step 1: Initial VM-Level Diagnosis

I checked if VM networking was functional at Layer 2/3.

```bash
# Check IP assignment
ip a
# Result: 10.0.63.200/24 assigned via DHCP

# Self-ping
ping 10.0.63.200
# Result: Works

# Gateway ping
ping 10.0.63.1
# Result: Hanging, no response
```

DHCP Server Log (Router):
```
2026-03-22 11:49:10  DHCP Server allocated IP address 10.0.63.200 for [client:XX:XX:XX:XX:XX:XX]
```

DHCP works (Layer 2 broadcast successful), but Layer 3 routing fails.

### Step 2: ARP/MAC Layer Check

```bash
arping -I ens18 10.0.63.1
```

Result:
```
ARPING 10.0.63.1 from 10.0.63.200 ens18
Unicast reply from 10.0.63.1 [XX:XX:XX:XX:XX:XX]  2.551ms
Unicast reply from 10.0.63.1 [XX:XX:XX:XX:XX:XX]  2.531ms
Unicast reply from 10.0.63.1 [XX:XX:XX:XX:XX:XX]  2.477ms
```

ARP works (Layer 2 OK), gateway MAC learned, but ICMP ping fails (Layer 3 issue or intermittent connectivity).

### Step 3: Proxmox Host Network Check

```bash
cat /etc/network/interfaces
ip a
ping 10.0.5.1    # WiFi management (VLAN 5) - Works
ping 10.0.5.110  # Self - Works
```

Key finding: WiFi management plane works, only `svc0` (service VLAN trunk) affected.

Interface status:
```
3: svc0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
5: vmbr0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP
```

Interfaces show UP but traffic not passing.

### Step 4: Router-Side Diagnosis

I checked if the router can reach VMs using ER605 Web UI diagnostics:
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

Router cannot ping VMs either - bidirectional failure. Issue is between switch and Proxmox.

### Step 5: Proxmox dmesg Analysis (CRITICAL FINDING)

```bash
dmesg -T | grep svc0 | tail -30
```

LINK FLAPPING DETECTED:
```
[Sun Mar 22 11:43:16 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 11:43:19 2026] vmbr0: port 1(svc0) entered forwarding state
[Sun Mar 22 11:43:20 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 11:43:23 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 11:43:23 2026] vmbr0: port 1(svc0) entered forwarding state
... (pattern repeats every 2-3 seconds)
```

Bridge port constantly cycling: disabled -> blocking -> forwarding -> disabled.

### Step 6: ethtool Link Status Check

```bash
ethtool svc0
```

```
Settings for svc0:
    Speed: Unknown!
    Duplex: Unknown! (255)
    Auto-negotiation: off
    Link detected: no    <- LINK DOWN!
```

Physical link is DOWN. The interface shows UP in `ip a` because it's a bridge port, but actual physical link is lost.

### Step 7: Switch Log Analysis

Location: `logs/new port 4 down /syslog.log`

Port 4 (Gi1/0/4) - Proxmox connection:
```
#2026-03-22 12:08:50,[Link]/5/Gi1/0/4 changed state to up.
#2026-03-22 12:08:43,[Link]/5/Gi1/0/4 changed state to down.
#2026-03-22 12:08:34,[Link]/5/Gi1/0/4 changed state to up.
#2026-03-22 12:08:31,[Link]/5/Gi1/0/4 changed state to down.
#2026-03-22 12:08:31,[Link]/5/Gi1/0/4 changed state to up.
#2026-03-22 12:08:05,[Link]/5/Gi1/0/4 changed state to down.
... (100+ events in 25 minutes)
```

Timeline Analysis:
| Time | Event |
|------|-------|
| 2026-03-21 19:47:30 | Last stable state before server shutdown |
| 2026-03-21 23:00 | Server shutdown (expected link down) |
| 2026-03-22 08:45:42 | Server boot - link comes up |
| 2026-03-22 09:52-09:58 | Normal boot negotiation (brief flaps OK) |
| **2026-03-22 11:43:16** | **First ABNORMAL flap - problem starts** |
| 2026-03-22 11:43 - 12:08 | Continuous flapping (every 2-6 seconds) |

Port 3 Check (yesterday's issue):
```bash
grep "Gi1/0/3" syslog.log | grep "2026-03-22"
# Result: No events
```

Confirmed: Port 3 (router uplink) stable since yesterday's fix. Only Port 4 affected.

### Step 8: Switch UI Status

| Port | Status | Profile |
|------|--------|---------|
| Port 3 | Orange (warning) | Dev_SVC... |
| Port 4 | Gray (down/abnormal) | Dev_SVC... |

### Step 9: Rule Out Candidates

| Component | Status | Evidence |
|-----------|--------|----------|
| Cable | Changed yesterday | Same issue with new cable |
| Router port | Changed yesterday (Port 4 -> Port 2) | Port 2 working, no flaps |
| Switch Port 3 (uplink) | Stable | No logs after yesterday fix |
| **Switch Port 4 (Proxmox)** | **FLAPPING** | 100+ events in switch log |
| **Proxmox NIC (svc0)** | **Link down** | ethtool shows no link |

Isolation needed: Is it Switch Port 4 or Proxmox NIC?

## Solution Applied

I reseated the cable on both ends:
1. Unplugged cable from Proxmox NIC (svc0 USB-Ethernet adapter)
2. Plugged back firmly
3. Unplugged cable from Switch Port 4
4. Plugged back firmly

```bash
dmesg -T | grep svc0 | tail -5
```

```
[Sun Mar 22 12:11:11 2026] vmbr0: port 1(svc0) entered forwarding state
[Sun Mar 22 12:11:17 2026] vmbr0: port 1(svc0) entered disabled state
[Sun Mar 22 12:11:23 2026] vmbr0: port 1(svc0) entered blocking state
[Sun Mar 22 12:11:23 2026] vmbr0: port 1(svc0) entered forwarding state
```

Link stable since 12:11:23 - no more flapping.

Verification:
```bash
ping 10.0.63.1    # Works
ping 10.0.60.10   # Works (from another VM)
```

## Root Cause (WRONG - Later Disproven)

Loose cable connection - either at Proxmox USB-Ethernet adapter or Switch Port 4. The connector was not fully seated, causing intermittent electrical contact:
- Good contact -> Link up -> Traffic flows
- Contact breaks -> Link down -> "Destination Host Unreachable"
- Cycle repeats every few seconds

## Why DHCP Worked But Ping Failed

| Protocol | Behavior | Result |
|----------|----------|--------|
| DHCP | Broadcast, retries automatically | Succeeded during brief "up" window |
| ARP | Broadcast, cached | Succeeded, MAC learned |
| ICMP Ping | Unicast, requires stable connection | Failed during "down" windows |

DHCP and ARP are more tolerant of intermittent connectivity because they use broadcasts and have retry mechanisms. ICMP ping requires continuous unicast connectivity.

---

# Phase 3: Recurrence & Force 100M Resolution
Date: 2026-03-26 (~4 days later) | Duration: ~2+ hrs | Result: RESOLVED (actual fix found)

## Issue Returned

The link flapping issue recurred ~4 days later, despite:
- Reseating cable connections (Phase 2 fix)
- Replacing cables
- Replacing USB-Ethernet adapter
- Migrating from ER605 Port 4 to Port 2 (Phase 1 fix)

## Symptoms

Dev VMs cannot ping gateway (10.0.6x.1). Same-VLAN traffic works (VM to VM on same VLAN). Prod environment stable. svc0 interface shows UP but no incoming traffic from router. Kernel logs show svc0 entering "disabled state" intermittently.

```
[  807.326651] vmbr0: port 1(svc0) entered disabled state
[  826.782521] vmbr0: port 1(svc0) entered forwarding state
[ 1522.340213] vmbr0: port 1(svc0) entered disabled state
[ 1525.156136] vmbr0: port 1(svc0) entered forwarding state
```

ethtool stats:
```
tx_reason_timeout: 49635  <- High TX timeouts
```

## Extended Troubleshooting

### Isolation Attempts

| Action | Result |
|--------|--------|
| Check switch VLAN config | Correct - VLANs 60-65 tagged on ports 3 & 4 |
| Check Proxmox bridge config | Correct - identical to working Prod |
| Changed USB-Ethernet adapter | Issue remained |
| Changed Ethernet cable | Issue remained |
| Changed server USB port | Issue remained |
| Swapped switch ports 3 <-> 4 | Issue remained |
| Bypassed switch (direct to router) | Initially failed, then worked randomly |
| Tested with MikroTik router | Same issue occurred |

### Key Discovery

After swapping switch ports, both ports showed UP in switch logs but traffic still didn't flow.

Test results:
- Same-VLAN ping (VM to VM): **WORKS**
- Gateway ping: **FAILS**
- Problem isolated to: Switch <-> ER605 uplink path

### Port Mirror Confusion

ER605 Port 2 had port mirroring enabled (leftover from Phase 1 debugging).

| Action | Result |
|--------|--------|
| Port 2 with mirror enabled | Traffic blocked |
| Changed to Port 4 | Traffic worked |
| Disabled mirror on Port 2 | Traffic worked |

But behavior was inconsistent - port mirror was "solution" in one case, "problem" in another.

### Final Fix Discovery

I recalled that **100M forced + flow control** was the original fix from Phase 1, but had been reverted to Auto at some point.

Re-applied:
- ER605 Port 4: 100M Full-duplex + Flow Control
- ER605 Port 2: 100M Full-duplex + Flow Control (if used)

Result: Stable connectivity restored.

## Root Cause Analysis

What I know:
1. Prod server is always stable - uses built-in 100M NIC
2. Dev server is unstable - uses USB Gigabit adapter
3. Gigabit auto-negotiation fails intermittently
4. Forcing 100M resolves the instability

What I don't know: The exact hardware/firmware component causing the failure - ER605 PHY chip? USB-Ethernet adapter chipset (ASIX AX88179B)? Interaction between the two? EMI/power issue?

Root cause is UNIDENTIFIED at this point, but workaround is confirmed.

## Architecture Assessment

Original setup (over-engineered):
```
Server svc0 -> Switch Port 4 -> Switch Port 3 -> ER605 Port 2
                    ^
              Does nothing useful
```

The switch provides zero benefit for SVC traffic - just forwards tagged VLANs.

Simplified option:
```
Server svc0 -> ER605 Port (direct)
```

Fewer failure points, simpler troubleshooting. I decided to keep the switch for now but acknowledged it adds complexity without benefit for the SVC path.

## Final Configuration

### ER605 Port Settings

| Port | Function | Speed | Flow Control |
|------|----------|-------|--------------|
| Port 2 | Dev SVC uplink | **100M Full** | **Enabled** |
| Port 4 | Dev SVC (backup) | **100M Full** | **Enabled** |
| Port 5 | Prod SVC uplink | Auto (100M default) | Enabled |

### Why Prod Doesn't Need Forcing

Prod server uses built-in Ethernet NIC which negotiates at 100M by default. The instability only occurs with USB Gigabit adapters attempting Gigabit negotiation.

---

# Phase 4: Driver Analysis Discovery
Date: 2026-03-27 (next day) | Duration: ~1 hr | Result: TRUE ROOT CAUSE IDENTIFIED

## Hardware Discovery

| Component | Details |
|-----------|---------|
| Dev Server | **ASUS VivoBook 15** (economy laptop) |
| USB Adapter | **UGREEN 2.5G** (ASIX AX88179B chipset) |
| USB Topology | Single physical chip, multiple ports |
| Prod Server | Dedicated laptop with **built-in Ethernet** on mainboard |

## Driver Investigation

The AX88179B adapter is using the **wrong kernel driver**.

```bash
# Expected driver
driver: ax88179_178a  (native ASIX driver with proper negotiation)

# Actual driver in use
driver: cdc_ncm       (generic CDC NCM fallback - limited functionality)
```

ethtool output with cdc_ncm:
```
Speed: 100Mb/s
Duplex: Unknown! (255)    <- PROBLEM: No duplex negotiation
Auto-negotiation: off
Link detected: yes
```

## Why cdc_ncm Causes Instability

The `cdc_ncm` driver is a generic USB network driver that:
- Does NOT support proper speed/duplex negotiation
- Shows "Duplex: Unknown! (255)"
- Cannot communicate link parameters to switch/router
- Causes intermittent link flapping

The native `ax88179_178a` driver:
- Supports full auto-negotiation
- Reports correct speed/duplex
- Handles link state properly

## Attempted Fix

```bash
# 1. Driver module exists
modinfo ax88179_178a  # Available in kernel

# 2. Loaded the proper driver
modprobe ax88179_178a  # Loaded

# 3. But adapter still binds to cdc_ncm first
ethtool -i svc0  # Still shows driver: cdc_ncm
```

The AX88179B presents itself as a CDC NCM device first, and the kernel binds to `cdc_ncm` before `ax88179_178a` can claim it.

## Proposed Permanent Fix

Blacklist `cdc_ncm` to force binding to native driver:

```bash
echo "blacklist cdc_ncm" > /etc/modprobe.d/blacklist-cdc_ncm.conf
update-initramfs -u
# Reboot
```

Status: Pending testing.

## Why Prod Server is Stable

| Server | NIC Type | Driver | Negotiation | Stability |
|--------|----------|--------|-------------|-----------|
| **Dev** (VivoBook 15) | USB adapter (AX88179B) | cdc_ncm (wrong) | Broken | Unstable |
| **Prod** | Built-in Ethernet | Native driver | Works | Stable |

The Prod server has a dedicated Ethernet port on the mainboard, which uses native drivers with proper negotiation. It defaults to 100M naturally without issues.

## Current Configuration

Both Dev and Prod SVC cables connected to router (not through switch):

| Server | Cable Path | Router Port | Speed Setting |
|--------|------------|-------------|---------------|
| Dev | Direct to router | Port 2 or 4 | 100M Forced |
| Prod | Direct to router | Port 5 | Auto (100M default) |

## Next Steps

- [ ] Reboot Dev server with `cdc_ncm` blacklisted
- [ ] Verify `ax88179_178a` driver binds on boot
- [ ] Test if proper driver allows Gigabit without flapping
- [ ] If still unstable, keep 100M forced as permanent workaround
- [ ] Consider replacing USB adapter with PCIe NIC for Dev server
_____________________________________________________________________

[Final Root Cause]

Multi-layered issue with true root cause discovered in Phase 4:

**Primary:** Wrong kernel driver (`cdc_ncm` instead of `ax88179_178a`) causing broken duplex negotiation on USB-Ethernet adapter. The AX88179B presents itself as a CDC NCM device first, and the kernel binds to the generic `cdc_ncm` driver before the native `ax88179_178a` can claim it. This results in "Duplex: Unknown! (255)" and no proper speed/duplex negotiation.

**Secondary:** USB Gigabit adapters + ER605 Gigabit auto-negotiation = unreliable combination when the driver can't negotiate properly.

**Red herrings tracked across phases:**
- Phase 1: ER605 Port 4 PHY failure (migrating to Port 2 didn't fix it)
- Phase 2: Loose cable connection (replacing cables didn't fix it)
- Phase 2: Bad USB-Ethernet adapter (replacing adapter didn't fix it)
- Phase 3: Switch port issues (swapping ports didn't fix it)

Each "fix" appeared to work due to coincidental timing -- the link was cycling anyway, and any change that triggered a re-negotiation could land on a brief stable window.

**Investigation timeline:**

| Phase | Date | Duration | Suspected Cause | Actual Status |
|-------|------|----------|-----------------|---------------|
| 1 | 2026-03-21 | ~45 min | ER605 Port 4 PHY failure | Wrong |
| 2 | 2026-03-22 | ~1.5 hrs | Loose cable connection | Wrong |
| 3 | 2026-03-26 | ~2+ hrs | Various (all wrong) | Force 100M works |
| 4 | 2026-03-27 | ~1 hr | Driver binding issue | TRUE ROOT CAUSE |
_____________________________________________________________________

[Final Solution]

**Working fix:** Force 100M Full-duplex on all SVC router ports.

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

If the blacklist works, the native `ax88179_178a` driver should handle Gigabit negotiation properly. If still unstable, keep 100M forced as permanent workaround. If 100M is unacceptable, replace USB adapter with PCIe NIC.

The switch was also removed from the SVC path (direct server -> router) to reduce failure points.
_____________________________________________________________________

[Risk Level]

LOW - Dev SVC limited to 100Mbps, which is sufficient since ISP speed is 30-70 Mbps. All SVC ports stable at 100M with no more link flapping. Dev and Prod environments both functional.
_____________________________________________________________________

[References]

- ER605 SSH access: `ssh -o HostKeyAlgorithms=+ssh-rsa -o PubkeyAcceptedKeyTypes=+ssh-rsa admin@10.0.5.1`
- Switch diagnostic exports: syslog.log, switchCfg.cfg, cpuUltilization.txt, meminfo, dmesg
- Phase 2 switch logs location: `logs/new port 4 down /`
- Kernel driver info: `ethtool -i svc0` (shows active driver), `modinfo ax88179_178a` (native driver)
- Key diagnostic commands: `dmesg -T | grep svc0`, `ethtool svc0`, `ethtool -i svc0`, `ip -s link show svc0`
