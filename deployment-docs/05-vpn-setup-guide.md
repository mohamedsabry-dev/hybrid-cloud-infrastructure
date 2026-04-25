# VPN (WireGuard) - Setup Guide

Note: If you face issues during deployment, check the troubleshooting/ folder
for the related technology section. Most common issues have been documented there.
Relevant folders: troubleshooting/network/ (Cases 4-5: WireGuard CGNAT and stability)

For more details, see: network/vpn/wireguard-setup-guide.txt

---

## Overview

This guide covers the WireGuard VPN setup connecting on-premises infrastructure
to AWS VPCs for both Dev and Prod environments.

IMPORTANT: VPN setup requires AWS Network deployed first, as the EC2 instance
needs the VPC, subnets, and route tables.

---

## Architecture

```
Home/Datacenter (10.0.x.x)
        |
   MikroTik Router
   (172.16.200.1 dev)
   (172.17.200.1 prod)
        |
        +-------- WireGuard (UDP 51820) ------> AWS Dev EC2 (172.16.200.2)
        |                                            |
        |                                       AWS Dev VPC
        |                                       172.16.0.0/16
        |
        +-------- WireGuard (UDP 51830) ------> AWS Prod EC2 (172.17.200.2)
                                                     |
                                                AWS Prod VPC
                                                172.17.0.0/16
```

---

## Tunnel Summary

| Environment | MikroTik Tunnel IP | AWS Tunnel IP   | MikroTik Port | AWS Port |
|-------------|-------------------|-----------------|---------------|----------|
| Dev         | 172.16.200.1      | 172.16.200.2    | 51820         | 51820    |
| Prod        | 172.17.200.1      | 172.17.200.2    | 51830         | 51820    |

Note on prod's listen port: dev and prod both originally used 51820 on the
on-prem side. Prod was moved to 51830 after the ISP CGNAT started silently
dropping return traffic on 51820 for the prod tunnel — see TS-NET-004 in
troubleshooting/network/. AWS side stays on 51820 for both envs; it
responds to whatever source port the packet arrived from.

IMPORTANT: Tunnel IPs are deliberately placed within each AWS VPC CIDR so
one AllowedIPs entry covers both tunnel and VPC. Full reasoning (including
why this pattern emerged from an ER605 single-CIDR-per-peer limitation and
was kept on MikroTik for continuity) is in network/vpn/wireguard-setup-guide.txt
under "Why tunnel IPs live inside the VPC CIDR".

---

## Prerequisites

### AWS Network

AWS Network must be deployed before Compute:

Terraform Path: terraform/dev/aws/network/
GitHub Workflow: .github/workflows/dev-aws-network.yml

Creates: VPC, Internet Gateway, VPN Subnet, Management Subnet, Route Tables

### GitHub Secrets Required

| Secret              | Purpose                                    |
|---------------------|--------------------------------------------|
| HOME_PUBLIC_IP      | Your home public IP for AWS security group |
| VPN_PUBLIC_KEY_DEV  | SSH public key for Dev VPN EC2 access      |
| VPN_PUBLIC_KEY_PROD | SSH public key for Prod VPN EC2 access     |

Note: the AWS Elastic IPs for the VPN EC2 instances are NOT stored in
GitHub Secrets. They are created by Terraform and surfaced via Terraform
output / AWS console. Reference them via SSH config (see Phase 3.4 below).

---

## Phase 1: Deploy AWS Network

### 1.1 Terraform Configuration

Path: terraform/dev/aws/network/

Creates:
- VPC with CIDR 172.16.0.0/16 (dev) or 172.17.0.0/16 (prod)
- Internet Gateway
- VPN Subnet (172.16.65.0/24 or 172.17.65.0/24)
- Management Subnet
- Route Tables with default route to IGW

### 1.2 Run Workflow

Workflow: .github/workflows/dev-aws-network.yml

Triggers: Push to dev branch (terraform/dev/aws/network/**)

Actions:
- OIDC authentication to AWS
- Terraform init, plan, apply
- 3-minute review window before apply

---

## Phase 2: Deploy AWS Compute (WireGuard EC2)

### 2.1 Terraform Configuration

Path: terraform/dev/aws/compute/

Creates:
- Security Group (UDP 51820 for WireGuard, TCP 22 for SSH)
- EC2 Instance (Amazon Linux 2023, t3.micro)
- Elastic IP attachment
- Route for home subnets through WireGuard instance

### 2.2 EC2 Userdata

The EC2 userdata installs:
- wireguard-tools
- tcpdump, nmap-ncat (debugging)
- cronie, iptables
- Enables IP forwarding (net.ipv4.ip_forward=1)

### 2.3 Run Workflow

Workflow: .github/workflows/dev-aws-compute.yml

Triggers: Push to dev branch (terraform/dev/aws/compute/**)

Variables passed:
- allowed_ip: HOME_PUBLIC_IP (restricts SSH/WG access)
- vpn_public_key: VPN_PUBLIC_KEY_DEV (SSH key)

### 2.4 Post-Deployment Guide

After workflow completes, follow the printed guide to configure WireGuard.

---

## Phase 3: Configure WireGuard on EC2

### 3.1 Copy Setup Script

  scp network/vpn/setup-wireguard.sh wg-dev:~/
  # or for prod: scp network/vpn/setup-wireguard.sh wg-prod:~/

### 3.2 Run Setup Script

  ssh wg-dev   # or wg-prod
  chmod +x setup-wireguard.sh
  ./setup-wireguard.sh dev   # or prod

### 3.3 What setup-wireguard.sh Does

- Sets hostname (wg-dev or wg-prod)
- Generates WireGuard key pair
- Displays AWS public key (copy this for MikroTik peer config)
- Prompts for MikroTik public key
- Creates /etc/wireguard/wg0.conf with:
  - Interface: Tunnel IP, Listen Port, Private Key
  - PostUp: iptables forwarding + NAT masquerade
  - Peer: MikroTik public key, AllowedIPs (on-prem subnets)
- Starts wg-quick@wg0 service
- Creates wg-keepalive service (continuous ping)

For script details, see: network/vpn/setup-wireguard.sh

### 3.4 SSH Config (Recommended)

Add to ~/.ssh/config for easy access to VPN EC2 instances:

  Host wg-dev
      HostName <DEV_ELASTIC_IP>
      User ec2-user
      IdentityFile ~/WorkSpace/vpn-key-pair-dev.pem

  Host wg-prod
      HostName <PROD_ELASTIC_IP>
      User ec2-user
      IdentityFile ~/WorkSpace/vpn-key-pair-prod.pem

Then connect with: ssh wg-dev or ssh wg-prod

Template available at: workstation/ssh-wg/ssh-config-template

---

## Phase 4: Configure MikroTik WireGuard

### 4.1 Create WireGuard Interfaces

  /interface wireguard
  add comment="Dev AWS tunnel"  listen-port=51820 mtu=1420 name=dev-tunnel
  add comment="Prod AWS tunnel" listen-port=51830 mtu=1420 name=prod-tunnel

### 4.2 Assign Tunnel IPs

  /ip address
  add address=172.16.200.1/16 interface=dev-tunnel network=172.16.0.0
  add address=172.17.200.1/16 interface=prod-tunnel network=172.17.0.0

### 4.3 Configure Peers

  /interface wireguard peers
  add allowed-address=172.16.0.0/16 comment="AWS Dev" \
      endpoint-address=<AWS_DEV_EIP> endpoint-port=51820 \
      interface=dev-tunnel persistent-keepalive=10s \
      public-key="<AWS_DEV_PUBLIC_KEY>"

  add allowed-address=172.17.0.0/16 comment="AWS Prod" \
      endpoint-address=<AWS_PROD_EIP> endpoint-port=51820 \
      interface=prod-tunnel persistent-keepalive=10s \
      public-key="<AWS_PROD_PUBLIC_KEY>"

### 4.4 Add Routes

  /ip route
  add comment="AWS Dev VPC" dst-address=172.16.0.0/16 gateway=dev-tunnel
  add comment="AWS Prod VPC" dst-address=172.17.0.0/16 gateway=prod-tunnel

### 4.5 Firewall Rules

  /ip firewall filter
  add action=accept chain=input comment="WireGuard Dev"  dst-port=51820 \
      in-interface=ether1 protocol=udp
  add action=accept chain=input comment="WireGuard Prod" dst-port=51830 \
      in-interface=ether1 protocol=udp

For full config reference, see: network/router/mikrotik/backups/backup-config-stable.rsc

---

## Keepalive Service (Why Continuous Ping?)

### Problem: ISP NAT Timeout

ISP routers (especially with CGNAT) drop UDP mappings after idle periods (~60 min).
This causes WireGuard handshakes to fail after timeout.

### Solution: wg-keepalive Service

The setup script creates a systemd service that pings the tunnel peer every 5 seconds:

  [Service]
  ExecStart=/bin/bash -c 'while true; do ping -c 1 <TUNNEL_PEER> > /dev/null 2>&1; sleep 5; done'
  Restart=always

Keepalive Targets:
- Dev EC2: ping 172.16.200.1 (MikroTik dev tunnel IP)
- Prod EC2: ping 172.17.200.1 (MikroTik prod tunnel IP)

### Additional Protections

- MikroTik peers have persistent-keepalive=10s
- Full Cone NAT recommended on ISP router (if configurable)

See TS-NET-005 (troubleshooting/network/5-wireguard-tunnel-stability-investigation.md)
for NAT timeout and tunnel stability details.

---

## ISP/CGNAT Port Blocking

### Symptoms

- One tunnel works (dev on 51820), the other doesn't
- AWS tcpdump shows bidirectional packets
- MikroTik shows TX bytes increasing but RX: 0 B
- No handshake established

### How to identify CGNAT

Check ISP router routing table for addresses in 100.64.0.0/10 range.

### Solution

Change the on-prem listen port to a port the ISP isn't blocking:
- Dev originally worked fine on 51820 and kept it.
- Prod was originally 51821, got CGNAT-blocked, moved to 51830.
- AWS side never changes — it responds to whatever source port the packet
  arrived from.

See TS-NET-004 (troubleshooting/network/4-wireguard-cgnat-port-blocking.md)
for full diagnosis and fix.

---

## Verification

### On AWS EC2

  sudo wg show                              # WireGuard status
  sudo systemctl status wg-keepalive        # Keepalive service
  ping 172.16.200.1                         # Test tunnel (dev)

### On MikroTik

  /interface wireguard peers print          # Show peers
  /ping 172.16.200.2                        # Test tunnel (dev)

### From Internal Host

  ping 172.16.200.2                         # AWS tunnel IP
  traceroute 172.16.65.x                    # Should show tunnel hop

---

## Troubleshooting Reference

Key VPN troubleshooting cases in troubleshooting/network/:

| TS case    | Issue                              | Resolution                                                                 |
|------------|------------------------------------|----------------------------------------------------------------------------|
| TS-NET-004 | CGNAT port blocking (prod tunnel)  | Moved prod on-prem listen port from 51821 to 51830                         |
| TS-NET-005 | Tunnel stability (4-phase invest.) | Keepalive service + moved prod compute/network to us-east-1 + ER605 → MikroTik |

TS-NET-005 resolution also drove the retirement of the ER605 router (see
network/README.md) and the mixed-region prod setup on AWS (see aws/bootstrap.md).

For all cases: troubleshooting/network/

---

## Routing Design (Important)

### Why Tunnel IPs in VPC Range?

MikroTik's WireGuard peer AllowedIPs field routes traffic for matched IPs.
By placing tunnel IPs within VPC CIDR:

- Dev: 172.16.200.x within 172.16.0.0/16
- Prod: 172.17.200.x within 172.17.0.0/16

One AllowedIPs entry covers both tunnel AND VPC traffic:
- dev peer: 172.16.0.0/16 routes tunnel (172.16.200.x) + VPC (172.16.x.x)
- prod peer: 172.17.0.0/16 routes tunnel (172.17.200.x) + VPC (172.17.x.x)

See TS-NET-005 for the routing issue this solves.

---

## Environment Segmentation

### ACL Rules (MikroTik Firewall)

VPN traffic is segmented by environment:

- Dev VPN (172.16.x.x) can only reach Dev VLANs (60-65)
- Prod VPN (172.17.x.x) can only reach Prod VLANs (50-55)

Cross-environment traffic is blocked.

---

## Summary - File Reference

| Component                | Path                                              |
|--------------------------|---------------------------------------------------|
| WireGuard Setup Guide    | network/vpn/wireguard-setup-guide.txt                    |
| Setup Script             | network/vpn/setup-wireguard.sh                    |
| Quick Config Reference   | network/vpn/wireguard-config.txt                  |
| AWS Network Terraform    | terraform/dev/aws/network/                        |
| AWS Compute Terraform    | terraform/dev/aws/compute/                        |
| Network Workflow         | .github/workflows/dev-aws-network.yml             |
| Compute Workflow         | .github/workflows/dev-aws-compute.yml             |
| MikroTik Backup          | network/router/mikrotik/backups/backup-config-stable.rsc |
| SSH Config Template      | workstation/ssh-wg/ssh-config-template            |

---

## GitHub Secrets Reference

| Secret              | Purpose                              |
|---------------------|--------------------------------------|
| HOME_PUBLIC_IP      | Home IP for AWS security groups      |
| VPN_PUBLIC_KEY_DEV  | Dev VPN EC2 SSH public key           |
| VPN_PUBLIC_KEY_PROD | Prod VPN EC2 SSH public key          |

See github/variables-secrets.md for the full repo-level secrets reference.
AWS Elastic IPs for the VPN EC2 instances are NOT GitHub secrets — they
are Terraform-managed and retrieved via `terraform output` or the AWS
console after `dev-aws-compute` / `prod-aws-compute` workflows complete.

---

## Quick Commands

  # AWS EC2 - Check tunnel status
  sudo wg show

  # AWS EC2 - Restart WireGuard
  sudo systemctl restart wg-quick@wg0

  # AWS EC2 - Check keepalive
  sudo systemctl status wg-keepalive

  # AWS EC2 - Capture traffic
  sudo tcpdump -i enX0 udp port 51820 -n

  # MikroTik - Show peers
  /interface wireguard peers print

  # MikroTik - Show handshakes
  /interface wireguard peers print detail

---

## Deployment Order

VPN is step 5 — after AWS secrets, before Ansible/runner setup. For the
full 0–15 sequence, see [README.md](README.md).

---
