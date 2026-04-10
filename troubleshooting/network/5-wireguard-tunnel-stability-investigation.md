# TS-NET-005 | 2026-03-11 → 2026-04 | RESOLVED

## 1. Context
- System: WireGuard VPN / Site-to-Site Tunnel
- Environment: ER605 → AWS (Dev & Prod tunnels), later MikroTik → AWS
- Related components: ER605 WireGuard, MikroTik WireGuard, AWS EC2 (Dev & Prod), ISP CGNAT
- Related tickets: [TS-NET-004](4-wireguard-cgnat-port-blocking.md) - CGNAT port blocking (related but separate incident)

## 2. Issue
- Symptom: WireGuard tunnels intermittently dropping, requiring manual intervention
- Multiple suspected root causes investigated over time
- Error patterns:
  - Tunnel works initially, drops after idle time
  - "No handshake" status on ER605
  - Connection timeouts from internal hosts to AWS

**This document covers the full investigation journey across multiple suspected causes before discovering the TRUE root cause.**

---

# PHASE 1: NAT Timeout Investigation | 2026-03-11

## Symptoms (Phase 1)
- WireGuard tunnel worked initially
- After ~1 hour of idle time, tunnel stopped working
- No handshake, connection timeout
- Required manual restart on both sides

---

## 3. Analysis (Phase 1)

**Check 1: ISP Router NAT Configuration**
```
Setting: NAT Type
Value: Port-Restricted Cone NAT
```
Finding: Port-Restricted Cone NAT drops UDP mappings after inactivity timeout (~60 minutes). ✓

---

**Check 2: WireGuard Keepalive Settings**
```bash
# On ER605
Persistent Keepalive = 25 seconds per peer
```
Finding: ER605 sending keepalives, but not sufficient alone. Need bidirectional keepalive. ✓

---

**Check 3: NAT Behavior Analysis**
```
Port-Restricted Cone NAT:
1. Drops UDP mappings after inactivity timeout (~60 minutes)
2. Blocks incoming packets if no recent outgoing traffic
3. Causes WireGuard handshakes to fail after timeout
```
Finding: ISP NAT too aggressive with UDP session cleanup. ✓

---

## 4. Root Cause (Phase 1 - Partial)
> ISP router configured with Port-Restricted Cone NAT which drops UDP mappings after inactivity timeout (~60 minutes), causing WireGuard handshakes to fail.

---

## 5. Solution (Phase 1)

**Part 1: Change ISP NAT Type**
```
Location: ISP Router settings
Changed: NAT Type
From: Port-Restricted Cone NAT
To: Full Cone NAT
```

**Full Cone NAT Benefits:**
- Maintains UDP mappings longer
- Allows incoming packets from any source once mapping exists
- More permissive for VPN traffic

---

**Part 2: AWS Keepalive Ping Service**

Created systemd service on AWS EC2 to send regular pings through tunnel, preventing NAT timeout:

**File: `/etc/systemd/system/wg-keepalive.service`**
```ini
[Unit]
Description=WireGuard Tunnel Keepalive Ping
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do ping -c 1 <TUNNEL_PEER_IP> > /dev/null 2>&1; sleep 5; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**Enable Service:**
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now wg-keepalive
```

**Keepalive Targets:**
| EC2 Instance | Ping Target | Description |
|--------------|-------------|-------------|
| Dev EC2 | 172.16.200.1 | ER605 dev tunnel IP |
| Prod EC2 | 172.17.200.1 | ER605 prod tunnel IP |

**Ping Interval:** 5 seconds (aggressive to prevent any NAT timeout)

**Service Parameters Explained:**
```ini
Restart=always     # Always restart service if it crashes
RestartSec=10      # Wait 10 seconds before restarting (prevents rapid restart loops)
sleep 5            # Ping interval - every 5 seconds
```

---

**Phase 1 Verification:**
```bash
# Check service status
sudo systemctl status wg-keepalive

# View keepalive logs
journalctl -u wg-keepalive -f

# Verify tunnel stays up
watch -n 60 'sudo wg show wg0 latest-handshakes'
```

**Phase 1 Result:**
Tunnel survived:
- Extended idle periods ✓
- EC2 reboots (service auto-starts) ✓
- Network interruptions (service auto-restarts) ✓

---
---

# PHASE 2: VLAN Gateway Ping Failure | 2026-03-11

## Symptoms (Phase 2)
- Prod EC2 could ping hosts in VLAN 55 (10.0.55.x)
- Prod EC2 could NOT ping VLAN 55 gateway (10.0.55.1)
- Dev EC2 could ping both hosts and gateway in VLAN 65
- Keepalive service failing on Prod EC2 due to ping target unreachable

---

## 3. Analysis (Phase 2)

**Check 1: Connectivity Test**
```bash
# Works - host in VLAN
ping 10.0.55.10
PING 10.0.55.10: 56 data bytes
64 bytes from 10.0.55.10: icmp_seq=0 ttl=64 time=60.2 ms

# Fails - VLAN gateway interface
ping 10.0.55.1
PING 10.0.55.1: 56 data bytes
Request timeout for icmp_seq 0
Request timeout for icmp_seq 1
```
Finding: Host reachable, gateway interface not responding. ✓

---

**Check 2: ER605 ACL Rules Analysis**
```
Rule: vpn_prod → DataCenter_Cairo (Allow)
```
Finding: ACL covers traffic THROUGH the router, but traffic TO router's own interface (10.0.55.1) may have different rules. ✓

---

**Check 3: Traffic Flow Analysis**
```
Traffic THROUGH router: Handled by ACL rules
Traffic TO router's own VLAN interface: Different firewall path
```
Finding: ER605 firewall treats traffic to its own interfaces differently. ✓

---

## 4. Root Cause (Phase 2 - Workaround Found)
> ER605 firewall rules control traffic TO router's own interfaces differently than traffic THROUGH the router. VLAN gateway interface (10.0.55.1) not responding to pings from VPN tunnel while hosts behind it work fine.

---

## 5. Solution (Phase 2 - Workaround)

**Changed keepalive target from VLAN interface to tunnel peer IP:**
```bash
# Old (didn't work for prod)
KEEPALIVE_TARGET="10.0.55.1"

# New (works - tunnel IP is in VPC range)
KEEPALIVE_TARGET="172.17.200.1"
```

**Why this works:** Tunnel IPs are in VPC range, pinging the ER605 tunnel IP (172.17.200.1) serves the same keepalive purpose and is guaranteed to work since it's the tunnel endpoint itself.

**Updated wg-keepalive.service:**
```ini
ExecStart=/bin/bash -c 'while true; do ping -c 1 172.17.200.1 > /dev/null 2>&1; sleep 5; done'
```

---
---

# PHASE 3: Wrong Tunnel Routing | 2026-03-11

## Symptoms (Phase 3)
- Prod internal hosts (10.0.5x.x) could not reach Prod AWS EC2 (172.17.x.x)
- Dev internal hosts could reach Dev AWS EC2 normally
- Prod EC2 could reach internal hosts, but internal could NOT initiate to Prod EC2
- Traffic going through WRONG tunnel

---

## 3. Analysis (Phase 3)

**Check 1: Ping Test from Internal Host**
```bash
[root@ansible ~]# ping 172.17.65.73
PING 172.17.65.73 (172.17.65.73) 56(84) bytes of data.
--- 172.17.65.73 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2030ms
```
Finding: 100% packet loss to Prod EC2 from internal network. ✗

---

**Check 2: Traceroute Analysis - CRITICAL FINDING**
```bash
[root@ansible ~]# traceroute 172.17.65.73
traceroute to 172.17.65.73 (172.17.65.73), 30 hops max, 60 byte packets
 1  _gateway (10.0.53.1)  0.853 ms  0.914 ms  0.849 ms
 2  10.200.0.2 (10.200.0.2)  60.389 ms  60.371 ms  60.359 ms   <-- WRONG TUNNEL!
 3  * * *
 4  * * *
```

**Evidence:** Traffic to PROD AWS (172.17.x.x) was being routed through DEV tunnel (10.200.0.2) instead of PROD tunnel (10.200.1.2).

Finding: **Wrong tunnel selection by ER605!** ✓

---

**Check 3: ER605 AllowedIPs Configuration**
```
dev_tunnel peer:  AllowedIPs = 0.0.0.0/0
prod_tunnel peer: AllowedIPs = 0.0.0.0/0
```

**Problem:** Both peers had `0.0.0.0/0` - ER605 couldn't distinguish which tunnel to use.

Finding: ER605 defaulting to dev_tunnel for ALL traffic. ✓

---

**Check 4: ER605 AllowedIPs Limitation Discovery**

ER605's WireGuard peer AllowedIPs field only accepts **ONE entry**.

Original tunnel IPs were in a separate range (10.200.x.x), requiring multiple AllowedIPs entries:
```
Needed:
- Tunnel IP: 10.200.1.0/24
- VPC CIDR: 172.17.0.0/16

But ER605 only allows ONE entry!
```

**Behavior with different AllowedIPs settings:**
| AllowedIPs Setting | Result |
|--------------------|--------|
| `10.200.1.0/24` (tunnel only) | VPN→Internal works, Internal→VPN fails |
| `172.17.0.0/16` (VPC only) | Internal→VPN works, VPN→Internal fails |
| `0.0.0.0/0` (any) | ER605 picks ONE tunnel for ALL traffic |

Finding: **ER605 limitation - single AllowedIPs entry only!** ✓

---

## 4. Root Cause (Phase 3)
> ER605's WireGuard implementation only accepts ONE AllowedIPs entry per peer. With tunnel IPs in separate range (10.200.x.x) from VPC CIDR (172.x.x.x), there was no way to specify both ranges. Using `0.0.0.0/0` caused ER605 to route all traffic through first tunnel (dev_tunnel).

---

## 5. Solution (Phase 3)

**Strategy:** Place tunnel IPs INSIDE the AWS VPC CIDR range so single AllowedIPs entry covers everything.

**IP Address Changes:**
| Environment | Old Tunnel IPs | New Tunnel IPs |
|-------------|----------------|----------------|
| Dev ER605 | 10.200.0.1 | 172.16.200.1 |
| Dev AWS | 10.200.0.2 | 172.16.200.2 |
| Prod ER605 | 10.200.1.1 | 172.17.200.1 |
| Prod AWS | 10.200.1.2 | 172.17.200.2 |

**New AllowedIPs (single entry covers everything):**
```
dev_tunnel peer:  AllowedIPs = 172.16.0.0/16 (covers tunnel 172.16.200.x + VPC 172.16.x.x)
prod_tunnel peer: AllowedIPs = 172.17.0.0/16 (covers tunnel 172.17.200.x + VPC 172.17.x.x)
```

---

**Configuration Changes Applied:**

**ER605 WireGuard Interface:**
```
dev_tunnel:  Local IP = 172.16.200.1
prod_tunnel: Local IP = 172.17.200.1
```

**ER605 WireGuard Peer:**
```
dev_tunnel peer:  AllowedIPs = 172.16.0.0/16
prod_tunnel peer: AllowedIPs = 172.17.0.0/16
```

**AWS EC2 WireGuard Config (/etc/wireguard/wg0.conf):**
```ini
# Dev EC2
[Interface]
Address = 172.16.200.2/16

# Prod EC2
[Interface]
Address = 172.17.200.2/16
```

---

**Phase 3 Verification:**
```bash
[root@ansible ~]# traceroute 172.17.65.73
traceroute to 172.17.65.73 (172.17.65.73), 30 hops max, 60 byte packets
 1  _gateway (10.0.53.1)  0.853 ms
 2  172.17.200.2  60.389 ms   <-- CORRECT! Prod tunnel
 3  172.17.65.73  61.234 ms
```

**Result:** Traffic now routed through correct tunnel ✓

**Additional Benefit:** Cross-tunnel reachability - both tunnel endpoints can now ping each other since they're in routable VPC ranges.

---
---

# PHASE 4: TRUE ROOT CAUSE DISCOVERY | 2026-04

## Symptoms (Phase 4)
After all previous fixes were applied:
- Tunnels still experienced intermittent drops
- Issue persisted even after migrating from ER605 to MikroTik router
- Ruled out router-specific issues since both ER605 and MikroTik experienced same behavior
- Random tunnel failures with no apparent pattern

---

## 3. Analysis (Phase 4)

**Check 1: Router Migration Test**
```
Before: ER605 WireGuard
After: MikroTik WireGuard

Result: Same intermittent tunnel drops on BOTH routers
```
Finding: Issue NOT router-specific. Something external. ✓

---

**Check 2: Pattern Analysis**
```
Observations:
- Tunnel works for hours/days
- Suddenly stops - no handshake
- AWS EC2 shows it's responding (tcpdump confirms)
- Responses not reaching local router
- Happens on both Dev and Prod randomly
```
Finding: Packets leaving AWS but not arriving at ISP. ✓

---

**Check 3: ISP Behavior Analysis**
```
Behind CGNAT:
- ISP controls all NAT mappings
- ISP can block specific public IPs
- No visibility into ISP-level decisions

AWS EIP:
- Each environment has dedicated Elastic IP
- EIP can be associated/disassociated
- New EIP = new public IP address
```
Finding: ISP may be blocking specific AWS public IPs intermittently. ✓

---

**Check 4: EIP Recreation Test**
```bash
# When tunnel down with no apparent cause:
# AWS Console → EC2 → Elastic IPs → Release old EIP → Allocate new EIP
# Update ER605/MikroTik with new endpoint IP
```
Finding: **Tunnel immediately works after EIP recreation!** ✓

---

## 4. Root Cause (FINAL - TRUE ROOT CAUSE)
> **ISP intermittently blocks AWS public IP addresses at CGNAT level.** This causes return traffic from AWS to never reach the local router, regardless of router type (confirmed on both ER605 and MikroTik). The blocking appears random and affects specific EIPs for periods of time.

**Why previous fixes helped but didn't fully resolve:**
| Fix | Why it helped | Why not complete solution |
|-----|---------------|---------------------------|
| NAT type change | Longer UDP timeouts | Didn't fix ISP IP blocking |
| Keepalive service | Prevented timeout drops | Useless if IP is blocked |
| VPC-range tunnel IPs | Fixed routing issues | Unrelated to ISP blocking |
| Port changes | Sometimes clears state | Temporary if IP still blocked |

---

## 5. Solution (FINAL)

**When tunnel drops with no apparent cause:**

**Step 1: Try Port Change First**
```
ER605/MikroTik: Change Listen Port
Example: 51820 → 51830 → 51840

Sometimes clears ISP CGNAT state without needing new EIP.
```

**Step 2: If Port Change Doesn't Work - Recreate AWS EIP**
```bash
# AWS Console Method:
1. Go to EC2 → Elastic IPs
2. Select the affected EIP
3. Actions → Disassociate (if associated)
4. Actions → Release Elastic IP address
5. Allocate new Elastic IP
6. Associate with EC2 instance
7. Update local router with new endpoint IP

# This may need to be done once or twice until ISP doesn't block the new IP
```

**Step 3: Update Local Router Configuration**
```
ER605/MikroTik → WireGuard → Peer → Endpoint
Update to new EIP address
```

**Important:** Keep AWS keepalive ping service running to ensure NAT mapping stays active and to quickly detect if blocking occurs again.

---

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Brief tunnel downtime during EIP recreation (~2-5 minutes)
- AWS EIP cost: Free while associated with running instance

## 7. Impact After Fix
- Observed: Tunnel immediately stable after EIP recreation
- Issue confirmed NOT router-specific (happened on both ER605 and MikroTik)
- Keepalive service provides early detection of future issues

---

## 8. Notes

**Final Architecture:**
```
AWS EC2 (REDACTED_EIP_DEV/PROD)
    │
    │ WireGuard (UDP 51820)
    │
ISP CGNAT ← ─ ─ ─ ─ [May block specific IPs randomly]
    │
Local Router (ER605/MikroTik)
    │
    ├── Dev Tunnel (172.16.200.x)
    └── Prod Tunnel (172.17.200.x)
```

**Keepalive Service Location:** AWS EC2 instances
- Purpose: Ping local tunnel endpoint every 5 seconds
- Benefit: Prevents NAT timeout AND provides quick detection of tunnel failure

**IP Addressing Summary:**
| Environment | Tunnel Subnet | AWS Tunnel IP | Local Tunnel IP |
|-------------|--------------|---------------|-----------------|
| Dev | 172.16.200.0/24 | 172.16.200.2 | 172.16.200.1 |
| Prod | 172.17.200.0/24 | 172.17.200.2 | 172.17.200.1 |

**AllowedIPs Configuration:**
| Tunnel | AllowedIPs | Coverage |
|--------|------------|----------|
| Dev | 172.16.0.0/16 | Tunnel + VPC range |
| Prod | 172.17.0.0/16 | Tunnel + VPC range |

**Verification Commands:**
```bash
# On AWS EC2 - Check WireGuard status
sudo wg show wg0

# On AWS EC2 - Check keepalive service
sudo systemctl status wg-keepalive
journalctl -u wg-keepalive -f

# On AWS EC2 - Watch handshake times
watch -n 60 'sudo wg show wg0 latest-handshakes'

# On AWS EC2 - Check for blocked traffic
sudo tcpdump -i enX0 udp port 51820 -n

# On local network - Check routing path
traceroute 172.17.65.73
```

**References:**
- `network/vpn/wireguard-setup.md` - Full VPN setup documentation
- `network/vpn/wireguard-config.txt` - Quick reference configuration

## 9. Workaround (if any)
> **Immediate fix when tunnel fails:**
> 1. Try changing UDP port first (quick)
> 2. If still failing, delete and recreate AWS Elastic IP (definitive)
> 3. Update local router endpoint with new EIP
> 4. In shaa Allah, tunnel will be back up

---

## Investigation Summary

| Phase | Date | Suspected Cause | Actual Finding |
|-------|------|-----------------|----------------|
| 1 | 2026-03-11 | NAT timeout | Partial - contributed but not root |
| 2 | 2026-03-11 | VLAN gateway ACL | Workaround - changed keepalive target |
| 3 | 2026-03-11 | Wrong tunnel routing | Fixed - VPC-range tunnel IPs |
| 4 | 2026-04 | ISP blocking AWS IPs | **TRUE ROOT CAUSE** |

**Key Learning:** When tunnel issues persist across different router hardware (ER605 → MikroTik), the problem is upstream - in this case, ISP CGNAT intermittently blocking specific AWS public IPs.

