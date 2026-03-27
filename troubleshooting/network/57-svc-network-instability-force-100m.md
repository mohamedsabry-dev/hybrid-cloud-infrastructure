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
