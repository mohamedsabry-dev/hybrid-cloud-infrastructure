# TS-NET-006 | 2026-05-22 | TEMP SOLVED
_____________________________________________________________________

[Info]
Domain: Networking / VPN / AWS
Sub-techs: WireGuard, AWS VPC, Security Groups, iptables, Linux routing,
           wg-quick, CIDR masks, connected routes, INPUT/FORWARD chains
Environment: AWS Prod — VPC 172.17.0.0/16, WireGuard EC2 (172.17.65.35),
             test EC2 in mgmt subnet (172.17.63.0/24)
Re-opened: No

_____________________________________________________________________

[Issue Description]
New EC2 instances in AWS mgmt subnet (172.17.63.0/24) could not reach
on-prem hosts (10.0.5x.0/24) through the WireGuard VPN EC2, and could
not even ping the VPN EC2's private IP (172.17.65.35).

Symptoms:
  - ping from 172.17.63.30 → 172.17.65.35: 100% packet loss (timeout)
  - ping from 172.17.63.30 → 10.0.55.10: 100% packet loss
  - ping from 172.17.65.x (same subnet) → 172.17.65.35: works
  - ping via public IP between instances: works
  - VPN tunnel itself healthy (wg show: handshake active, 150+ MiB transferred)

Goal: enable mgmt subnet EC2 instances to reach on-prem via VPN tunnel.

_____________________________________________________________________

[Analysis]

# Investigation approach: traced the packet path layer by layer.

_____________________________________________________________________
PHASE 1 | Security Group Investigation
_____________________________________________________________________

Check 1 — VPC route table:
  Route: 10.0.0.0/16 → WireGuard EC2 primary ENI
  Both subnets (vpn 172.17.65.0/24, mgmt 172.17.63.0/24) share same
  route table (rt_public). Routing logic correct.

Check 2 — Security Group inbound rules:
  wireguard-sg-prod only allowed:
    - UDP 51820 from home IP (Personal_IP/32)
    - TCP 22 from home IP
    - Egress: all

  Finding: no rule allowing inbound from VPC instances.
  AWS SGs apply to ALL traffic hitting an ENI, including transit/forwarded
  traffic. source_dest_check=false lets the ENI accept packets not
  addressed to it, but does NOT bypass SG evaluation.

  Fix attempt 1: added "All traffic" from 172.17.63.0/24 to SG.
  Result: STILL FAILED. Ping from 63.x to 65.x still 100% loss.

  NOTE: This SG change was done MANUALLY in AWS console.
  TODO: Add this rule via Terraform in compute/main.tf before next apply,
  or the manual rule will be destroyed on next terraform apply.

_____________________________________________________________________
PHASE 2 | Layer Elimination
_____________________________________________________________________

Check 3 — Created additional test EC2s (one per subnet):
  Finding: test EC2s in different subnets could ping EACH OTHER normally.
  But mgmt EC2 could NOT reach the VPN main EC2 or transit through it.
  Test VPN EC2 (65.x) could reach VPN main EC2 and transit to on-prem.

  Pattern: the issue is specific to the VPN main EC2 receiving from
  a different subnet. Not a VPC/NACL/SG issue.

Check 4 — tcpdump on VPN EC2 (ens5):
  Finding: ICMP echo requests from 63.x ARRIVE at ens5 (visible in capture).
  But NO echo reply is generated. Packet dies inside the Linux kernel.
  From 65.x (same subnet), ping succeeds silently (not visible in capture
  on ens5 — handled without showing in same tcpdump session).

  This proved: SG passed, NACL passed, VPC routing delivered the packet.
  Drop is inside the OS.

_____________________________________________________________________
PHASE 3 | Internal OS Investigation
_____________________________________________________________________

Check 5 — iptables:
  sudo iptables -L FORWARD -n -v
    Chain FORWARD (policy ACCEPT) — 2 rules (-i wg0, -o wg0) — clean.
  sudo iptables -L INPUT -n -v
    Chain INPUT (policy ACCEPT) — no rules — clean.
  sudo iptables-save
    Only FORWARD rules from WireGuard PostUp + NAT MASQUERADE. Nothing blocking.

Check 6 — nftables / firewalld:
  /usr/sbin/nft: command not found
  firewalld.service: could not be found
  Neither installed. Eliminated.

Check 7 — ICMP settings:
  net.ipv4.icmp_echo_ignore_all = 0 (responds to ping)
  net.ipv4.icmp_echo_ignore_broadcasts = 1 (irrelevant)

Check 8 — rp_filter (reverse path filtering):
  net.ipv4.conf.all.rp_filter = 0
  net.ipv4.conf.wg0.rp_filter = 2 (loose)
  net.ipv4.conf.ens5.rp_filter = 2 (loose)
  net.ipv4.conf.default.rp_filter = 2
  Not the issue — loose mode only checks reachability via ANY interface.

_____________________________________________________________________
PHASE 4 | Root Cause Found — WireGuard Address Mask
_____________________________________________________________________

Check 9 — tcpdump on wg0 while pinging from 63.x:
  Captured ICMP echo REPLIES leaving via wg0, addressed to 172.17.63.x.
  No echo requests on wg0 (they arrived on ens5).

  The kernel was generating the reply, but routing it
  OUT THE WRONG INTERFACE. Replies to 63.x were going into the
  WireGuard tunnel instead of back to ens5/VPC.

Check 10 — WireGuard interface config:
  ip a show wg0:
    inet 172.17.200.2/16 scope global wg0

  The /16 mask on wg0 installed a connected route:
    172.17.0.0/16 dev wg0 proto kernel scope link src 172.17.200.2

  This route claimed the ENTIRE VPC CIDR (172.17.0.0/16) as reachable
  via wg0. When the kernel needed to reply to 172.17.63.30:
    - 172.17.63.30 matches 172.17.65.0/24 dev ens5? No (65 ≠ 63).
    - 172.17.63.30 matches 172.17.0.0/16 dev wg0? Yes → reply sent to wg0.

  Same-subnet (65.x) worked because 172.17.65.0/24 dev ens5 is more
  specific than /16 and wins the route lookup. Cross-subnet (63.x) had
  no specific /24 route, so the /16 hijacked it.

Check 11 — Route table evidence (confirmed the hijack):
  $ route
  Destination     Gateway   Genmask         Flags Metric Ref Use Iface
  default         172.17.65.1  0.0.0.0      UG    512    0   0   ens5
  10.0.5.0        0.0.0.0   255.255.255.0   U     0      0   0   wg0
  10.0.50.0       0.0.0.0   255.255.255.0   U     0      0   0   wg0
  10.0.51.0       0.0.0.0   255.255.255.0   U     0      0   0   wg0
  10.0.52.0       0.0.0.0   255.255.255.0   U     0      0   0   wg0
  10.0.53.0       0.0.0.0   255.255.255.0   U     0      0   0   wg0
  10.0.54.0       0.0.0.0   255.255.255.0   U     0      0   0   wg0
  10.0.55.0       0.0.0.0   255.255.255.0   U     0      0   0   wg0
  172.17.0.0      0.0.0.0   255.255.0.0     U     0      0   0   wg0    ← THE HIJACK
  172.17.65.0     0.0.0.0   255.255.255.0   U     512    0   0   ens5

  The 172.17.0.0/16 dev wg0 route is the connected route from Address=/16.
  172.17.65.0/24 dev ens5 (more specific) wins for same-subnet traffic.
  Everything else in 172.17.0.0/16 (including 172.17.63.0/24) → wg0.

_____________________________________________________________________

[Final Root Cause]
CONFIRMED — WireGuard wg0.conf had Address = 172.17.200.2/16.

The /16 mask created a connected route that captured the entire VPC CIDR
(172.17.0.0/16) on the wg0 interface. Any traffic to VPC IPs outside the
VPN EC2's own /24 subnet (172.17.65.0/24) was routed into the tunnel
instead of back to the VPC via ens5.

For site-to-site WireGuard, the Address mask controls the connected
route, NOT the tunnel routing. Tunnel routing is controlled by AllowedIPs.
Using /16 was a configuration issue — it should match only the tunnel
endpoint subnet, not the entire VPC.

_____________________________________________________________________

[Final Solution]

Step 1 — Edit WireGuard config:
  sudo vi /etc/wireguard/wg0.conf

  Change:
    Address = 172.17.200.2/16
  To:
    Address = 172.17.200.2/24

Step 2 — Bounce interface (or reboot):
  sudo wg-quick down wg0
  sudo wg-quick up wg0

Step 3 — Verify:
  ip addr show wg0                     # confirm /24
  ip route show | grep wg0             # no 172.17.0.0/16, only 10.0.x.x + 172.17.200.0/24
  ip route get 172.17.63.30            # should return dev ens5
  ip route get 10.0.55.10              # should return dev wg0
  ping -c 2 172.17.200.1               # tunnel peer
  ping -c 2 10.0.55.10                 # on-prem host

Step 4 — Test from mgmt subnet EC2:
  ping -c 2 172.17.65.35               # VPN EC2 private IP
  ping -c 2 10.0.55.10                 # on-prem via transit

Result: both work after reboot with /24 config.

MANUAL CHANGE PENDING TERRAFORM:
  Security Group wireguard-sg-prod was manually updated in AWS console
  to add inbound rule: All traffic from 172.17.63.0/24.
  This must be added to terraform/prod/aws/compute/main.tf before next
  terraform apply, or it will be destroyed.

SETUP SCRIPT UPDATED:
  network/vpn/setup-wireguard.sh had the /16 hardcoded for both envs.
  Changed TUNNEL_IP from /16 to /24 for both dev and prod so future
  EC2 rebuilds don't reintroduce this bug.

SAME FIX NEEDED ON DEV:
  Check dev WireGuard EC2 — if Address = 172.16.200.2/16, change to /24.
  Same bug exists but hasn't manifested because no cross-subnet EC2s
  exist in dev VPC yet.

_____________________________________________________________________

[Failed Attempts During Investigation]

1. Adding SG rule for 172.17.63.0/24 — necessary but not sufficient.
   The SG was blocking, but fixing it alone didn't solve the problem
   because the /16 route was the real blocker.

2. Manual ip addr del/add (live fix without config edit):
   sudo ip addr del 172.17.200.2/16 dev wg0
   sudo ip addr add 172.17.200.2/24 dev wg0

   This fixed the cross-subnet ping but BROKE the 10.0.x.x routes.
   Reason: wg-quick installs AllowedIPs routes when the interface comes
   up. Manually deleting and re-adding the address does NOT re-trigger
   wg-quick's route installation. The 10.0.x.x dev wg0 routes vanished,
   and 10.0.55.1 started routing via ens5 (default route) → dropped by AWS.

   ip route get 10.0.55.1 confirmed: "via 172.17.65.1 dev ens5" (wrong).

   Fix: edit wg0.conf first, then wg-quick down/up (or reboot). wg-quick
   re-reads the config and installs all routes from AllowedIPs fresh.

_____________________________________________________________________

[Risk Level]
MEDIUM — VPN connectivity for new AWS workloads blocked. Tunnel to
on-prem unaffected (existing traffic worked). No data loss. Risk of
wider impact if manual ip addr edit is done without wg-quick bounce
(drops all tunnel routes as discovered).

_____________________________________________________________________

[References]
- terraform/prod/aws/compute/main.tf — WireGuard EC2 + SG definition
- terraform/prod/aws/network/main.tf — VPC, subnets, route table
- /etc/wireguard/wg0.conf on wg-prod EC2 — tunnel config
- network/vpn/setup-wireguard.sh — setup script (TUNNEL_IP updated /16→/24)
- network/vpn/wireguard-config.txt — tunnel reference (updated /16→/24)
- network/vpn/wireguard-setup-guide.txt — setup guide (updated /16→/24)
- TS-NET-005 — previous WireGuard tunnel stability investigation

_____________________________________________________________________

[Draft Notes]

Lessons:
  - WireGuard Address mask ≠ tunnel scope. Address sets a connected route.
    AllowedIPs sets tunnel routing. Two independent mechanisms.
  - For site-to-site tunnels where the tunnel IP is just an endpoint
    identifier, use /24 or /32. Never use /16 unless the entire /16 is
    actually tunnel-side hosts.
  - Never live-edit wg0 address with ip addr commands. Always edit
    wg0.conf and bounce via wg-quick, otherwise AllowedIPs routes are lost.
  - AWS SGs apply to transit traffic on ENIs used as route targets.
    source_dest_check=false does not bypass SG evaluation.
  - When debugging "packet arrives but no reply": check the REPLY routing
    path, not just the inbound path. ip route get <source_ip> tells you
    where the reply actually goes.

Prevention:
  - Audit all WireGuard Address lines: mask should never overlap with
    non-tunnel subnets reachable via other interfaces.
  - Add Terraform rule for SG before next apply.
  - Apply same /24 fix on dev WireGuard EC2.
