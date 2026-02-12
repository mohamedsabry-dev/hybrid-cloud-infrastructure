# NAS VM Network Bonding

> **Active-Backup bonding for high availability on storage traffic**

---

## Overview

NAS VM uses network bonding (Active-Backup mode) for high availability on storage traffic.

**Purpose:**
- Zero downtime during single NIC failure
- Automatic failover without manual intervention
- Critical for NFS storage availability

---

## Bond Configuration

### Interface: bond0

```
IP Address: 10.0.20.90
Mode: Active-Backup (mode 1)
Primary: ens33
Backup: ens35
miimon: 100 (milliseconds)
Gateway: 10.0.20.170 (pfSense LAN)
DNS: 10.0.20.184 (IPA)
```

---

## Why Active-Backup Mode?

### Mode Comparison

| Mode | Distribution | Failover | Switch Config | Lab Suitable |
|------|--------------|----------|---------------|--------------|
| **0 (Balance-RR)** | Round-robin | Yes | Required | ❌ |
| **1 (Active-Backup)** | One active | Yes | Not required | ✅ **PERFECT** |
| **2 (Balance-XOR)** | Hash-based | Yes | Optional | ✅ |
| **4 (LACP)** | Dynamic | Yes | LACP switch | ❌ |

### Selected: Mode 1 (Active-Backup)

**Advantages:**
- ✅ No switch configuration required (ideal for home lab)
- ✅ Simple failover logic (one active, one standby)
- ✅ Sub-second failover with miimon=100
- ✅ Compatible with VMware virtual networking

**Trade-offs:**
- ⚠️ No bandwidth aggregation (only one NIC active)
- ⚠️ Standby NIC idle (no load balancing)

**Why this works for NAS:**
- NFS traffic fits within single 1 Gbps link
- Availability more important than bandwidth
- Simple configuration reduces complexity

---

## miimon Parameter Explained

### Parameter: `miimon=100`

**What It Does:**
- Forces kernel to check link status every 100ms
- Ensures failover within 100-200ms
- Critical for NFS traffic (prevents timeout)

**Why 100ms?**
- Standard NFS timeout: 30-60 seconds
- Our failover: <200ms (100ms detection + 100ms switch)
- Result: ESXi never notices the interruption

**Alternative Values:**
- `miimon=50`: More aggressive (higher CPU overhead)
- `miimon=200`: Less aggressive (longer failover)
- `miimon=0`: No monitoring (NOT RECOMMENDED - relies on driver interrupts)

**Our Choice: miimon=100**
- Balanced between responsiveness and overhead
- Industry standard for most configurations
- Proven reliable in testing

---

## Bond Configuration Commands

### Create Bond Master

```bash
# Create bond master
sudo nmcli con add type bond con-name bond0 ifname bond0 \
  bond.options "mode=active-backup,miimon=100"

# Assign IP to bond
sudo nmcli con mod bond0 ipv4.addresses 10.0.20.90/24
sudo nmcli con mod bond0 ipv4.gateway 10.0.20.170
sudo nmcli con mod bond0 ipv4.dns "10.0.20.184"
sudo nmcli con mod bond0 ipv4.method manual

# Attach slave interfaces
sudo nmcli con add type ethernet slave-type bond \
  con-name bond0-port1 ifname ens33 master bond0

sudo nmcli con add type ethernet slave-type bond \
  con-name bond0-port2 ifname ens35 master bond0

# Activate bond
sudo nmcli con up bond0
```

### Verification

```bash
# Check bond status
cat /proc/net/bonding/bond0

# Expected Output:
# Bonding Mode: fault-tolerance (active-backup)
# Primary Slave: ens33 (primary_reselect always)
# Currently Active Slave: ens33
# MII Status: up
# MII Polling Interval (ms): 100
#
# Slave Interface: ens33
# MII Status: up
# Speed: 1000 Mbps
# ...
#
# Slave Interface: ens35
# MII Status: up
# Speed: 1000 Mbps
```

---

## Failover Testing Results

### Test Procedure

1. Continuous ping from ESXi to NAS (10.0.20.90)
2. Disconnect primary interface (ens33) via VMware Workstation
3. Observe failover behavior
4. Reconnect primary interface
5. Disconnect secondary interface (ens35)
6. Disconnect both interfaces (total failure test)

### Results

**Single Interface Failure (ens33):**
- ✅ Failover time: Sub-second (<200ms)
- ✅ Zero packet loss during failover
- ✅ Automatic failover to ens35
- ✅ Fast recovery when ens33 reconnected

**Single Interface Failure (ens35):**
- ✅ No impact (already using ens33 as primary)
- ✅ Zero packet loss

**Both Interfaces Disconnected:**
- ❌ Packet loss (expected - total network failure)
- ✅ Fast recovery when either interface reconnected

**Statistics:**
```
63 packets transmitted, 58 received, 7.93% packet loss
  └─ Loss only during total disconnection test
  └─ Zero loss during single interface failover
```

**Conclusion:**
- miimon=100 performing as designed
- Sub-second failover meets requirements
- Active-Backup mode reliable for NFS traffic

---

## Monitoring Bond Health

### Check Bond Status

```bash
# Real-time bond status
cat /proc/net/bonding/bond0

# Watch for:
# - Currently Active Slave (should be ens33 normally)
# - MII Status: up (for both slaves)
# - MII Polling Interval: 100 ms
```

### Check Interface Statistics

```bash
# Interface statistics
ip -s link show bond0
ip -s link show ens33
ip -s link show ens35

# Watch for:
# - TX/RX packet counters increasing on active interface
# - Error counters should be 0 or very low
```

### Monitor Network Traffic

```bash
# Real-time traffic monitoring
iftop -i bond0

# Or use dstat for all-in-one view
dstat -n -N bond0,ens33,ens35
```

---

## Troubleshooting

### Issue: Failover Not Working

**Symptom**: Disconnecting primary NIC causes total network loss

**Diagnosis:**
```bash
# Check bond configuration
cat /proc/net/bonding/bond0

# Verify:
# - Mode is "active-backup" (mode 1)
# - miimon is 100
# - Both slaves are "up"
```

**Cause**: Bond not properly configured

**Solution:**
1. Verify both slave interfaces attached to bond
2. Verify miimon parameter set
3. Restart bond: `sudo nmcli con down bond0 && sudo nmcli con up bond0`

### Issue: Frequent Failovers (Flapping)

**Symptom**: Bond constantly switching between ens33 and ens35

**Diagnosis:**
```bash
# Check system logs
journalctl -u NetworkManager -f

# Look for frequent "link status changed" messages
```

**Cause**: Unstable network links or VMware virtual network issues

**Solution:**
1. Increase miimon interval: `miimon=200` (less sensitive)
2. Check VMware virtual network adapter settings
3. Verify no duplicate MAC addresses

### Issue: No Network Connectivity After Reboot

**Symptom**: NAS VM has no network after reboot

**Diagnosis:**
```bash
# Check bond status
nmcli con show

# Verify bond0 is "activated"
# If not activated:
sudo nmcli con up bond0
```

**Cause**: Bond not configured to auto-start

**Solution:**
```bash
# Enable auto-connect
sudo nmcli con mod bond0 connection.autoconnect yes
sudo nmcli con mod bond0-port1 connection.autoconnect yes
sudo nmcli con mod bond0-port2 connection.autoconnect yes
```

---

## Benefits of Network Bonding for NAS

### High Availability

**Without Bonding:**
```
ens33 fails → NAS unreachable → All VMs lose NFS storage → Cluster down
```

**With Bonding:**
```
ens33 fails → Failover to ens35 in <200ms → Zero downtime → VMs unaffected
```

### ESXi Impact

**NFS Timeout Behavior:**
- ESXi NFS timeout: 30-60 seconds
- Our failover: <200ms
- ESXi never experiences timeout
- VMs continue running without interruption

### Production Best Practice

**Why this matters:**
- NAS VM is single point of failure for storage
- Network bonding provides resilience
- Sub-second failover prevents VM stalls
- Critical for production workloads

---

## Future Enhancements

### Additional Bonding Modes (Future)

**If upgrading to physical switch with LACP:**
- Mode 4 (LACP): Dynamic link aggregation
- Benefit: Bandwidth aggregation (2 Gbps)
- Requirement: LACP-capable switch

**If deploying separate storage VLAN:**
- Dedicated VLAN for NFS traffic
- Bond on storage VLAN only
- Further isolation from management traffic

---

## Related Documentation

- [Internal Network](03-Internal-Network.md)
- [NAS Configuration](../Storage/03-NAS-Configuration.md)
- [Network Security](07-Network-Security-and-Troubleshooting.md)
- [Storage Performance](../Storage/06-Performance-Monitoring.md)
