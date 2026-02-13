#!/bin/bash
#===============================================================================
# Mac Mini - Install persistent route to internal 10.x networks
#===============================================================================

set -e

PLIST_NAME="com.local.route10.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST_SRC="${SCRIPT_DIR}/${PLIST_NAME}"
PLIST_DST="/Library/LaunchDaemons/${PLIST_NAME}"

if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo: sudo $0"
    exit 1
fi

echo "Installing persistent route to 10.0.0.0/8 via 192.168.0.175..."

# Copy plist
cp "${PLIST_SRC}" "${PLIST_DST}"

# Set permissions
chown root:wheel "${PLIST_DST}"
chmod 644 "${PLIST_DST}"

# Unload if already loaded
launchctl unload "${PLIST_DST}" 2>/dev/null || true

# Load (also runs immediately)
launchctl load "${PLIST_DST}"

# Verify
sleep 1
echo ""
echo "Route table:"
netstat -rn | grep -E "^10 |^default"

echo ""
echo "Done! Route will persist after reboot."
