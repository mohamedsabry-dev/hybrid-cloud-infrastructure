# TS-MAC-001 | 2026-02-04 | RESOLVED
_____________________________________________________________________

[Info]
Domain: macOS
Sub-techs: macOS Local Network privacy permission, GitHub Actions runner, VS Code
Environment: Mac Mini (192.168.0.x) on home LAN
Re-opened: No

_____________________________________________________________________

[Issue Description]
Some apps can reach local network devices, others cannot — on the same machine.

  Terminal.app  → ping 192.168.0.x works
  Safari        → Proxmox web UI (port 8006) loads fine
  Chrome        → unreachable address
  VS Code       → no route to host
  GitHub runner → unreachable

_____________________________________________________________________

[Analysis]

# Initial Check Notes:
Checked routing and firewall first since the symptom looked like a network issue.

Command:
  ping 192.168.0.x  (from Terminal.app)
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

Output:
  ping works — not a routing issue.
  Firewall not blocking — Safari reaches the same host fine.

Noticed the pattern in what works vs what does not:
  Works:       Terminal.app (Apple), Safari (Apple)
  Fails:       Chrome, VS Code, Node.js / GitHub runner

All failing apps are third-party. All working apps are native Apple.

Checked macOS Local Network privacy permissions:

Command:
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"

Output:
  Chrome, VS Code, Node.js — all toggled OFF.
  macOS requires explicit permission for third-party apps to access local network.
  Native Apple apps are automatically allowed.


# Suspected Root Cause
macOS Local Network privacy permission (introduced in Monterey). Third-party apps
require explicit user consent to access local network devices. Native apps like
Terminal.app and Safari are automatically allowed. Chrome, VS Code, and Node.js
were not enabled.


# More Checks Notes:
N/A — cause confirmed from privacy settings.


# Suspected Solution
Enable Local Network permission for Chrome, VS Code, and Node.js in System Settings.


# Test
Enabled permissions for all three apps, restarted them, tested connectivity.

Command:
  ping 192.168.0.x  (from VS Code terminal)

Result: PASS — all apps can reach local network devices.

_____________________________________________________________________

[Final Root Cause]
macOS Local Network privacy permission was not granted to third-party apps.
macOS Monterey+ requires explicit user consent for any third-party app to access
local network devices. Native Apple apps (Terminal.app, Safari) are automatically
allowed. Chrome, VS Code, and Node.js (GitHub Actions runner) were not enabled —
all local network connections from these apps were silently blocked.

_____________________________________________________________________

[Final Solution]
Enabled Local Network permission for affected apps:

  System Settings → Privacy & Security → Local Network
  Toggle ON: Google Chrome, Visual Studio Code, Node.js

  Quick access:
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"

  Restart affected apps after enabling.

Verified: Yes

_____________________________________________________________________

[Risk Level] LOW
Note: No impact — enabling expected network access for development tools.

_____________________________________________________________________

[References]
-
-

_____________________________________________________________________

[Draft Notes]

Key lesson: On macOS, when some apps reach a local device but others cannot,
check Local Network permissions before investigating firewall or routing.

Apps that commonly need this permission:
  Google Chrome, Visual Studio Code, Node.js, Docker Desktop,
  third-party terminal emulators (iTerm2, Hyper, etc.)