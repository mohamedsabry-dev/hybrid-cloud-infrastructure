# Troubleshooting: Dev SVC Network Instability - Force 100M Resolution

**Date**: 2026-03-26
**Duration**: ~2+ hours troubleshooting
**Affected**: Dev environment - all VMs/LXCs on SVC VLANs (60-65)
**Resolution**: Force 100M on all SVC router ports

---

## Related Issues

- **Case 43**: `43-switch-port4-link-flapping-loose-connection.md` - Initial loose cable diagnosis
- **Case 48**: `48-er605-port4-gigabit-negotiation.md` - ER605 Port 4 PHY failure, migration to Port 2

Both previous cases recurred. This case consolidates the final resolution.

---

## Symptoms

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

## Troubleshooting Sequence

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

### Key Discovery

After swapping switch ports, both ports showed UP in switch logs but traffic still didn't flow.

**Test results:**
- Same-VLAN ping (VM to VM): **WORKS**
- Gateway ping: **FAILS**
- Problem isolated to: Switch ↔ ER605 uplink path

### Port Mirror Confusion

ER605 Port 2 had port mirroring enabled (leftover from Case 48 debugging).

| Action | Result |
|--------|--------|
| Port 2 with mirror enabled | Traffic blocked |
| Changed to Port 4 | Traffic worked |
| Disabled mirror on Port 2 | Traffic worked |

But behavior was inconsistent - port mirror was "solution" in one case, "problem" in another.

### Final Fix

User recalled that **100M forced + flow control** was the original fix from Case 48, but had been reverted to Auto at some point.

**Re-applied:**
- ER605 Port 4: 100M Full-duplex + Flow Control
- ER605 Port 2: 100M Full-duplex + Flow Control (if used)

**Result:** Stable connectivity restored.

---

## Root Cause Analysis

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

## Architecture Assessment

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

## Final Configuration

### ER605 Port Settings

| Port | Function | Speed | Flow Control |
|------|----------|-------|--------------|
| Port 2 | Dev SVC uplink | **100M Full** | **Enabled** |
| Port 4 | Dev SVC (backup) | **100M Full** | **Enabled** |
| Port 5 | Prod SVC uplink | Auto (100M default) | Enabled |

### Why Prod Doesn't Need Forcing

Prod server uses **built-in Ethernet NIC** which negotiates at 100M by default. The instability only occurs with USB Gigabit adapters attempting Gigabit negotiation.

---

## Lessons Learned

1. **Previous "root causes" were incomplete** - loose cable and PHY failure were symptoms, not the full picture

2. **USB Gigabit adapters are unreliable** at Gigabit speeds with ER605

3. **100M is sufficient** - ISP is 30-70 Mbps anyway

4. **Document workarounds even without root cause** - sometimes you can't find the exact cause

5. **Over-engineering adds failure points** - switch in SVC path provides no benefit

6. **Intermittent issues may never be fully explained** - accept working workaround

---

## Recommendations

### Immediate

- [x] Force 100M on all SVC router ports
- [x] Disable port mirror when not actively debugging
- [x] Update Cases 43 and 48 with recurrence info

### Future Considerations

- Consider removing switch from SVC path (direct server → router)
- Consider replacing USB adapters with PCIe NICs
- Consider replacing ER605 with MikroTik (more diagnostic capability)

---

## Status

✅ **Stable** - All SVC ports forced to 100M from router side

**Monitor for:** Any future instability even at 100M (would indicate hardware failure requiring replacement)

---

## Update: Driver Analysis (2026-03-27)

### Hardware Discovery

| Component | Details |
|-----------|---------|
| Dev Server | **ASUS VivoBook 15** (economy laptop) |
| USB Adapter | **UGREEN 2.5G** (ASIX AX88179B chipset) |
| USB Topology | Single physical chip, multiple ports |
| Prod Server | Dedicated laptop with **built-in Ethernet** on mainboard |

### Driver Investigation

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

### Why cdc_ncm Causes Instability

The `cdc_ncm` driver is a **generic USB network driver** that:
- Does NOT support proper speed/duplex negotiation
- Shows "Duplex: Unknown! (255)"
- Cannot communicate link parameters to switch/router
- Causes intermittent link flapping

The native `ax88179_178a` driver:
- Supports full auto-negotiation
- Reports correct speed/duplex
- Handles link state properly

### Attempted Fix

```bash
# 1. Driver module exists
modinfo ax88179_178a  # ✓ Available in kernel

# 2. Loaded the proper driver
modprobe ax88179_178a  # ✓ Loaded

# 3. But adapter still binds to cdc_ncm first
ethtool -i svc0  # Still shows driver: cdc_ncm
```

**Root Cause:** The AX88179B presents itself as a CDC NCM device first, and the kernel binds to `cdc_ncm` before `ax88179_178a` can claim it.

### Proposed Permanent Fix

Blacklist `cdc_ncm` to force binding to native driver:

```bash
# Create blacklist
echo "blacklist cdc_ncm" > /etc/modprobe.d/blacklist-cdc_ncm.conf

# Update initramfs
update-initramfs -u

# Reboot
```

**Status:** Pending reboot to test

### Why Prod Server is Stable

| Server | NIC Type | Driver | Negotiation | Stability |
|--------|----------|--------|-------------|-----------|
| **Dev** (VivoBook 15) | USB adapter (AX88179B) | cdc_ncm (wrong) | Broken | ❌ Unstable |
| **Prod** | Built-in Ethernet | Native driver | Works | ✅ Stable |

The Prod server has a **dedicated Ethernet port on the mainboard**, which uses native drivers with proper negotiation. It defaults to 100M naturally without issues.

### Current Configuration

Both Dev and Prod SVC cables connected to **router** (not through switch):

| Server | Cable Path | Router Port | Speed Setting |
|--------|------------|-------------|---------------|
| Dev | Direct to router | Port 2 or 4 | 100M Forced |
| Prod | Direct to router | Port 5 | Auto (100M default) |

### Lessons Learned (Updated)

1. **USB adapter driver matters** - `cdc_ncm` vs `ax88179_178a` makes a huge difference
2. **Economy laptops have shared USB controllers** - single chip, multiple ports
3. **Built-in NICs are more reliable** than USB adapters
4. **Kernel driver binding order** can cause wrong driver to be used
5. **Duplex "Unknown" is a red flag** - indicates broken negotiation

### Next Steps

- [ ] Reboot Dev server with `cdc_ncm` blacklisted
- [ ] Verify `ax88179_178a` driver binds on boot
- [ ] Test if proper driver allows Gigabit without flapping
- [ ] If still unstable, keep 100M forced as permanent workaround
- [ ] Consider replacing USB adapter with PCIe NIC for Dev server
