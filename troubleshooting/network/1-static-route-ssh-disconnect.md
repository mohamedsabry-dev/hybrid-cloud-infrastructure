# TS-NET-001 | 2026-02-12 | WORKAROUND APPLIED
_____________________________________________________________________

[Info]
Domain: Networking
Sub-techs: Static routes, ISP router, macOS routing
Environment: Home network | ISP router 192.168.0.1 | ER605 192.168.0.175 | Mac Mini 192.168.0.223
Re-opened: No

_____________________________________________________________________

[Issue Description]
SSH connections disconnect after ~30 seconds when routing 10.x traffic through
ER605 via a static route configured on the ISP router.

Goal: allow Mac Mini to reach all internal 10.x networks through ER605.

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked ISP router static route configuration:
  Network destination: 10.0.0.0
  Subnet mask:         255.0.0.0
  Gateway:             192.168.0.175 (ER605 WAN)
  Interface:           LAN

SSH disconnects after ~30 seconds consistently. Same issue was seen in POC-v1.

Tested local static route on Mac Mini instead:

Command:
  sudo route add -net 10.0.0.0/8 192.168.0.175

Output:
  SSH connections stable — no disconnects.


# Suspected Root Cause
Observed behaviour only — not fully investigated.
ISP router static route causes SSH sessions to drop after ~30 seconds.
Same route configured locally on Mac Mini is stable. Possible routing loop
or timing issue on the consumer ISP router, but root cause was not confirmed.
Decision made not to investigate further and move to workaround instead.


# More Checks Notes:
N/A — not investigated further.


# Suspected Solution
Move static route from ISP router to Mac Mini directly and make it persistent.


# Test
Removed ISP router static route, configured local route on Mac Mini, tested SSH.

Result: PASS — SSH stable with local route. Workaround confirmed working.

_____________________________________________________________________

[Final Root Cause]
Not confirmed — not investigated further.
Observed: ISP router static route causes SSH disconnects after ~30 seconds.
Local route on Mac Mini is stable. Root cause not pursued — workaround was
sufficient and internal route was the preferred long-term direction anyway.

_____________________________________________________________________

[Final Solution]
Workaround — configured persistent static route directly on Mac Mini using
LaunchDaemon instead of relying on ISP router static route.

  Files: foundation/mac-mini/
    com.local.route10.plist   LaunchDaemon config
    install-route.sh          installation script

  Install:
    cd foundation/mac-mini
    sudo ./install-route.sh

  Verify after reboot:
    netstat -rn | grep "^10"
    → 10/8  192.168.0.175  UGSc ...

See TS-MAC-002 for full LaunchDaemon setup details.

Verified: Yes (workaround confirmed working, root cause not resolved)

_____________________________________________________________________

[Risk Level] LOW
Note: Must configure on each external device that needs 10.x access.
No central enforcement — per-device setup required.

_____________________________________________________________________

[References]
- poc-v1/troubleshooting/network/08-Static-Route-Loop-SSH-Disconnect.md

_____________________________________________________________________

[Draft Notes]

Root cause remains open. If ISP router static route instability needs to be
understood in the future, investigate:
  - Routing loop between ISP router and ER605
  - ISP router ARP/NAT behaviour when forwarding to ER605 WAN IP
  - Connection tracking timeout settings on ISP router

Long-term direction: route configured at ISP router level pointing to MikroTik
(see TS-MAC-002 update 2026-04) — Mac Mini local route no longer needed.

Workaround (non-persistent):
  sudo route add -net 10.0.0.0/8 192.168.0.175