#!/bin/bash
#===============================================================================
# Mac Mini - Install persistent route to internal 10.x networks
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE_SCRIPT="/usr/local/bin/add-route.sh"
PLIST_DST="/Library/LaunchDaemons/com.local.route10.plist"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0"
    exit 1
fi

echo "Installing persistent route to 10.0.0.0/8 via 192.168.0.175..."

# Install route script
cp "${SCRIPT_DIR}/add-route.sh" "$ROUTE_SCRIPT"
chmod 755 "$ROUTE_SCRIPT"
echo "Installed: $ROUTE_SCRIPT"

# Install plist
cp "${SCRIPT_DIR}/com.local.route10.plist" "$PLIST_DST"
chown root:wheel "$PLIST_DST"
chmod 644 "$PLIST_DST"
echo "Installed: $PLIST_DST"

# Reload
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

# Wait and verify
sleep 3
echo ""
echo "Route table:"
netstat -rn | grep -E "^10|^default"

echo ""
echo "Done! Reboot to verify persistence."
