# TS-NET-004 | 2026-03 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Networking / VPN
Sub-techs: WireGuard, CGNAT, UDP port blocking, ER605, AWS EC2, tcpdump
Environment: Prod WireGuard tunnel (ER605 → AWS EC2 Prod)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Prod WireGuard tunnel showing no handshake for ~5 days. Dev tunnel on same
setup working perfectly throughout.

  prod_tunnel  TX: 3.0 KiB   RX: 0 B    Last handshake: ---
  dev_tunnel   TX: 34.6 KiB  RX: 34.4 KiB  Last handshake: 1 second ago

TX increasing but RX: 0 B — ER605 sending packets but receiving nothing back.

Related ticket: TS-NET-005 — WireGuard stability investigation

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Ruled out key mismatch and time sync first — both confirmed fine.

Checked if AWS was receiving and responding using tcpdump:

Command:
  sudo tcpdump -i enX0 udp port 51820 -n  (on AWS EC2)

Output:
  REDACTED_ISP_PUBLIC:51821 > 172.17.65.73:51820  UDP length 148  (ER605 → AWS, handshake init)
  172.17.65.73:51820 > REDACTED_ISP_PUBLIC:51821  UDP length 92   (AWS → ER605, handshake response)

AWS is receiving packets AND sending responses back.
Responses are NOT reaching ER605.
Problem is between AWS and ER605 — something blocking the return path.

Tried ISP router port forwarding:
  Added WireGuard_Prod rule: UDP external 51821 → internal 192.168.100.175:51821
  Result: still not working.

Tried ISP router DMZ:
  Set ER605 (192.168.100.175) as DMZ host to bypass all port restrictions.
  Result: still not working.

Both fixes failed — checked ISP router routing table to understand why:

  Route entry: Destination 100.122.0.1 / 255.255.255.255 → Interface TR069_INTERNET

  100.122.0.1 is in the CGNAT range (100.64.0.0/10).
  ISP is using Carrier-Grade NAT — the real NAT is happening at ISP infrastructure
  level, not at the local router. Port forwarding and DMZ on the local ISP router
  are completely useless under CGNAT because they only affect the local NAT — the
  ISP-level NAT is upstream and not configurable.

  ISP was blocking port 51821 specifically at the CGNAT level.
  Dev tunnel on port 51820 was not blocked — that is why dev worked fine throughout.


# Suspected Root Cause
ISP CGNAT blocking port 51821 at infrastructure level. Port forwarding and DMZ
on local ISP router have no effect — real NAT and filtering happens upstream.


# More Checks Notes:
CGNAT detection method: check ISP router routing table for any address in
100.64.0.0/10 range. Presence of a 100.x.x.x route confirms CGNAT.

Why dev tunnel worked:
  Both tunnels work by ER605 initiating outbound — creates NAT mapping.
  PersistentKeepalive (25 sec) maintains the NAT mapping.
  Dev port 51820 was not blocked at CGNAT level.
  Prod port 51821 was blocked — responses never reached ER605.


# Suspected Solution
Change prod_tunnel Listen Port on ER605 to a different UDP port that is
not blocked at CGNAT level.


# Test
Changed ER605 prod_tunnel Listen Port from 51821 to 51830.
No changes needed on AWS side — AWS responds to whatever source port it receives from.

Result: PASS — handshake established immediately after port change.

Post-resolution cleanup:
  Disabled DMZ on ISP router.
  Deleted WireGuard_Prod port forwarding rule.
  Neither is needed — ER605 initiates outbound and PersistentKeepalive
  maintains the NAT mapping. DMZ and port forwarding are irrelevant under CGNAT.

Post-fix retest — tried reverting to port 51821:
  Result: port 51821 worked with no issues after reverting.

Possible explanations for this:
  1. Temporary ISP CGNAT issue that cleared during troubleshooting
  2. Stale state on ER605 that cleared after config changes
  3. DMZ/port forwarding changes triggered something at ISP level

Decision: keep port 51830 as precaution in case 51821 gets blocked again.

_____________________________________________________________________

[Final Root Cause]
ISP uses CGNAT (confirmed via 100.64.0.0/10 route in ISP router routing table).
Port 51821 was being blocked at ISP CGNAT level — AWS was responding but responses
never reached ER605. Port forwarding and DMZ on the local ISP router have no effect
under CGNAT because the real NAT and filtering happen at ISP infrastructure level,
upstream of the local router. Dev tunnel on port 51820 was unaffected because that
port was not blocked.

Note: port 51821 worked again after changing to 51830 and back — exact cause of
original blockage not fully confirmed (temporary CGNAT issue, stale state, or
side effect of config changes during troubleshooting).

_____________________________________________________________________

[Final Solution]
Changed prod_tunnel Listen Port on ER605 from 51821 to 51830.

  ER605 → VPN → WireGuard → prod_tunnel → Edit → Listen Port: 51830

  No AWS changes needed.
  Disabled DMZ and removed port forwarding rule from ISP router.

Current port configuration:
  dev_tunnel   ER605 port 51820  AWS port 51820
  prod_tunnel  ER605 port 51830  AWS port 51820

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: No impact — just using a different port number.

_____________________________________________________________________

[References]
- network/vpn/wireguard-setup.md
- network/vpn/wireguard-config.txt

_____________________________________________________________________

[Draft Notes]

CGNAT detection: check ISP router routing table for any address in 100.64.0.0/10.
If present, ISP is using CGNAT — port forwarding and DMZ on local router are useless.

Key lesson: tcpdump on the remote side (AWS) is essential for diagnosing WireGuard
handshake failures. It immediately shows whether the remote is receiving packets and
responding — narrows the problem to either the sending side or the return path.

Under CGNAT + PersistentKeepalive, no port forwarding or DMZ is needed at all.
ER605 initiates outbound, CGNAT creates the mapping, keepalive maintains it.
The only thing that matters is the ISP not blocking the outbound UDP port.

ER605 limitation: very poor CLI makes it hard to diagnose internal router state.
When troubleshooting WireGuard on ER605, rely on tcpdump on the remote (AWS) side
rather than trying to extract diagnostic info from the ER605 itself.