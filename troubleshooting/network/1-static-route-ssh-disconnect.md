# TS-NET-001 | 2026-02-12 | RESOLVED

## 1. Context
- System: Network routing / Static routes
- Environment: Home Network (Mac Mini to ER605)
- Related components: ISP router (192.168.0.1), ER605 (192.168.0.175), Mac Mini (192.168.0.223)

## 2. Issue
- Symptom: SSH connections disconnect after ~30 seconds when using ISP router static route
- Error: Connection drops when routing 10.x traffic through ER605 via ISP router static route

**Goal:** Allow Mac Mini to reach all internal 10.x networks through ER605 router.

## 3. Analysis

**Check 1: ISP router static route configuration**
| Setting | Value |
|---------|-------|
| Network Destination | 10.0.0.0 |
| Subnet Mask | 255.0.0.0 |
| Default Gateway | 192.168.0.175 (ER605 WAN) |
| Interface | LAN |

Finding: SSH disconnects after ~30 seconds. Same issue encountered in POC-v1.

**Check 2: Local static route on Mac Mini**
```bash
sudo route add -net 10.0.0.0/8 192.168.0.175
```
Finding: Stable SSH connections when route is configured locally.

## 4. Root Cause
> Consumer-grade ISP routers have routing loop or timing issues with static routes. The ISP router's static route implementation causes connection instability.

## 5. Solution
> Configure static route directly on the Mac Mini instead of the ISP router.

**Persistent Route Setup (survives reboot):**

Scripts Location: `foundation/mac-mini/`
- `com.local.route10.plist` - LaunchDaemon config
- `install-route.sh` - Installation script

**Install Command:**
```bash
cd foundation/mac-mini
sudo ./install-route.sh
```

**Files Installed:**
- `/usr/local/bin/add-route.sh` - Waits for network, adds route
- `/Library/LaunchDaemons/com.local.route10.plist` - Runs at boot

**How it works:** Runs at boot, pings ER605 to warm ARP, adds route

**Verify after reboot:**
```bash
netstat -rn | grep "^10"
# Should show: 10/8  192.168.0.175  UGSc  ...
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: Must configure on each external device that needs 10.x access

## 7. Impact After Fix
- Observed: Stable SSH connections
- No disconnects when accessing internal networks

## 8. Notes
**Key Takeaway:** When ISP router static routes cause connection instability, configure the static route locally on the client device instead.

**Related:** POC-v1 had same issue - `poc-v1/troubleshooting/network/08-Static-Route-Loop-SSH-Disconnect.md`

## 9. Workaround (if any)
> Manual route add: `sudo route add -net 10.0.0.0/8 192.168.0.175` (non-persistent)
