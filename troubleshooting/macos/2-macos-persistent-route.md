# TS-MAC-002 | 2026-02-16 | RESOLVED

## 1. Context
- System: macOS with LaunchDaemon
- Environment: Mac Mini workstation
- Related components: Static routes, internal VLANs access

## 2. Issue
- Symptom: Routes added via `route add` are lost after Mac reboot
- Error:
```bash
# After reboot
netstat -rn | grep "^10"
# Empty - route gone
```

## 3. Analysis

**Check 1: Does the route work when added manually?**
```bash
sudo route add -net 10.0.0.0/8 192.168.0.175
netstat -rn | grep "^10"
# 10    192.168.0.175    UGSc    en1
```
Finding: Route works when added manually.

**Check 2: Why doesn't it persist?**
```
macOS doesn't have /etc/rc.local or systemd
Routes added via `route add` are in-memory only
Reboot clears routing table
```
Finding: macOS needs LaunchDaemon to run commands at boot.

**Check 3: What's the gateway?**
```
192.168.0.175 = ER605 router / WireGuard endpoint
Routes to 10.0.0.0/8 = all internal VLANs
```
Finding: Single route covers all internal networks.

## 4. Root Cause
> macOS `route add` commands are not persistent - they're cleared on reboot. macOS requires a LaunchDaemon to execute commands at system startup.

## 5. Solution
> **Current:** Route configured at ISP router level pointing to ER605 router - no Mac config needed.
> **Alternative:** Create LaunchDaemon to add route at boot (kept for reference).

**Update (2026-04):** The route `10.0.0.0/8` is now configured at the ISP router level. The LaunchDaemon below is no longer needed on Mac Mini but kept for reference or alternative setups.

**Gateway history:**
| Phase | Gateway | Device |
|-------|---------|--------|
| Before MikroTik migration | 192.168.0.175 | ER605 |
| After MikroTik migration | 192.168.100.195 | MikroTik |
| Fallback (kept) | 192.168.0.175 | ER605 (same config retained) |

---

### Alternative: LaunchDaemon Method (Reference)

**Why this works:** LaunchDaemon runs at system startup with root privileges, before user login.

**Location:** Mac workstation

**Files in:** `workstation/route-setup/`

**1. Route script:** `workstation/route-setup/add-route.sh`
```bash
#!/bin/bash
# Wait for network, then add route to 10.x networks

GATEWAY="192.168.100.195"
NETWORK="10.0.0.0/8"

# Wait up to 60 seconds for network
for i in {1..60}; do
    if /sbin/ping -c 1 -t 1 "$GATEWAY" &>/dev/null; then
        /sbin/route add -net "$NETWORK" "$GATEWAY" 2>/dev/null
        logger "Route $NETWORK via $GATEWAY added"
        exit 0
    fi
    sleep 1
done

logger "Failed to add route - gateway $GATEWAY not reachable"
exit 1
```

**2. LaunchDaemon plist:** `workstation/route-setup/com.local.route10.plist`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.local.route10</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/add-route.sh</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
```

**Quick install (if needed):**
```bash
cd workstation/route-setup
sudo ./install-route.sh
```

**Manual install:**
```bash
# Copy script
sudo cp workstation/add-route.sh /usr/local/bin/add-route.sh
sudo chmod 755 /usr/local/bin/add-route.sh

# Copy plist
sudo cp workstation/com.local.route10.plist /Library/LaunchDaemons/
sudo chown root:wheel /Library/LaunchDaemons/com.local.route10.plist
sudo chmod 644 /Library/LaunchDaemons/com.local.route10.plist

# Load daemon
sudo launchctl load /Library/LaunchDaemons/com.local.route10.plist
```

**Verification:**
```bash
netstat -rn | grep "^10"
```
Expected output:
```
10    192.168.0.175    UGSc    en1
```

## 6. Solution Risk
- Risk level: LOW
- Potential impact: If gateway (192.168.0.175) is down, route won't be added (script times out after 60s)

## 7. Impact After Fix
- Observed: Route persists after reboot
- All internal VLANs accessible from Mac
- No new issues caused

**Networks accessible via this route:**
- 10.0.5.x (Management)
- 10.0.50.x (Prod)
- 10.0.53.x (Prod DMZ)
- 10.0.63.x (Dev)
- etc.

## 8. Notes

**Troubleshooting commands:**
```bash
# Check if script exists
ls -la /usr/local/bin/add-route.sh

# Check daemon status
sudo launchctl list | grep route

# Reload daemon
sudo launchctl unload /Library/LaunchDaemons/com.local.route10.plist
sudo launchctl load /Library/LaunchDaemons/com.local.route10.plist

# Delete old/wrong routes
sudo route delete -net 10.0.0.0/16 192.168.0.175
sudo route delete -net 10.0.2.0/24 192.168.0.185
```

**Why the script waits for gateway:**
At boot, network interface might not be ready immediately. The script pings gateway up to 60 times (1 second apart) before adding route. This ensures network is up before adding route.

## 9. Workaround (if any)
> Manually run `sudo route add -net 10.0.0.0/8 192.168.0.175` after each reboot.

## Related Files
- `workstation/route-setup/add-route.sh` - Route script
- `workstation/route-setup/com.local.route10.plist` - LaunchDaemon plist
- `workstation/route-setup/install-route.sh` - Installer script
- `workstation/README.md` - Full workstation setup guide
