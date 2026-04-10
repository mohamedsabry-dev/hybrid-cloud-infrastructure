# TS-NET-002 | 2026-02-12 | RESOLVED

## 1. Context
- System: Network routing / TCP connections
- Environment: WAN to Proxmox DEV via ER605
- Related components: Mac Mini (192.168.0.223), ER605, Proxmox DEV (WiFi: 10.0.5.110, vmbr0: 192.168.0.220)

## 2. Issue
- Symptom: SSH from WAN to Proxmox hangs (no password prompt), ping works
- Error:
```
kex_exchange_identification: read: Connection reset by peer
```

**Observed behavior:**
| Test | Result |
|------|--------|
| Ping 10.0.5.110 from Mac Mini | PASS |
| SSH to 10.0.5.110 from Mac Mini | HANG (no password prompt) |
| curl to HTTP on 10.0.5.110 | FAIL |
| SSH from same VLAN (10.0.5.x) | PASS |

## 3. Analysis

**Check 1: SSH service status**
```bash
systemctl status ssh
```
Finding: SSH running, listening on 0.0.0.0:22 ✓

**Check 2: Proxmox firewall**
- Datacenter → Firewall → Options → Firewall: No (disabled)
Finding: Not the issue ✓

**Check 3: Routing table**
```bash
ip route
```
Finding: Default gateway correct (10.0.5.1 via wlp1s0) ✓

**Check 4: ER605 ACL rules for return traffic**
- Added: Allow_LAN_to_Mac (LAN→WAN direction)
- Added: rrrrr (ALL direction, IPGROUP_LAN → Mac_Mini_PC)
Finding: Still failed ✗

**Check 5: Verbose SSH test**
```bash
ssh -v root@10.0.5.110
```
Finding: "Connection established" but then hung, later showed connection reset.

**Check 6: Multiple network paths discovered**
Proxmox had TWO network paths to 192.168.0.x:
1. WiFi (wlp1s0) → Gateway 10.0.5.1 → ER605 → WAN → 192.168.0.x
2. vmbr0 with IP 192.168.0.220 → DIRECT to 192.168.0.x (same subnet)

Finding: **ASYMMETRIC ROUTING** - inbound via WiFi, outbound via vmbr0.

## 4. Root Cause
> Asymmetric routing due to old IP (192.168.0.220) still configured on vmbr0. Inbound traffic came via WiFi interface, but Proxmox replied directly via vmbr0 (same subnet as source). TCP requires symmetric routing - SYN came in on wlp1s0, but SYN-ACK went out on vmbr0 = connection reset.

**Why Ping worked but SSH failed:**
- ICMP (ping): Stateless, doesn't care about path symmetry
- TCP (SSH): Stateful, requires packets to flow on same path for connection tracking

## 5. Solution
> Remove the old 192.168.0.220 IP from vmbr0.

```bash
ip addr del 192.168.0.220/24 dev vmbr0
ip route del 192.168.0.0/24 dev vmbr0
```

Then update `/etc/network/interfaces` to remove old config permanently.

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Any services relying on old IP will lose connectivity

## 7. Impact After Fix
- Observed: SSH connections work from WAN to Proxmox
- All TCP connections now symmetric through ER605

## 8. Notes

**Key Takeaway:** When migrating management from one interface to another, REMOVE the old IP completely. Having IPs on multiple interfaces in overlapping/related subnets causes asymmetric routing issues for TCP connections.

**Prevention checklist:**
1. Plan the migration completely
2. Remove old IP from old interface BEFORE relying on new interface
3. Or ensure old and new interfaces are on completely separate subnets with no overlap
4. Test with TCP connections (SSH, HTTP), not just ping

## 9. Workaround (if any)
> N/A - must fix the routing asymmetry.
