#!/bin/bash
#
# WireGuard Setup Script for AWS EC2
# Usage: ./setup-wireguard.sh <dev|prod>
#
# IMPORTANT: Tunnel IPs are within AWS VPC range to simplify ER605 routing.
# This allows single AllowedIPs entry on ER605 (VPC CIDR covers tunnel + subnets).
#

set -e

ENV="${1:-}"
if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    echo "Usage: $0 <dev|prod>"
    exit 1
fi

echo "=== WireGuard Setup for $ENV ==="

# Environment config
# NOTE: Tunnel IPs are inside VPC range to solve ER605 AllowedIPs routing issue
if [[ "$ENV" == "dev" ]]; then
    TUNNEL_IP="172.16.200.2/16"
    ER605_TUNNEL_IP="172.16.200.1"
    ALLOWED_IPS="172.16.200.1/32, 10.0.60.0/24, 10.0.61.0/24, 10.0.62.0/24, 10.0.63.0/24, 10.0.64.0/24, 10.0.65.0/24, 10.0.5.0/24"
    KEEPALIVE_TARGET="172.16.200.1"
else
    TUNNEL_IP="172.17.200.2/16"
    ER605_TUNNEL_IP="172.17.200.1"
    ALLOWED_IPS="172.17.200.1/32, 10.0.50.0/24, 10.0.51.0/24, 10.0.52.0/24, 10.0.53.0/24, 10.0.54.0/24, 10.0.55.0/24, 10.0.5.0/24"
    KEEPALIVE_TARGET="172.17.200.1"
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
echo "=========================================="
echo "AWS Public Key (add to ER605 peer config):"
echo "$PUBLIC_KEY"
echo "=========================================="
echo ""
echo "ER605 Peer Settings:"
echo "  - Endpoint: <THIS_EC2_ELASTIC_IP>"
echo "  - Endpoint Port: 51820"
echo "  - AllowedIPs: ${TUNNEL_IP%/*}/16"
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
ExecStart=/bin/bash -c 'while true; do ping -c 1 $KEEPALIVE_TARGET > /dev/null 2>&1; sleep 5; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wg-keepalive

echo ""
echo "=== Setup Complete ==="
echo "AWS Tunnel IP: $TUNNEL_IP"
echo "ER605 Tunnel IP: $ER605_TUNNEL_IP"
echo "AWS Public Key: $PUBLIC_KEY"
echo ""
echo "Verify: sudo wg show"
echo "Test:   ping $KEEPALIVE_TARGET"
