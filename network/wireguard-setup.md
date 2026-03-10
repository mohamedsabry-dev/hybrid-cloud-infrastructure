# WireGuard VPN Setup Guide

## Overview

This guide covers setting up WireGuard VPN between AWS EC2 and on-premises ER605 router for both Dev and Prod environments.

## Architecture

```
                        AWS Dev (172.16.0.0/16)
                              |
Home/Datacenter          WireGuard EC2 Dev
  10.0.x.x                (10.200.0.2)
      |                        |
      |                   UDP 51820
      |                        |
   ER605 ─────────────────────┘
(10.200.0.1 dev)
(10.200.1.1 prod)              |
      |                   UDP 51820
      |                        |
      |                   WireGuard EC2 Prod
      |                    (10.200.1.2)
      |                        |
      └───────────────── AWS Prod (172.17.0.0/16)
```

---

## Environment Summary

| Setting | Dev | Prod |
|---------|-----|------|
| AWS VPC CIDR | 172.16.0.0/16 | 172.17.0.0/16 |
| AWS WireGuard Subnet | 172.16.65.0/24 | 172.17.65.0/24 |
| AWS Tunnel IP | 10.200.0.2/30 | 10.200.1.2/30 |
| AWS Listen Port | 51820 | 51820 |
| ER605 Tunnel IP | 10.200.0.1 | 10.200.1.1 |
| ER605 Listen Port | 51820 | 51821 |
| ER605 Interface Name | dev_tunnel | prod_tunnel |
| State Bucket | ...-tf-state-dev | ...-tf-state-prod |

---

## AWS EC2 WireGuard Setup

### 1. Install Required Packages

```bash
# Update system
sudo dnf update -y

# Install WireGuard
sudo dnf install wireguard-tools -y

# Install monitoring tools
sudo dnf install tcpdump -y
sudo dnf install nmap-ncat -y    # For nc command
sudo dnf install tmux -y          # For persistent sessions
sudo dnf install cronie -y        # For cron jobs

# Start cron service
sudo systemctl enable crond
sudo systemctl start crond
```

### 2. Generate WireGuard Keys

```bash
# Generate private and public keys
wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key

# Secure the private key
sudo chmod 600 /etc/wireguard/private.key

# View your public key (needed for ER605 config)
cat /etc/wireguard/public.key
```

### 3. Create WireGuard Configuration

```bash
sudo nano /etc/wireguard/wg0.conf
```

**Dev Environment Config (`/etc/wireguard/wg0.conf`):**
```ini
[Interface]
Address = 10.200.0.2/30
ListenPort = 51820
PrivateKey = <DEV_AWS_PRIVATE_KEY>

# Enable IP forwarding and NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o enX0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o enX0 -j MASQUERADE

[Peer]
PublicKey = <ER605_DEV_TUNNEL_PUBLIC_KEY>
AllowedIPs = 10.200.0.1/32, 10.0.60.0/24, 10.0.61.0/24, 10.0.62.0/24, 10.0.63.0/24, 10.0.64.0/24, 10.0.65.0/24
# Endpoint not needed - ER605 initiates connection
```

**Prod Environment Config (`/etc/wireguard/wg0.conf`):**
```ini
[Interface]
Address = 10.200.1.2/30
ListenPort = 51820
PrivateKey = <PROD_AWS_PRIVATE_KEY>

# Enable IP forwarding and NAT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o enX0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o enX0 -j MASQUERADE

[Peer]
PublicKey = <ER605_PROD_TUNNEL_PUBLIC_KEY>
AllowedIPs = 10.200.1.1/32, 10.0.60.0/24, 10.0.61.0/24, 10.0.62.0/24, 10.0.63.0/24, 10.0.64.0/24, 10.0.65.0/24
# Endpoint not needed - ER605 initiates connection
```

### 4. Enable IP Forwarding

```bash
# Enable temporarily
sudo sysctl -w net.ipv4.ip_forward=1

# Enable permanently
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

### 5. Start WireGuard

```bash
# Enable and start
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

# Check status
sudo wg show
```

### 6. Verify Network Interface

```bash
# Find your main interface name (enX0, ens5, eth0, etc.)
ip a | grep -E "^[0-9]"

# Update PostUp/PostDown in wg0.conf if interface name differs
```

---

## ER605 WireGuard Configuration

### Dev Tunnel Interface Settings

| Setting | Value |
|---------|-------|
| Name | dev_tunnel |
| MTU | 1400 |
| Listen Port | 51820 |
| Local IP Address | 10.200.0.1 |
| Status | Enable |

### Dev Tunnel Peer Settings

| Setting | Value |
|---------|-------|
| Interface | dev_tunnel |
| Public Key | `<AWS_DEV_PUBLIC_KEY>` |
| Endpoint | `<AWS_DEV_ELASTIC_IP>` |
| Endpoint Port | 51820 |
| Allowed Address | 0.0.0.0/0 |
| Persistent Keepalive | 25 |
| Status | Enable |

---

### Prod Tunnel Interface Settings

| Setting | Value |
|---------|-------|
| Name | prod_tunnel |
| MTU | 1400 |
| Listen Port | 51821 |
| Local IP Address | 10.200.1.1 |
| Status | Enable |

### Prod Tunnel Peer Settings

| Setting | Value |
|---------|-------|
| Interface | prod_tunnel |
| Public Key | `<AWS_PROD_PUBLIC_KEY>` |
| Endpoint | `<AWS_PROD_ELASTIC_IP>` |
| Endpoint Port | 51820 |
| Allowed Address | 0.0.0.0/0 |
| Persistent Keepalive | 25 |
| Status | Enable |

---

### Required Firewall Rules

Create rules on ER605:

| Rule Name | Action | Source Zone | Destination Zone |
|-----------|--------|-------------|------------------|
| vpn_dev | Allow ALL | vpn_dev | DataCenter_Cairo |
| vpn_prod | Allow ALL | vpn_prod | DataCenter_Cairo |

---

## ISP Router Configuration

### Full Cone NAT (Important!)

Change NAT type from "Port-restricted cone NAT" to **"Full cone NAT"** to prevent connection drops.

### Port Forwarding (if AWS initiates)

| Name | External Port | Internal IP | Internal Port | Protocol |
|------|---------------|-------------|---------------|----------|
| WireGuard_Dev | 51820 | 192.168.100.175 | 51820 | UDP |
| WireGuard_Prod | 51821 | 192.168.100.175 | 51821 | UDP |

---

## Keepalive Service (Systemd)

Create a systemd service to keep the tunnel alive after reboot:

```bash
sudo tee /etc/systemd/system/wg-keepalive.service << 'EOF'
[Unit]
Description=WireGuard Tunnel Keepalive Ping
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do ping -c 1 10.0.65.1 > /dev/null 2>&1; sleep 30; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wg-keepalive
sudo systemctl start wg-keepalive
sudo systemctl status wg-keepalive
```

**Note:** For prod, change the ping target to an appropriate VLAN interface (e.g., 10.0.50.1 for prod VLANs).

---

## Monitoring Commands

### Check WireGuard Status

```bash
sudo wg show
```

### Continuous Ping with Timestamps

```bash
nohup bash -c 'ping 10.0.65.1 | while read line; do echo "$(date "+%H:%M:%S") $line"; done' > ~/ping.log 2>&1 &
```

### Monitor Handshakes

```bash
nohup bash -c 'while true; do echo "$(date "+%H:%M:%S") $(sudo wg show wg0 latest-handshakes)"; sleep 30; done' > ~/handshake.log 2>&1 &
```

### Capture WireGuard Traffic

```bash
nohup sudo tcpdump -i enX0 udp port 51820 -n -tt > ~/wg-traffic.log 2>&1 &
```

### Check Logs

```bash
tail -100 ~/ping.log
tail -100 ~/handshake.log
tail -100 ~/wg-traffic.log
```

---

## Troubleshooting

### No Handshake

1. Check keys match on both sides
2. Verify UDP 51820 is allowed in security group
3. Check ER605 endpoint is correct
4. Verify ISP router port forward (if AWS initiates)

### Connection Drops After Time

1. Enable Full Cone NAT on ISP router
2. Lower keepalive to 15 seconds
3. Enable wg-keepalive systemd service

### MTU Issues (Fragmentation)

Test with different packet sizes:
```bash
ping -s 1372 -D 10.0.65.10   # 1400 MTU
ping -s 1172 -D 10.0.65.10   # 1200 MTU
```

Set MTU in ER605 WireGuard interface to working value (recommended: 1400).

### Asymmetric Traffic

If TX >> RX or vice versa:
- Check firewall rules on ER605
- Verify AllowedIPs on both sides
- Check return routes

---

## Security Notes

- Only open UDP 51820 and TCP 22 in AWS security group
- Restrict to your public IP only (use `var.allowed_ip`)
- Internal traffic (ping, SSH to internal hosts) passes through encrypted tunnel
- No need to open ICMP in security group for tunnel traffic

---

## Traffic Flow

```
ER605 (dev_tunnel)                    AWS Dev EC2
  Port 51820        ───────────────►    Port 51820
  10.200.0.1                            10.200.0.2


ER605 (prod_tunnel)                   AWS Prod EC2
  Port 51821        ───────────────►    Port 51820
  10.200.1.1                            10.200.1.2
```

Both AWS instances listen on port 51820 (they have different public IPs).
ER605 uses different local ports (51820/51821) to route to the correct tunnel.
