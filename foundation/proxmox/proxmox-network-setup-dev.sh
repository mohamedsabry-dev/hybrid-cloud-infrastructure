#!/bin/bash
#===============================================================================
# Proxmox DEV Server Network Setup
# Run from console or storage network - NOT over WiFi!
#===============================================================================

set -e

#===============================================================================
# HARDCODED CONFIG
#===============================================================================
SERVER_TYPE="dev"
WIFI_INTERFACE="wlp1s0"
WIFI_SSID="unified_mgmt"
WIFI_COUNTRY="EG"
MGMT_IP="10.0.5.110"
MGMT_NETMASK="255.255.255.0"
MGMT_GATEWAY="10.0.5.1"
SERVICE_INTERFACE="svc0"
SERVICE_VLANS="60-65"
STORAGE_INTERFACE="stor0"
STORAGE_IP="10.0.40.110"
STORAGE_NETMASK="255.255.255.0"
NAS_STORAGE_IP="10.0.40.120"

#===============================================================================
# CHECKS
#===============================================================================

if [[ $EUID -ne 0 ]]; then
    echo "Run as root"
    exit 1
fi

echo "==============================================="
echo "Proxmox ${SERVER_TYPE} Network Setup"
echo "==============================================="
echo ""

# Get WiFi password
if [[ -z "$WIFI_PASSWORD" ]]; then
    read -s -p "WiFi password: " WIFI_PASSWORD
    echo ""
fi

#===============================================================================
# INSTALL & CONFIGURE
#===============================================================================

echo "Installing packages..."
apt update && apt install -y wpasupplicant wireless-tools

echo "Creating wpa_supplicant config..."
cat > /etc/wpa_supplicant/wpa_supplicant-${WIFI_INTERFACE}.conf << EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=${WIFI_COUNTRY}

network={
    ssid="${WIFI_SSID}"
    psk="${WIFI_PASSWORD}"
    key_mgmt=WPA-PSK
}
EOF
chmod 600 /etc/wpa_supplicant/wpa_supplicant-${WIFI_INTERFACE}.conf

echo "Testing WiFi..."
killall wpa_supplicant 2>/dev/null || true
wpa_supplicant -B -i ${WIFI_INTERFACE} -c /etc/wpa_supplicant/wpa_supplicant-${WIFI_INTERFACE}.conf
ip link set ${WIFI_INTERFACE} up
sleep 3
ip addr add ${MGMT_IP}/24 dev ${WIFI_INTERFACE} 2>/dev/null || true
ip route add default via ${MGMT_GATEWAY} dev ${WIFI_INTERFACE} 2>/dev/null || true

if ! ping -c 3 ${MGMT_GATEWAY}; then
    echo "WiFi test FAILED!"
    exit 1
fi
echo "WiFi OK!"

echo "Backing up /etc/network/interfaces..."
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d%H%M%S)

echo "Writing /etc/network/interfaces..."
cat > /etc/network/interfaces << EOF
auto lo
iface lo inet loopback

# WiFi Management (VLAN 5)
auto ${WIFI_INTERFACE}
iface ${WIFI_INTERFACE} inet static
    address ${MGMT_IP}
    netmask ${MGMT_NETMASK}
    gateway ${MGMT_GATEWAY}
    wpa-conf /etc/wpa_supplicant/wpa_supplicant-${WIFI_INTERFACE}.conf

# Service VLAN Trunk (to ER605)
auto ${SERVICE_INTERFACE}
iface ${SERVICE_INTERFACE} inet manual

auto vmbr0
iface vmbr0 inet manual
    bridge-ports ${SERVICE_INTERFACE}
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids ${SERVICE_VLANS}

# Storage (VLAN 40 - isolated)
auto ${STORAGE_INTERFACE}
iface ${STORAGE_INTERFACE} inet static
    address ${STORAGE_IP}
    netmask ${STORAGE_NETMASK}

source /etc/network/interfaces.d/*
EOF

# Remove old 192.168.0.x config
OLD_IP=$(ip addr show vmbr0 2>/dev/null | grep -oP '192\.168\.0\.\d+/24' | head -1)
if [[ -n "$OLD_IP" ]]; then
    echo "Removing old IP ${OLD_IP} from vmbr0..."
    ip addr del ${OLD_IP} dev vmbr0
    ip route del 192.168.0.0/24 dev vmbr0 2>/dev/null || true
fi

systemctl enable wpa_supplicant

echo ""
echo "==============================================="
echo "DONE!"
echo "==============================================="
echo ""
echo "Current network state:"
ip addr
echo ""
echo "After reboot verify:"
echo "  ping ${MGMT_GATEWAY}"
echo "  ping ${NAS_STORAGE_IP}"
echo "  bridge vlan show"
echo ""
read -p "Reboot now? (y/n): " -n 1 -r
echo ""
[[ $REPLY =~ ^[Yy]$ ]] && reboot
