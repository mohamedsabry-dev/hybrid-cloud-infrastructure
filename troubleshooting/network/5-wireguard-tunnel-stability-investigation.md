# TS-NET-005 | 2026-03-11 to 2026-04 | RESOLVED
_____________________________________________________________________

[Info]
Author:
Domain: Networking / VPN
Sub-techs: WireGuard, CGNAT, AWS EIP, NAT timeout, tunnel routing, AllowedIPs,
           ER605, MikroTik, AWS EC2, keepalive service, systemd
Environment: ER605 → AWS (Dev & Prod tunnels), later MikroTik → AWS
Re-opened: No

_____________________________________________________________________

[Issue Description]
WireGuard tunnels intermittently dropping, requiring manual intervention.
Multiple suspected root causes investigated over time across 4 phases.

Error patterns:
  - Tunnel works initially, drops after idle time
  - No handshake status on local router
  - TX bytes increasing, RX: 0 B (sending but nothing coming back)
  - Connection timeouts from internal hosts to AWS

This ticket covers the full investigation journey before discovering the true root cause.

Related ticket: TS-NET-004 — CGNAT port blocking (related but separate incident)

_____________________________________________________________________

[Analysis]

# Initial Check Notes:

_____________________________________________________________________
PHASE 1 | 2026-03-11 | NAT Timeout Investigation
_____________________________________________________________________

Tunnel worked initially then dropped after ~1 hour of idle time.
No handshake, connection timeout. Required manual restart on both sides.

Check 1 — ISP router NAT configuration:
  NAT Type: Port-Restricted Cone NAT
  Finding: Port-Restricted Cone NAT drops UDP mappings after inactivity
  timeout (~60 minutes). Blocks incoming packets if no recent outgoing
  traffic. Causes WireGuard handshakes to fail after timeout.

Check 2 — WireGuard keepalive settings on ER605:
  Persistent Keepalive = 25 seconds per peer
  Finding: ER605 sending keepalives but not sufficient alone.
  Need bidirectional keepalive to maintain NAT mapping reliably.

Phase 1 fix — Part 1: Change ISP NAT type:
  From: Port-Restricted Cone NAT
  To:   Full Cone NAT

  Full Cone NAT benefits:
    Maintains UDP mappings longer.
    Allows incoming packets from any source once mapping exists.
    More permissive for VPN traffic.

Phase 1 fix — Part 2: AWS keepalive ping service:
  Created systemd service on AWS EC2 to send regular pings through tunnel,
  preventing NAT timeout from either side.

  File: /etc/systemd/system/wg-keepalive.service

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

  Enable:
    sudo systemctl daemon-reload
    sudo systemctl enable --now wg-keepalive

  Keepalive targets:
    Dev EC2   → ping 172.16.200.1  (ER605 dev tunnel IP)
    Prod EC2  → ping 172.17.200.1  (ER605 prod tunnel IP)

  Parameters:
    Restart=always    always restart if service crashes
    RestartSec=10     wait 10s before restart (prevents rapid restart loops)
    sleep 5           ping every 5 seconds (aggressive, prevents any NAT timeout)

  Verification:
    sudo systemctl status wg-keepalive
    journalctl -u wg-keepalive -f
    watch -n 60 'sudo wg show wg0 latest-handshakes'

Phase 1 result:
  Tunnel survived extended idle periods, EC2 reboots (service auto-starts),
  and network interruptions (service auto-restarts).

Phase 1 status: PARTIAL FIX — contributed but not the root cause.


_____________________________________________________________________
PHASE 2 | 2026-03-11 | VLAN Gateway Ping Failure
_____________________________________________________________________

Prod EC2 could ping hosts in VLAN 55 (10.0.55.x) but NOT the VLAN gateway
(10.0.55.1). Dev EC2 could ping both hosts and gateway in VLAN 65.
Keepalive service failing on Prod EC2 due to ping target unreachable.

Check 1 — Connectivity test from Prod EC2:
  ping 10.0.55.10 → works (host in VLAN)
  ping 10.0.55.1  → Request timeout (VLAN gateway interface)

Check 2 — ER605 ACL rules:
  Rule: vpn_prod → DataCenter_Cairo (Allow) exists.
  Finding: ACL covers traffic THROUGH the router. Traffic TO the router's
  own VLAN interface (10.0.55.1) takes a different firewall path on ER605.
  ER605 treats traffic destined for its own interfaces differently.

Phase 2 fix — Change keepalive target:
  Old target: 10.0.55.1  (VLAN gateway — blocked by ER605 firewall)
  New target: 172.17.200.1 (tunnel peer IP — always reachable as tunnel endpoint)

  Updated wg-keepalive.service:
    ExecStart=/bin/bash -c 'while true; do ping -c 1 172.17.200.1 > /dev/null 2>&1; sleep 5; done'

  Why this works: tunnel IPs are VPC-range endpoints, pinging them serves
  the same keepalive purpose and is guaranteed to work.

Phase 2 status: WORKAROUND — changed keepalive target, underlying ACL not resolved.


_____________________________________________________________________
PHASE 3 | 2026-03-11 | Wrong Tunnel Routing
_____________________________________________________________________

Prod internal hosts (10.0.5x.x) could not reach Prod AWS EC2 (172.17.x.x).
Dev internal hosts could reach Dev EC2 normally.
Prod EC2 could reach internal hosts, but internal could NOT initiate to Prod EC2.
Traffic going through the wrong tunnel.

Check 1 — Ping from internal host:
  ping 172.17.65.73 → 100% packet loss

Check 2 — Traceroute (CRITICAL FINDING):

  traceroute 172.17.65.73
  1  _gateway (10.0.53.1)   0.853 ms
  2  10.200.0.2             60.389 ms   ← WRONG TUNNEL (dev tunnel)
  3  * * *

  Traffic to PROD AWS (172.17.x.x) was routing through DEV tunnel (10.200.0.2)
  instead of PROD tunnel (10.200.1.2).

Check 3 — ER605 AllowedIPs configuration:
  dev_tunnel peer:  AllowedIPs = 0.0.0.0/0
  prod_tunnel peer: AllowedIPs = 0.0.0.0/0

  Both peers set to 0.0.0.0/0 — ER605 cannot distinguish which tunnel to use.
  ER605 defaulting to dev_tunnel for ALL traffic.

Check 4 — ER605 AllowedIPs limitation discovered:
  ER605 WireGuard peer AllowedIPs field only accepts ONE entry.

  Original tunnel IPs were in a separate range (10.200.x.x) requiring two entries:
    Tunnel IP:  10.200.1.0/24
    VPC CIDR:   172.17.0.0/16
  But ER605 only allows ONE — impossible to specify both ranges.

  Behaviour with different AllowedIPs settings:
    10.200.1.0/24 (tunnel only)  → VPN→Internal works, Internal→VPN fails
    172.17.0.0/16 (VPC only)    → Internal→VPN works, VPN→Internal fails
    0.0.0.0/0 (any)             → ER605 picks ONE tunnel for ALL traffic

Phase 3 root cause: ER605 single AllowedIPs limitation + tunnel IPs outside
VPC CIDR range = no way to route correctly with two tunnels.

Phase 3 fix — place tunnel IPs INSIDE the AWS VPC CIDR range:
  Single AllowedIPs entry then covers both tunnel IP and VPC CIDR.

  IP address changes:
    Dev  ER605 tunnel IP:  10.200.0.1 → 172.16.200.1
    Dev  AWS tunnel IP:    10.200.0.2 → 172.16.200.2
    Prod ER605 tunnel IP:  10.200.1.1 → 172.17.200.1
    Prod AWS tunnel IP:    10.200.1.2 → 172.17.200.2

  New AllowedIPs (single entry covers everything):
    dev_tunnel peer:  AllowedIPs = 172.16.0.0/16  (covers 172.16.200.x tunnel + 172.16.x.x VPC)
    prod_tunnel peer: AllowedIPs = 172.17.0.0/16  (covers 172.17.200.x tunnel + 172.17.x.x VPC)

  ER605 WireGuard interface updates:
    dev_tunnel:  Local IP = 172.16.200.1
    prod_tunnel: Local IP = 172.17.200.1

  AWS EC2 /etc/wireguard/wg0.conf updates:
    Dev EC2:  Address = 172.16.200.2/16
    Prod EC2: Address = 172.17.200.2/16

Phase 3 verification:
  traceroute 172.17.65.73
  1  _gateway (10.0.53.1)   0.853 ms
  2  172.17.200.2           60.389 ms   ← CORRECT (prod tunnel)
  3  172.17.65.73           61.234 ms

  Additional benefit: both tunnel endpoints can now ping each other since
  they are in routable VPC ranges.

Phase 3 status: FIXED — tunnel routing correct. But intermittent drops continued.


_____________________________________________________________________
PHASE 4 | 2026-04 | TRUE ROOT CAUSE IDENTIFIED
_____________________________________________________________________

After all previous fixes applied, tunnels still experienced intermittent drops.
Issue persisted after migrating from ER605 to MikroTik router.
Both routers experienced same behaviour — confirmed NOT router-specific.
Random tunnel failures with no apparent pattern.

Check 1 — Router migration test:
  Before: ER605 WireGuard
  After:  MikroTik WireGuard
  Result: Same intermittent tunnel drops on both routers.
  Finding: issue is NOT router-specific — something external.

Check 2 — Pattern analysis:
  Tunnel works for hours or days.
  Suddenly stops, no handshake.
  AWS EC2 tcpdump confirms it is responding (packets leaving AWS).
  Responses not arriving at local router.
  Happens on both Dev and Prod randomly.
  Finding: packets leaving AWS but not arriving at ISP side.

Check 3 — ISP CGNAT behaviour analysis:
  Under CGNAT, ISP controls all NAT mappings at infrastructure level.
  ISP can block specific public IPs — no visibility into ISP-level decisions.
  AWS EIP is a dedicated public IP per environment.
  New EIP = new public IP address from AWS pool.

Check 4 — EIP recreation test (CRITICAL FINDING):
  When tunnel down with no apparent cause:
    AWS Console → EC2 → Elastic IPs → Release old EIP → Allocate new EIP
    Associate new EIP with EC2 instance.
    Update local router endpoint with new IP.

  Result: tunnel immediately works after EIP recreation.
  Confirmed: ISP CGNAT was blocking the specific AWS public IP.


# Suspected Root Cause
ISP intermittently blocks specific AWS Elastic IP addresses at CGNAT
infrastructure level. Return traffic from AWS never reaches local router.
Blocking appears random, affects specific EIPs for periods of time.
Confirmed on both ER605 and MikroTik — completely router-independent.


# More Checks Notes:
Why previous fixes helped but did not fully resolve:
  NAT type change (Phase 1)     → longer UDP timeouts, but doesn't fix IP blocking
  Keepalive service (Phase 1)   → prevents timeout drops, useless if IP is blocked
  VPC-range tunnel IPs (Phase 3)→ fixed routing, unrelated to ISP blocking
  Port change (TS-NET-004)      → sometimes clears CGNAT state, temporary relief


# Suspected Solution
When tunnel drops with no apparent cause:
  Step 1: try port change (quick, sometimes clears CGNAT state)
  Step 2: if port change fails, recreate AWS EIP (definitive fix)


# Test
Released affected EIP, allocated new EIP, associated with EC2, updated router.

Result: PASS — tunnel immediately stable after EIP recreation.

_____________________________________________________________________

[Final Root Cause]
ISP intermittently blocks specific AWS Elastic IP addresses at CGNAT level.
This causes return traffic from AWS to never reach the local router — regardless
of router type (confirmed identical behaviour on both ER605 and MikroTik).
The blocking appears random and affects specific EIPs for unpredictable periods.
This was the root cause of all recurring tunnel drops throughout the investigation.
All other issues found (NAT timeout, keepalive target, wrong routing) were real
problems but were separate from the true root cause.

_____________________________________________________________________

[Final Solution]

When tunnel drops with no apparent cause — follow this sequence:

Step 1: Try port change first (quick, ~1 minute):
  ER605 or MikroTik → WireGuard → peer → change Listen Port
  Example: 51820 → 51830 → 51840
  Sometimes clears ISP CGNAT stale state without needing new EIP.

Step 2: If port change does not work — recreate AWS EIP (~5 minutes):
  AWS Console → EC2 → Elastic IPs
  1. Select affected EIP
  2. Actions → Disassociate (if associated)
  3. Actions → Release Elastic IP address
  4. Allocate new Elastic IP
  5. Associate with EC2 instance
  6. Update local router endpoint with new EIP address
  May need to repeat once or twice until ISP does not block the new IP.

Keep keepalive service running at all times:
  Provides early detection — if pings stop, tunnel is down.
  Maintains NAT mapping so timeout is not an additional failure mode.

Final tunnel IP addressing:
  Dev  ER605/MikroTik tunnel IP: 172.16.200.1
  Dev  AWS EC2 tunnel IP:        172.16.200.2
  Prod ER605/MikroTik tunnel IP: 172.17.200.1
  Prod AWS EC2 tunnel IP:        172.17.200.2

Final AllowedIPs configuration:
  dev_tunnel peer:  172.16.0.0/16  (covers tunnel + VPC range)
  prod_tunnel peer: 172.17.0.0/16  (covers tunnel + VPC range)

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Brief tunnel downtime during EIP recreation (~2-5 minutes).
AWS EIP cost: free while associated with a running instance.

_____________________________________________________________________

[References]
- network/vpn/wireguard-setup-guide.txt
- network/vpn/wireguard-config.txt
- TS-NET-004 — CGNAT port blocking (related separate incident)

_____________________________________________________________________

[Draft Notes]

Full investigation timeline:
  Phase 1  2026-03-11  NAT timeout          Partial — contributed but not root cause
  Phase 2  2026-03-11  VLAN gateway ACL      Workaround — changed keepalive target
  Phase 3  2026-03-11  Wrong tunnel routing  Fixed — VPC-range tunnel IPs
  Phase 4  2026-04     ISP blocking AWS IPs  TRUE ROOT CAUSE

Key learning: when tunnel issues persist across different router hardware
(ER605 → MikroTik), the problem is upstream. Router migration is a valid
diagnostic step — if same issue occurs on different hardware, eliminate the
router and look at ISP or cloud side.

Architecture overview:
  AWS EC2 (EIP_DEV / EIP_PROD)
      │ WireGuard UDP 51820
  ISP CGNAT  ← may block specific AWS IPs intermittently
      │
  Local Router (ER605 or MikroTik)
      ├── Dev Tunnel  172.16.200.x
      └── Prod Tunnel 172.17.200.x

Keepalive service reference:
  Location: AWS EC2 instances (both Dev and Prod)
  File: /etc/systemd/system/wg-keepalive.service
  Ping target: local tunnel endpoint (172.16.200.1 or 172.17.200.1)
  Interval: every 5 seconds
  Purpose: prevent NAT timeout AND detect tunnel failure early

Verification commands:
  sudo wg show wg0                              WireGuard status on AWS
  sudo systemctl status wg-keepalive           keepalive service status
  journalctl -u wg-keepalive -f               keepalive live logs
  watch -n 60 'sudo wg show wg0 latest-handshakes'  monitor handshake times
  sudo tcpdump -i enX0 udp port 51820 -n      check if AWS receiving/sending
  traceroute 172.17.65.73                      verify correct tunnel path from internal

ER605 limitation note:
  WireGuard peer AllowedIPs field only accepts ONE entry.
  Must design IP addressing so single CIDR covers both tunnel IP and VPC CIDR.
  Placing tunnel IPs inside VPC CIDR range (e.g. 172.16.200.x inside 172.16.0.0/16)
  is the correct workaround for this limitation.