# TS-MAC-001 | 2026-02-04 | RESOLVED

## 1. Context
- System: macOS Monterey+
- Environment: Mac Mini (192.168.0.##) on home LAN
- Related components: GitHub local runner, VS Code, Chrome, Proxmox access

## 2. Issue
- Symptom: Some apps can reach local network devices, others cannot
- Error:

| Application | Behavior |
|-------------|----------|
| Native Terminal.app | ping to 192.168.0.## works |
| Safari | Proxmox web UI (port 8006) loads fine |
| Google Chrome | "unreachable address" |
| VS Code terminal | "no route to host" |
| GitHub Actions runner | "unreachable" |

## 3. Analysis

**Check 1: Is it a routing issue?**
```bash
# Terminal works fine
ping 192.168.0.XX
# Success
```
Finding: Not a routing issue - Terminal can reach the host.

**Check 2: Is it a firewall issue?**
```bash
# Check macOS firewall
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate
```
Finding: Firewall not blocking - Safari works fine to same host.

**Check 3: What's different between working and non-working apps?**

| Works | Doesn't Work |
|-------|--------------|
| Terminal.app (Apple) | Chrome (third-party) |
| Safari (Apple) | VS Code (third-party) |
| | Node.js/runner (third-party) |

Finding: Native Apple apps work, third-party apps don't.

**Check 4: macOS Local Network permission**
```bash
# Open Local Network permissions
open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
```
Finding: Chrome, VS Code, Node.js not enabled for Local Network access.

## 4. Root Cause
> macOS "Local Network" privacy permission (introduced in macOS Monterey). Third-party apps require explicit permission to access local network devices. Native system apps (Terminal.app, Safari) are automatically allowed, but apps like Chrome, VS Code, and Node.js are not.

## 5. Solution
> Enable Local Network permission for affected apps.

**Why this works:** macOS privacy model requires explicit user consent for third-party apps to access local network.

**Location:** macOS System Settings

**Steps:**
1. Open **System Settings > Privacy & Security > Local Network**
2. Enable (toggle ON) the following apps:
   - Google Chrome
   - Visual Studio Code
   - Node.js (covers GitHub Actions runner)
3. Restart affected apps/services to pick up the new permissions

**Quick access:**
```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork"
```

**Verification:**
```bash
# Test from VS Code terminal or Chrome
ping 192.168.0.XX
# Should work now
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: None - just enabling expected network access

## 7. Impact After Fix
- Observed: All apps can reach local network devices
- GitHub runner can connect to Proxmox
- No new issues caused

## 8. Notes
**Key takeaway:** When some apps can reach a local device but others cannot on macOS, check Local Network permissions first before investigating firewall or routing issues.

**Apps that commonly need this permission:**
- Google Chrome
- Visual Studio Code
- Node.js (GitHub Actions runner)
- Docker Desktop
- Terminal emulators (iTerm2, Hyper, etc.)

## 9. Workaround (if any)
> Use Terminal.app or Safari for tasks that need local network access until permissions are granted.
