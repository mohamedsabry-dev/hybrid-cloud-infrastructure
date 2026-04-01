# Troubleshooting: Switch Port 4 Link Flapping - Loose Cable Connection

**Date**: 2026-03-22
**Duration**: ~1.5 hours troubleshooting
**Affected**: Dev environment - all VMs/LXCs on SVC VLANs (60-65)
**Resolution**: Reseat cable connections on both ends (Proxmox NIC and Switch port)

---

## Related Issue

**Previous Day (2026-03-21)**: ER605 Router Port 4 failure - migrated to Port 2
- See: `troubleshooting/network/48-er605-port4-gigabit-negotiation.md`
- That issue was router-side PHY failure
- Today's issue is switch-side, different root cause

---

## Symptoms

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

## Network Path

```
Proxmox Dev (svc0 NIC)
       │
       │ Ethernet cable ← LOOSE CONNECTION HERE
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

## Troubleshooting Sequence

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

### Step 5: Proxmox dmesg Analysis (Critical Finding)

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

## Solution

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

## Root Cause

**Loose cable connection** - either at Proxmox USB-Ethernet adapter or Switch Port 4.

The connector was not fully seated, causing intermittent electrical contact:
- Good contact → Link up → Traffic flows
- Contact breaks → Link down → "Destination Host Unreachable"
- Cycle repeats every few seconds

---

## Why DHCP Worked But Ping Failed

| Protocol | Behavior | Result |
|----------|----------|--------|
| DHCP | Broadcast, retries automatically | Succeeded during brief "up" window |
| ARP | Broadcast, cached | Succeeded, MAC learned |
| ICMP Ping | Unicast, requires stable connection | Failed during "down" windows |

DHCP and ARP are more tolerant of intermittent connectivity because they use broadcasts and have retry mechanisms. ICMP ping requires continuous unicast connectivity.

---

## Commands Reference

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

## Evidence Files

Collected in: `logs/new port 4 down /`

| File | Content |
|------|---------|
| syslog.log | 100+ link flap events on Gi1/0/4 |
| switchCfg.cfg | Switch configuration |
| cpuUltilization.txt | Switch CPU (normal: 1-8%) |
| meminfo | Switch memory (normal: 29% free) |
| dmesg | Switch boot logs |

---

## Lessons Learned

1. **Check physical layer first** - loose cables cause intermittent issues that look like complex problems
2. **dmesg reveals link flapping** - `entered disabled state` cycling = physical layer issue
3. **ethtool shows true link status** - `Link detected: no` is definitive
4. **DHCP success doesn't mean network is healthy** - broadcasts are resilient, unicast is not
5. **ARP can mislead** - getting ARP replies doesn't mean stable connectivity
6. **Switch logs confirm the issue** - correlate Proxmox dmesg with switch syslog
7. **Reseat before replacing** - simple fix solved complex-looking problem

---

## Prevention

1. **Use quality cables** - Cat6 minimum for Gigabit
2. **Secure connections** - ensure click/lock engages
3. **Avoid USB-Ethernet adapters** - less reliable than onboard NICs
4. **Monitor link status** - script to alert on link flaps
5. **Label cables** - easier to identify for troubleshooting

---

## Monitoring Script (Optional)

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

## Status

⚠️ **Partially Resolved** - See Update Below

---

## Update: Issue Recurrence (March 26, 2026)

**Related Cases**:
- `48-er605-port4-gigabit-negotiation.md`
- `57-svc-network-instability-force-100m.md`

### Issue Returned

The link flapping issue recurred ~1-2 weeks later, despite:
- Reseating cable connections
- Replacing cables
- Replacing USB-Ethernet adapter

### Extended Troubleshooting Performed

All of the recommended prevention steps were tried:
- ✅ Replaced cable - issue remained
- ✅ Replaced USB-Ethernet adapter - issue remained
- ✅ Changed switch port - issue remained
- ✅ Changed server USB port - issue remained
- ✅ Bypassed switch entirely - initially failed, then worked randomly

### Root Cause: UNIDENTIFIED

The original diagnosis of "loose cable connection" was **incorrect or incomplete**. The true root cause could not be definitively identified.

### Actual Pattern Discovered

| Component | Status |
|-----------|--------|
| Prod server (built-in 100M NIC) | Always stable |
| Dev server (USB Gigabit adapter) | Intermittently unstable |
| Gigabit auto-negotiation | Unreliable |
| Forced 100M | Stable |

### Confirmed Fix

**Force 100M speed on router ports** rather than relying on physical layer fixes.

The issue is NOT:
- ~~Loose cable~~ (replaced multiple times)
- ~~Bad adapter~~ (replaced multiple times)
- ~~Bad switch port~~ (tried multiple ports)

The issue IS:
- **Gigabit auto-negotiation instability** between USB-Ethernet adapters and ER605 router

### Updated Lessons Learned

| Original Lesson | Updated Lesson |
|-----------------|----------------|
| Check physical layer first | Physical layer may not be the issue |
| Reseat before replacing | Reseating is temporary at best |
| Avoid USB-Ethernet adapters | **Force 100M if USB adapters must be used** |

### Prevention (Updated)

1. **Force 100M on SVC ports** - don't rely on auto-negotiation
2. **Use built-in NICs** - USB adapters are inherently less stable at Gigabit
3. **Accept 100M for reliability** - speed vs stability trade-off

### Current Status

✅ **Stable** - All SVC ports forced to 100M from router side
