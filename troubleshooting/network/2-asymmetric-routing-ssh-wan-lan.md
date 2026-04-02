# Case 2: Asymmetric Routing SSH Issue — WAN to LAN Hanging

## Status: RESOLVED
## Date: 2026-02-12
## Environment: WAN to Proxmox DEV via ER605

---

## Environment

- Client: Mac Mini (192.168.0.223) on home network (WAN side)
- Target: Proxmox DEV server WiFi interface (10.0.5.110)
- Router: ER605 handling WAN to LAN routing
- Proxmox interfaces: WiFi (wlp1s0) + Bridge (vmbr0)

---

## Symptoms

| Test | Result |
|------|--------|
| Ping 10.0.5.110 from Mac Mini | PASS |
| SSH to 10.0.5.110 from Mac Mini | HANG (no password prompt) |
| curl to HTTP on 10.0.5.110 | FAIL |
| SSH from same VLAN (10.0.5.x) | PASS |

---

## Failed Troubleshooting Attempts

### 1. Check SSH service status
```bash
systemctl status ssh
```
**Result:** SSH running, listening on 0.0.0.0:22 ✓

### 2. Check Proxmox firewall
- Datacenter → Firewall → Options
- Firewall: No (disabled)

**Result:** Not the issue ✓

### 3. Check routing table
```bash
ip route
```
**Result:** Default gateway correct (10.0.5.1 via wlp1s0) ✓

### 4. Add ER605 ACL rules for return traffic
- Added: Allow_LAN_to_Mac (LAN→WAN direction)
- Added: rrrrr (ALL direction, IPGROUP_LAN → Mac_Mini_PC)

**Result:** Still failed ✗

### 5. Verbose SSH test
```bash
ssh -v root@10.0.5.110
```
**Result:** "Connection established" but then hung, later showed:
```
kex_exchange_identification: read: Connection reset by peer
```

---

## Root Cause Found

**ASYMMETRIC ROUTING**

Proxmox had TWO network paths to 192.168.0.x:

1. **WiFi (wlp1s0)** → Gateway 10.0.5.1 → ER605 → WAN → 192.168.0.x
2. **vmbr0 with IP 192.168.0.220** → DIRECT to 192.168.0.x (same subnet)

### Traffic Flow Was Broken:

```
INBOUND:  Mac Mini → ER605 WAN → VLAN 5 → Proxmox WiFi (wlp1s0)
OUTBOUND: Proxmox saw 192.168.0.223, had 192.168.0.220 on vmbr0,
          replied DIRECTLY via vmbr0, bypassing ER605
```

**TCP requires symmetric routing.** SYN came in on wlp1s0, but SYN-ACK
went out on vmbr0 = connection reset.

---

## Solution

Remove the old 192.168.0.220 IP from vmbr0:

```bash
ip addr del 192.168.0.220/24 dev vmbr0
ip route del 192.168.0.0/24 dev vmbr0
```

Then update `/etc/network/interfaces` to remove old config permanently.

---

## Key Takeaway

When migrating management from one interface to another, **REMOVE the old
IP completely**. Having IPs on multiple interfaces in overlapping/related
subnets causes asymmetric routing issues for TCP connections.

### Why Ping Worked But SSH Failed:

- **ICMP (ping):** Stateless, doesn't care about path symmetry
- **TCP (SSH):** Stateful, requires packets to flow on same path for connection tracking

---

## Prevention

Before changing management interfaces:

1. Plan the migration completely
2. Remove old IP from old interface BEFORE relying on new interface
3. Or ensure old and new interfaces are on completely separate subnets with no overlap
4. Test with TCP connections (SSH, HTTP), not just ping
