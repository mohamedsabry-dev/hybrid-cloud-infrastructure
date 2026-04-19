#!/bin/bash
#===============================================================================
# Proxmox Network Setup Script
# Usage: ./network-setup.sh <dev|prod>
# Run from console or storage network - NOT over WiFi!
#===============================================================================
# 1. Install wpa_supplicant
# 2. Configure WiFi
# 3. Test WiFi connection
# 4. Configure /etc/network/interfaces
# 5. Update /etc/hosts
# 6. Regenerate SSL certificate
#===============================================================================

set -e

#===============================================================================
# Environment Selection
#===============================================================================
ENV="$1"

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    echo "Usage: $0 <dev|prod>"
    echo "  dev  - Configure development server (pve-dev)"
    echo "  prod - Configure production server (pve-prod)"
    exit 1
fi

#===============================================================================
# Environment-Specific Config
#===============================================================================
if [[ "$ENV" == "dev" ]]; then
    WIFI_INTERFACE="wlp1s0"
    MGMT_IP="10.0.5.110"
    SERVICE_VLANS="60-65"
    STORAGE_IP="10.0.40.110"
    HOSTNAME_SHORT="pve-dev"
else
    WIFI_INTERFACE="wlp4s0"
    MGMT_IP="10.0.5.100"
    SERVICE_VLANS="50-55"
    STORAGE_IP="10.0.40.100"
    HOSTNAME_SHORT="pve-prod"
fi

# Common Config
WIFI_SSID="unified_mgmt"
WIFI_COUNTRY="EG"
MGMT_NETMASK="255.255.255.0"
MGMT_GATEWAY="10.0.5.1"
SERVICE_INTERFACE="svc0"
STORAGE_INTERFACE="stor0"
STORAGE_VLAN="40"
STORAGE_NETMASK="255.255.255.0"
NAS_STORAGE_IP="10.0.40.120"
HOSTNAME_FQDN="${HOSTNAME_SHORT}.lab.local"

#===============================================================================
# Checks
#===============================================================================
if [[ $EUID -ne 0 ]]; then
    echo "Run as root"
    exit 1
fi

echo "==============================================="
echo "Proxmox ${ENV^^} Network Setup"
echo "==============================================="
echo ""
echo "Config:"
echo "  WiFi Interface: ${WIFI_INTERFACE}"
echo "  Management IP:  ${MGMT_IP}"
echo "  Storage IP:     ${STORAGE_IP}"
echo "  Service VLANs:  ${SERVICE_VLANS}"
echo "  Hostname:       ${HOSTNAME_FQDN}"
echo ""

# Get WiFi password
if [[ -z "$WIFI_PASSWORD" ]]; then
    read -s -p "WiFi password: " WIFI_PASSWORD
    echo ""
fi

#===============================================================================
# 1. Install Packages
#===============================================================================
echo ""
echo "[1/6] Installing packages..."
apt update && apt install -y wpasupplicant wireless-tools

#===============================================================================
# 2. Configure WiFi
#===============================================================================
echo ""
echo "[2/6] Creating wpa_supplicant config..."
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

#===============================================================================
# 3. Test WiFi
#===============================================================================
echo ""
echo "[3/6] Testing WiFi..."
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

#===============================================================================
# 4. Configure Network Interfaces
#===============================================================================
echo ""
echo "[4/6] Configuring /etc/network/interfaces..."

echo "Backing up current config..."
cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%Y%m%d%H%M%S)

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

# Service VLAN Trunk (to MikroTik router — previously ER605; see /network/README.md)
auto ${SERVICE_INTERFACE}
iface ${SERVICE_INTERFACE} inet manual

auto vmbr0
iface vmbr0 inet manual
    bridge-ports ${SERVICE_INTERFACE}
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids ${SERVICE_VLANS}

# Storage physical interface (no IP)
auto ${STORAGE_INTERFACE}
iface ${STORAGE_INTERFACE} inet manual

# Storage Bridge (VLAN-aware for VM access to VLAN 40)
auto vmbr1
iface vmbr1 inet manual
    bridge-ports ${STORAGE_INTERFACE}
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
    bridge-vids ${STORAGE_VLAN}

# Proxmox host access to VLAN ${STORAGE_VLAN} (NAS)
auto vmbr1.${STORAGE_VLAN}
iface vmbr1.${STORAGE_VLAN} inet static
    address ${STORAGE_IP}
    netmask ${STORAGE_NETMASK}

source /etc/network/interfaces.d/*
EOF

# Remove old 192.168.0.x config if exists
OLD_IP=$(ip addr show vmbr0 2>/dev/null | grep -oP '192\.168\.0\.\d+/24' | head -1)
if [[ -n "$OLD_IP" ]]; then
    echo "Removing old IP ${OLD_IP} from vmbr0..."
    ip addr del ${OLD_IP} dev vmbr0
    ip route del 192.168.0.0/24 dev vmbr0 2>/dev/null || true
fi

systemctl enable wpa_supplicant

#===============================================================================
# 5. Update /etc/hosts
#===============================================================================
echo ""
echo "[5/6] Updating /etc/hosts..."
sed -i "/\s${HOSTNAME_SHORT}/d" /etc/hosts
echo "${MGMT_IP}  ${HOSTNAME_FQDN} ${HOSTNAME_SHORT}" >> /etc/hosts

#===============================================================================
# 6. Regenerate SSL Certificate
#===============================================================================
echo ""
echo "[6/6] Regenerating Proxmox SSL certificate..."
pvecm updatecerts --force
systemctl restart pveproxy

#===============================================================================
# Complete
#===============================================================================
echo ""
echo "==============================================="
echo "DONE! (${ENV^^})"
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
