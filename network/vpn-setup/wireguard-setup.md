# WireGuard VPN Setup Guide

## Overview

This guide covers setting up WireGuard VPN between AWS EC2 and on-premises ER605 router for both Dev and Prod environments.

## Architecture

```
                        AWS Dev (172.16.0.0/16)
                              |
Home/Datacenter          WireGuard EC2 Dev
  10.0.x.x               (172.16.200.2)
      |                        |
      |                   UDP 51820
      |                        |
   ER605 ─────────────────────┘
(172.16.200.1 dev)
(172.17.200.1 prod)            |
      |                   UDP 51820
      |                        |
      |                   WireGuard EC2 Prod
      |                   (172.17.200.2)
      |                        |
      └───────────────── AWS Prod (172.17.0.0/16)
```

---

## Environment Summary

| Setting | Dev | Prod |
|---------|-----|------|
| **Hostname** | **wg-dev** | **wg-prod** |
| AWS VPC CIDR | 172.16.0.0/16 | 172.17.0.0/16 |
| AWS WireGuard Subnet | 172.16.65.0/24 | 172.17.65.0/24 |
| **AWS Tunnel IP** | **172.16.200.2/16** | **172.17.200.2/16** |
| AWS Listen Port | 51820 | 51820 |
| **ER605 Tunnel IP** | **172.16.200.1** | **172.17.200.1** |
| ER605 Listen Port | 51820 | 51821 |
| ER605 Interface Name | dev_tunnel | prod_tunnel |
| ER605 Peer AllowedIPs | 172.16.0.0/16 | 172.17.0.0/16 |
| On-Prem VLANs | 10.0.60-65.0/24 | 10.0.50-55.0/24 |

> **IMPORTANT**: Tunnel IPs are within the AWS VPC range. See [Routing Issue & Solution](#routing-issue--solution) for why.

---

## AWS EC2 WireGuard Setup

### SSH Config (Recommended)

Add to `~/.ssh/config` for easy access:

```
Host wg-dev
    HostName REDACTED_EIP_DEV
    User ec2-user
    IdentityFile ~/WorkSpace/vpn-key-pair-dev.pem

Host wg-prod
    HostName REDACTED_EIP_PROD
    User ec2-user
    IdentityFile ~/WorkSpace/vpn-key-pair-prod.pem
```

Optional `/etc/hosts` entries:
```
REDACTED_EIP_DEV  wg-dev
REDACTED_EIP_PROD   wg-prod
```

Then connect with:
```bash
ssh wg-dev
ssh wg-prod
```

### Quick Setup (Recommended)

```bash
# Copy script to EC2
scp network/setup-wireguard.sh wg-dev:~/   # or wg-prod

# SSH and run
ssh wg-dev   # or wg-prod
chmod +x setup-wireguard.sh
./setup-wireguard.sh dev   # or prod
```

### Manual Setup

#### 1. Install Required Packages

```bash
sudo dnf update -y
sudo dnf install wireguard-tools tcpdump nmap-ncat cronie iptables -y
sudo systemctl enable crond
sudo systemctl start crond
```

#### 2. Generate WireGuard Keys

```bash
wg genkey | sudo tee /etc/wireguard/private.key | wg pubkey | sudo tee /etc/wireguard/public.key
sudo chmod 600 /etc/wireguard/private.key
cat /etc/wireguard/public.key
```

#### 3. Create WireGuard Configuration

**Dev Environment (`/etc/wireguard/wg0.conf`):**
```ini
[Interface]
Address = 172.16.200.2/16
ListenPort = 51820
PrivateKey = <AWS_PRIVATE_KEY>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o enX0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o enX0 -j MASQUERADE

[Peer]
PublicKey = <ER605_DEV_TUNNEL_PUBLIC_KEY>
AllowedIPs = 172.16.200.1/32, 10.0.60.0/24, 10.0.61.0/24, 10.0.62.0/24, 10.0.63.0/24, 10.0.64.0/24, 10.0.65.0/24, 10.0.5.0/24
```

**Prod Environment (`/etc/wireguard/wg0.conf`):**
```ini
[Interface]
Address = 172.17.200.2/16
ListenPort = 51820
PrivateKey = <AWS_PRIVATE_KEY>
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o enX0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o enX0 -j MASQUERADE

[Peer]
PublicKey = <ER605_PROD_TUNNEL_PUBLIC_KEY>
AllowedIPs = 172.17.200.1/32, 10.0.50.0/24, 10.0.51.0/24, 10.0.52.0/24, 10.0.53.0/24, 10.0.54.0/24, 10.0.55.0/24, 10.0.5.0/24
```

#### 4. Enable IP Forwarding

```bash
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
```

#### 5. Start WireGuard

```bash
sudo systemctl enable --now wg-quick@wg0
sudo wg show
```

#### 6. Restart WireGuard (after config changes)

```bash
sudo systemctl restart wg-quick@wg0
sudo wg show
```

---

## ER605 Configuration

### IP Addresses

| ID | Name | Type | Address |
|----|------|------|---------|
| 22 | AWS_DEV_Subnet | IP Address/Mask | 172.16.0.0/16 |
| 23 | AWS_PROD_Subnet | IP Address/Mask | 172.17.0.0/16 |

### IP Groups

| ID | Group Name | Address Name | Description |
|----|------------|--------------|-------------|
| 12 | vpn_prod | vpn_AWS_PROD_Subnet | --- |
| 13 | vpn_dev | vpn_AWS_DEV_Subnet | --- |

### Access Control List (ACL)

| ID | Name | Policy | Service Type | Direction | Source | Destination |
|----|------|--------|--------------|-----------|--------|-------------|
| 7 | vpn_dev | Allow | ALL | ALL | vpn_dev | Development_Env |
| 8 | vpn_prod | Allow | ALL | ALL | vpn_prod | Production_Env |

> **Note**: VPN traffic is segmented - Dev VPN only reaches Dev VLANs (60-65), Prod VPN only reaches Prod VLANs (50-55).

---

### WireGuard Interfaces

| ID | Name | MTU | Listen Port | Local IP | Status |
|----|------|-----|-------------|----------|--------|
| 1 | dev_tunnel | 1372 | 51820 | 172.16.200.1 | Enabled |
| 2 | prod_tunnel | 1372 | 51821 | 172.17.200.1 | Enabled |

#### Dev Tunnel Interface Settings

| Setting | Value |
|---------|-------|
| Name | dev_tunnel |
| MTU | 1372 |
| Listen Port | 51820 |
| Private Key | `<HIDDEN>` |
| Public Key | `<ER605_DEV_PUBLIC_KEY>` |
| Local IP Address | 172.16.200.1 |
| Status | Enable |

#### Prod Tunnel Interface Settings

| Setting | Value |
|---------|-------|
| Name | prod_tunnel |
| MTU | 1372 |
| Listen Port | 51821 |
| Private Key | `<HIDDEN>` |
| Public Key | `<ER605_PROD_PUBLIC_KEY>` |
| Local IP Address | 172.17.200.1 |
| Status | Enable |

---

### WireGuard Peers

| Interface | Endpoint | Endpoint Port | Allowed Address | Persistent Keepalive | Status |
|-----------|----------|---------------|-----------------|---------------------|--------|
| dev_tunnel | `<AWS_DEV_EIP>` | 51820 | 172.16.0.0/16 | 25 | Enabled |
| prod_tunnel | `<AWS_PROD_EIP>` | 51820 | 172.17.0.0/16 | 25 | Enabled |

#### Dev Tunnel Peer Settings

| Setting | Value |
|---------|-------|
| Interface | dev_tunnel |
| Public Key | `<AWS_DEV_PUBLIC_KEY>` |
| Endpoint | `<AWS_DEV_ELASTIC_IP>` |
| Endpoint Port | 51820 |
| **Allowed Address** | **172.16.0.0/16** |
| Preshared Key | (Optional) |
| Persistent Keepalive | 25 |
| Status | Enable |

#### Prod Tunnel Peer Settings

| Setting | Value |
|---------|-------|
| Interface | prod_tunnel |
| Public Key | `<AWS_PROD_PUBLIC_KEY>` |
| Endpoint | `<AWS_PROD_ELASTIC_IP>` |
| Endpoint Port | 51820 |
| **Allowed Address** | **172.17.0.0/16** |
| Preshared Key | (Optional) |
| Persistent Keepalive | 25 |
| Status | Enable |

---

## Routing Issue & Solution

### The Problem

ER605's WireGuard AllowedIPs field only accepts ONE entry. This caused routing issues:

| AllowedIPs Setting | Result |
|--------------------|--------|
| `10.200.x.0/24` (tunnel only) | VPN→Internal works, Internal→VPN fails |
| `172.x.0.0/16` (VPC only) | Internal→VPN works, VPN→Internal fails |
| `0.0.0.0/0` (any) | Routes ALL traffic through ONE tunnel (wrong tunnel selected) |

**Symptom**: Traffic to prod AWS (172.17.x.x) was routed through dev tunnel (10.200.0.2):
```
$ traceroute 172.17.65.73
1  _gateway (10.0.53.1)
2  10.200.0.2          <-- WRONG! Should be prod tunnel
```

### The Solution

**Place tunnel IPs inside the AWS VPC CIDR range.**

| Environment | Old Tunnel IPs | New Tunnel IPs |
|-------------|----------------|----------------|
| Dev | 10.200.0.1/2 | 172.16.200.1/2 |
| Prod | 10.200.1.1/2 | 172.17.200.1/2 |

Now **one AllowedIPs entry covers both tunnel AND VPC traffic**:
- Dev peer: `172.16.0.0/16` covers tunnel (172.16.200.x) + VPC (172.16.x.x)
- Prod peer: `172.17.0.0/16` covers tunnel (172.17.200.x) + VPC (172.17.x.x)

**No static routes needed** - WireGuard handles routing automatically based on AllowedIPs.

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

The setup script creates this automatically. Manual creation:

```bash
sudo tee /etc/systemd/system/wg-keepalive.service << 'EOF'
[Unit]
Description=WireGuard Tunnel Keepalive Ping
After=network.target wg-quick@wg0.service
Wants=wg-quick@wg0.service

[Service]
Type=simple
User=root
ExecStart=/bin/bash -c 'while true; do ping -c 1 <KEEPALIVE_TARGET> > /dev/null 2>&1; sleep 5; done'
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now wg-keepalive
```

**Keepalive Targets:**
- Dev: `172.16.200.1` (ER605 tunnel IP)
- Prod: `172.17.200.1` (ER605 tunnel IP)

---

## Monitoring Commands

```bash
# WireGuard status
sudo wg show

# Restart WireGuard
sudo systemctl restart wg-quick@wg0

# Check keepalive service
sudo systemctl status wg-keepalive

# Continuous ping with timestamps
ping 172.16.200.1 | while read line; do echo "$(date "+%H:%M:%S") $line"; done

# Monitor handshakes
watch -n 30 'sudo wg show wg0 latest-handshakes'

# Capture WireGuard traffic
sudo tcpdump -i enX0 udp port 51820 -n
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
2. Lower keepalive to 5 seconds
3. Enable wg-keepalive systemd service

### Traffic Goes Through Wrong Tunnel

**Symptom**: traceroute shows traffic using wrong tunnel IP (e.g., dev tunnel for prod traffic)

**Cause**: ER605 AllowedIPs misconfigured or tunnel IPs not in VPC range

**Solution**: Ensure tunnel IPs are within VPC CIDR:
- Dev: 172.16.200.x (within 172.16.0.0/16)
- Prod: 172.17.200.x (within 172.17.0.0/16)

### MTU Issues (Fragmentation)

Test with different packet sizes:
```bash
ping -s 1332 -M do 172.16.200.1   # 1372 MTU
ping -s 1172 -M do 172.16.200.1   # 1200 MTU
```

Set MTU in ER605 WireGuard interface to working value (current: 1372).

---

## Traffic Flow

```
ER605 (dev_tunnel)                    AWS Dev EC2
  Port 51820        ───────────────►    Port 51820
  172.16.200.1                          172.16.200.2


ER605 (prod_tunnel)                   AWS Prod EC2
  Port 51821        ───────────────►    Port 51820
  172.17.200.1                          172.17.200.2
```

Both AWS instances listen on port 51820 (they have different public IPs).
ER605 uses different local ports (51820/51821) to route to the correct tunnel.

---

## Security Notes

- Only open UDP 51820 and TCP 22 in AWS security group
- Restrict to your public IP only (use `var.allowed_ip` in Terraform)
- Internal traffic passes through encrypted tunnel
- All public IPs and keys are stored securely, not in documentation
