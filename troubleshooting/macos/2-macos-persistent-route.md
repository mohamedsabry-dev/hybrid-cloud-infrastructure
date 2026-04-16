# TS-MAC-002 | 2026-02-16 | RESOLVED
_____________________________________________________________________

[Info]
Domain: macOS / Networking
Sub-techs: Static routes, LaunchDaemon, macOS boot persistence
Environment: Mac Mini workstation (192.168.0.x home LAN)
Re-opened: No

_____________________________________________________________________

[Issue Description]
Static routes added via route add are lost after Mac reboot. Internal VLANs
(10.0.0.0/8) become unreachable until route is manually re-added.

  After reboot:
  netstat -rn | grep "^10"
  → empty

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Confirmed route works when added manually — not a routing or gateway issue.

Command:
  sudo route add -net 10.0.0.0/8 192.168.0.175
  netstat -rn | grep "^10"

Output:
  10    192.168.0.175    UGSc    en1 — works fine manually.

macOS does not have /etc/rc.local or systemd. Routes added via route add are
in-memory only — reboot clears the routing table. macOS requires a LaunchDaemon
to execute commands at system startup.

Gateway: 192.168.0.175 = ER605 router.
Single route 10.0.0.0/8 covers all internal VLANs (management, prod, dev, etc).


# Suspected Root Cause
macOS route add is not persistent. Routes live in memory only and are cleared
on every reboot. No native persistence mechanism without a LaunchDaemon.


# More Checks Notes:
N/A — cause confirmed, solution direction clear.


# Suspected Solution
Create a LaunchDaemon that runs the route add command at boot with a gateway
reachability check before applying.


# Test
LaunchDaemon installed, Mac rebooted, route verified.

Command:
  netstat -rn | grep "^10"

Result: PASS — route present after reboot.

_____________________________________________________________________

[Final Root Cause]
macOS route add commands are in-memory only. Reboot clears the routing table.
macOS has no /etc/rc.local or systemd — a LaunchDaemon is required to run
commands at system startup with root privileges.

_____________________________________________________________________

[Final Solution]
UPDATE (2026-04): Route 10.0.0.0/8 is now configured at ISP router level pointing
to the MikroTik. LaunchDaemon no longer needed on Mac Mini. Kept below for reference.

Gateway history:
  Before MikroTik migration  → 192.168.0.175   (ER605)
  After MikroTik migration   → 192.168.100.195 (MikroTik)
  Current                    → configured at ISP router level

--- LaunchDaemon method (reference) ---

Script: /usr/local/bin/add-route.sh
  Waits up to 60s for gateway to be reachable (network may not be ready at boot)
  then runs: route add -net 10.0.0.0/8 <GATEWAY>
  Logs result via logger

Plist: /Library/LaunchDaemons/com.local.route10.plist
  RunAtLoad: true
  KeepAlive: false

Install:
  sudo cp add-route.sh /usr/local/bin/add-route.sh
  sudo chmod 755 /usr/local/bin/add-route.sh
  sudo cp com.local.route10.plist /Library/LaunchDaemons/
  sudo chown root:wheel /Library/LaunchDaemons/com.local.route10.plist
  sudo chmod 644 /Library/LaunchDaemons/com.local.route10.plist
  sudo launchctl load /Library/LaunchDaemons/com.local.route10.plist

Or use: sudo ./install-route.sh

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: If gateway is unreachable at boot, script times out after 60s and route
is not added. Manually run sudo route add -net 10.0.0.0/8 <GATEWAY> if needed.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Networks accessible via 10.0.0.0/8 route:
  10.0.5.x   management
  10.0.50.x  prod
  10.0.53.x  prod DMZ
  10.0.63.x  dev
  (and all other internal VLANs)

Troubleshooting commands:
  ls -la /usr/local/bin/add-route.sh          check script exists
  sudo launchctl list | grep route            check daemon status
  sudo launchctl unload /Library/LaunchDaemons/com.local.route10.plist
  sudo launchctl load  /Library/LaunchDaemons/com.local.route10.plist

  sudo route delete -net 10.0.0.0/16 192.168.0.175   remove old wrong routes
  sudo route delete -net 10.0.2.0/24 192.168.0.185

Related files:
  workstation/route-setup/add-route.sh
  workstation/route-setup/com.local.route10.plist
  workstation/route-setup/install-route.sh
  workstation/README.md