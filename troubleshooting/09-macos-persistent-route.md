# macOS - Persistent Static Route

## Issue
Routes added via `route add` are lost after Mac reboot.

## Solution
Use the scripts in `workstation/` folder to install a LaunchDaemon.

### Quick Install

```bash
cd workstation
sudo ./install-route.sh
```

This installs:
- `/usr/local/bin/add-route.sh` - Script that adds the route
- `/Library/LaunchDaemons/com.local.route10.plist` - Runs at boot

### What It Does

Adds route: `10.0.0.0/8 → 192.168.0.175`

This single route covers all internal VLANs:
- 10.0.5.x (Management)
- 10.0.50.x (Prod)
- 10.0.53.x (Prod DMZ)
- 10.0.63.x (Dev)
- etc.

### Verify

```bash
netstat -rn | grep "^10"
```

Expected output:
```
10    192.168.0.175    UGSc    en1
```

### Troubleshooting

**Route not added after reboot?**

Check if script exists:
```bash
ls -la /usr/local/bin/add-route.sh
```

If missing, reinstall:
```bash
sudo cp workstation/add-route.sh /usr/local/bin/add-route.sh
sudo chmod 755 /usr/local/bin/add-route.sh
```

**Check daemon status:**
```bash
sudo launchctl list | grep route
```

**Reload daemon:**
```bash
sudo launchctl unload /Library/LaunchDaemons/com.local.route10.plist
sudo launchctl load /Library/LaunchDaemons/com.local.route10.plist
```

**Delete old/wrong routes:**
```bash
sudo route delete -net 10.0.0.0/16 192.168.0.175
sudo route delete -net 10.0.2.0/24 192.168.0.185
```

### Manual Files

**workstation/add-route.sh:**
```bash
#!/bin/bash
GATEWAY="192.168.0.175"
NETWORK="10.0.0.0/8"

for i in {1..60}; do
    if /sbin/ping -c 1 -t 1 "$GATEWAY" &>/dev/null; then
        /sbin/route add -net "$NETWORK" "$GATEWAY" 2>/dev/null
        exit 0
    fi
    sleep 1
done
exit 1
```

**workstation/com.local.route10.plist:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
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
</dict>
</plist>
```

## Date Recorded
2026-02-16 (Updated: 2026-02-20)
