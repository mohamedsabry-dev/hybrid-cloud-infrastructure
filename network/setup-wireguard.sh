#!/bin/bash
#
# WireGuard Setup Script for AWS EC2
# Usage: ./setup-wireguard.sh <dev|prod>
#

set -e

ENV="${1:-}"
if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    echo "Usage: $0 <dev|prod>"
    exit 1
fi

echo "=== WireGuard Setup for $ENV ==="

# Environment config
if [[ "$ENV" == "dev" ]]; then
    TUNNEL_IP="10.200.0.2/30"
    ALLOWED_IPS="10.200.0.1/32, 10.0.60.0/24, 10.0.61.0/24, 10.0.62.0/24, 10.0.63.0/24, 10.0.64.0/24, 10.0.65.0/24, 10.0.5.110/32"
    KEEPALIVE_TARGET="10.0.65.1"
else
    TUNNEL_IP="10.200.1.2/30"
    ALLOWED_IPS="10.200.1.1/32, 10.0.50.0/24, 10.0.51.0/24, 10.0.52.0/24, 10.0.53.0/24, 10.0.54.0/24, 10.0.55.0/24, 10.0.5.100/32"
    KEEPALIVE_TARGET="10.0.55.1"
fi

MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
echo "Detected interface: $MAIN_INTERFACE"

# Generate keys
echo "[1/4] Generating keys..."
sudo mkdir -p /etc/wireguard
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)
echo "$PRIVATE_KEY" | sudo tee /etc/wireguard/private.key > /dev/null
echo "$PUBLIC_KEY" | sudo tee /etc/wireguard/public.key > /dev/null
sudo chmod 600 /etc/wireguard/private.key

echo ""
echo "AWS Public Key (add to ER605):"
echo "$PUBLIC_KEY"
echo ""

# Get ER605 key
echo "[2/4] Enter ER605 ${ENV}_tunnel public key:"
read -r ER605_KEY
if [[ -z "$ER605_KEY" ]]; then
    echo "Error: Key cannot be empty"
    exit 1
fi

# Create config
echo "[3/4] Creating config..."
sudo tee /etc/wireguard/wg0.conf > /dev/null << EOF
[Interface]
Address = $TUNNEL_IP
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE

[Peer]
PublicKey = $ER605_KEY
AllowedIPs = $ALLOWED_IPS
EOF
sudo chmod 600 /etc/wireguard/wg0.conf

# Start services
echo "[4/4] Starting services..."
sudo systemctl enable --now wg-quick@wg0

# Keepalive service
sudo tee /etc/systemd/system/wg-keepalive.service > /dev/null << EOF
[Unit]
Description=WireGuard Tunnel Keepalive Ping
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do ping -c 1 $KEEPALIVE_TARGET > /dev/null 2>&1; sleep 30; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wg-keepalive

echo ""
echo "=== Done ==="
echo "AWS Public Key: $PUBLIC_KEY"
echo "Test: ping $KEEPALIVE_TARGET"
echo "Status: sudo wg show"
