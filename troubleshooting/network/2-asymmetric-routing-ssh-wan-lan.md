# TS-NET-002 | 2026-02-12 | RESOLVED
_____________________________________________________________________

[Info]
Domain: Networking
Sub-techs: Asymmetric routing, TCP, SSH, Proxmox network interfaces
Environment: Home network | Mac Mini 192.168.0.223 | ER605 | Proxmox DEV (WiFi 10.0.5.110, vmbr0 192.168.0.220)
Re-opened: No

_____________________________________________________________________

[Issue Description]
SSH from WAN to Proxmox hangs with no password prompt. Ping works fine.

  ping 10.0.5.110 from Mac Mini       → PASS
  SSH to 10.0.5.110 from Mac Mini     → hangs, then connection reset
  SSH from same VLAN (10.0.5.x)       → PASS
  curl HTTP to 10.0.5.110             → FAIL

  kex_exchange_identification: read: Connection reset by peer

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked the obvious first — SSH service, firewall, routing table.

Command:
  systemctl status ssh
  ip route

Output:
  SSH running, listening on 0.0.0.0:22.
  Default gateway correct: 10.0.5.1 via wlp1s0.

Proxmox firewall was disabled at datacenter level — not the cause.

Tried adding ER605 ACL rules to allow return traffic — still failed.

Ran verbose SSH to see where it stalls:

Command:
  ssh -v root@10.0.5.110

Output:
  Connection established, then hung, then connection reset.
  TCP handshake starts but never completes properly.


# Suspected Root Cause
Something is causing the TCP handshake to break after the initial connection.
Ping (ICMP) works fine — TCP-specific problem. Suspected routing asymmetry.


# More Checks Notes:
Discovered Proxmox had TWO network paths to 192.168.0.x:

  Path 1: WiFi (wlp1s0) → gateway 10.0.5.1 → ER605 → WAN → 192.168.0.x
  Path 2: vmbr0 with IP 192.168.0.220 → direct to 192.168.0.x (same subnet)

Inbound traffic from Mac Mini (192.168.0.223) arrived via WiFi interface.
Proxmox reply went out via vmbr0 — same subnet as source, direct path.

TCP SYN came in on wlp1s0, SYN-ACK went out on vmbr0.
Mac Mini never received the SYN-ACK on the expected path — connection reset.

Why ping worked but SSH failed:
  ICMP is stateless — does not care about path symmetry.
  TCP is stateful — SYN and SYN-ACK must flow on the same path for connection
  tracking to work. Asymmetric path breaks the handshake.


# Suspected Root Cause
Asymmetric routing caused by old IP (192.168.0.220) still configured on vmbr0.
Inbound via WiFi, outbound via vmbr0 — TCP handshake breaks.


# More Checks Notes:
Confirmed vmbr0 still had 192.168.0.220 configured — leftover from before
management was migrated to WiFi interface. Two IPs on overlapping subnets,
two possible paths for the same return traffic.


# Suspected Solution
Remove old IP 192.168.0.220 from vmbr0. Single path for all traffic, no
asymmetry.


# Test
Removed IP and route from vmbr0, tested SSH from Mac Mini.

Command:
  ip addr del 192.168.0.220/24 dev vmbr0
  ip route del 192.168.0.0/24 dev vmbr0
  ssh root@10.0.5.110

Result: PASS — SSH connects immediately, no hang.

_____________________________________________________________________

[Final Root Cause]
Old IP (192.168.0.220/24) was still configured on vmbr0 after management was
migrated to WiFi. Proxmox had two paths to 192.168.0.x — via WiFi through ER605,
and via vmbr0 directly. Inbound traffic from Mac Mini arrived via WiFi, but
Proxmox replied via vmbr0 (shorter path, same subnet). TCP SYN and SYN-ACK took
different paths — connection tracking broke, handshake reset. Ping worked because
ICMP is stateless and does not require path symmetry.

_____________________________________________________________________

[Final Solution]
Removed old IP from vmbr0:

  ip addr del 192.168.0.220/24 dev vmbr0
  ip route del 192.168.0.0/24 dev vmbr0

Updated /etc/network/interfaces to remove the config permanently.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: Any service relying on 192.168.0.220 loses connectivity after removal.
Verify nothing is bound to that IP before applying.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key lesson: when migrating management from one interface to another, remove
the old IP completely before or immediately after. Two IPs on overlapping or
related subnets will cause asymmetric routing for TCP connections.

Prevention checklist:
  - Plan interface migration completely before starting
  - Remove old IP from old interface before relying on the new one
  - If keeping both, ensure subnets have no overlap
  - Always test with TCP (SSH, HTTP) not just ping — ping hides asymmetry