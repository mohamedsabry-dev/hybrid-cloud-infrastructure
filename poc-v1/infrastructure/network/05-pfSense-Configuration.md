# pfSense Network Gateway Configuration

> **NAT gateway, firewall, and DNS resolver configuration**

---

## Overview

pfSense serves as the network gateway, firewall, and DNS backup for the entire environment.

**VM Location**: ESXi Master
**Interfaces**: 2 (WAN + LAN)
**Primary Functions**: NAT gateway, firewall, DNS resolver (backup)

---

## Interface Configuration

### WAN Interface
```
IP Address: 192.x.x.##
Netmask: 255.255.255.0
Gateway: 192.x.x.1 (Home Router)
Purpose: Internet access
Connected to: vSwitch0 (Bridge network)
```

### LAN Interface
```
IP Address: 10.0.20.170
Netmask: 255.255.255.0
Gateway: None (this IS the gateway)
Purpose: Internal network gateway
Connected to: vSwitch_Internal
```

---

## Primary Functions

### 1. NAT Gateway

**Configuration**: Automatic Outbound NAT

**How It Works:**
```
Internal VM (10.0.20.185) → Internet Request
  ↓
pfSense LAN receives packet
  ↓
NAT translation (source IP: 10.0.20.185 → 192.x.x.##)
  ↓
pfSense WAN sends packet to internet
  ↓
Internet sees connection from pfSense WAN IP only
```

**Benefits:**
- ✅ All VMs can reach internet via pfSense
- ✅ Internal network hidden from internet
- ✅ Single public IP for entire lab
- ✅ Security through network address translation

### 2. Firewall & Access Control

**WAN Interface Rules:**
- Default: Deny all inbound traffic
- Exception: Allow HTTPS (443) from Mac PC IP only

**LAN Interface Rules:**
- Default: Allow all outbound traffic (NAT applied)
- Future: Granular rules for specific workloads

**Web UI Access Control:**
- Mac PC: Access via WAN (192.x.x.##) ✓
- Windows Host: Access via LAN (10.0.20.170) ✓
- Other devices: Denied by default

### 3. DNS Resolver (Backup)

**Role:**
- Primary DNS: IPA Server (10.0.20.184)
- Backup DNS: pfSense (10.0.20.170)
- External queries forwarded to 8.8.8.8, 1.1.1.1

**See DNS configuration section below for details**

---

## Firewall Rules

### WAN Interface Rules

#### Rule 1: Allow Web Access from Mac PC Only
```
Source: 192.x.x.## (Mac PC)
Destination: pfSense WAN (192.x.x.##)
Ports: 443 (HTTPS)
Action: Allow
Purpose: Restrict web UI access to authorized workstation
```

**Why restrict?**
- Limits attack surface
- Prevents unauthorized configuration changes
- Security best practice for management interfaces

### LAN Interface Rules

#### Rule 1: Allow Internal to Internet
```
Source: 10.0.20.0/24
Destination: Any
Action: Allow (NAT applied)
Purpose: Internet access for all internal VMs
```

**Future Rules (Planned):**
- Granular rules for Docker containers
- Specific rules for Kubernetes pod egress
- VPN access rules for AWS site-to-site
- Allow/deny rules per application

---

## DNS Resolver (Unbound) Configuration

### Purpose
- Backup/redundant DNS resolver
- Forward internal queries to IPA
- Handle external DNS when IPA unavailable

### Enable DNS Resolver

**Path**: Services > DNS Resolver

```
Enable: ✓
Listen Port: 53
Network Interfaces: ALL
Outgoing Interfaces: ALL
DNSSEC: ✓ (optional)
```

### Domain Overrides

**Forward internal domain queries to IPA:**

```
Domain: home.lab
IP Address: 10.0.20.184 (IPA Server)
Description: Forward internal domain queries to IPA
```

**How It Works:**
```
VM queries "ansible.home.lab"
  ↓
pfSense DNS Resolver receives query
  ↓
Matches "home.lab" domain override
  ↓
Forwards query to IPA (10.0.20.184)
  ↓
IPA responds with 10.0.20.185
  ↓
pfSense returns answer to VM
```

### Upstream DNS Servers

**Path**: System > General Setup > DNS Servers

```
DNS Server 1: 8.8.8.8 (Google DNS)
DNS Server 2: 1.1.1.1 (Cloudflare DNS)
DNS Server 3: 192.168.x.x (Home Router - optional)
```

### DNS Architecture

**Primary DNS Strategy:**
```
VM → IPA Server (10.0.20.184) → Authoritative Answer
```

**Backup DNS Path:**
```
VM → pfSense (10.0.20.170) → Forwards to IPA → Answer
```

**When IPA Fails:**
```
VM → pfSense (10.0.20.170) → External DNS (8.8.8.8)
```

**Benefits:**
- ✅ Redundancy: If IPA fails, pfSense provides DNS
- ✅ HA: Multiple resolution paths
- ✅ Future VPN: VPN clients can use pfSense as DNS
- ✅ Hybrid Cloud: Can forward cloud domain queries to AWS Route53

### Testing DNS Resolution

**Test External DNS:**
```bash
# SSH to pfSense (Option 8: Shell)
nslookup google.com

Expected:
Server:         127.0.0.1
Address:        127.0.0.1#53
Name:   google.com
Address: 142.250.x.x
```

**Test Internal DNS (via IPA):**
```bash
nslookup ansible.home.lab

Expected:
Server:         127.0.0.1
Address:        127.0.0.1#53
Non-authoritative answer:
Name:   ansible.home.lab
Address: 10.0.20.185
```

---

## Mac Mini NAT Configuration (192.168.x → 10.0.20.222)

### Problem

Mac Mini (<HOME_IP>) on the home network could not access Vault VMs because Vault firewall rules only allow connections from the 10.0.20.0/24 subnet.

**Vault Firewall Configuration:**
```yaml
# 03-AUTOMATION/ansible-playbooks/vault/02-vault_fw_check.yml
firewalld_rules:
  - zone: public
    source: 10.0.20.0/24  # Only allow internal network
    port: 8200/tcp
```

### Solution: Virtual IP + Outbound NAT

Created a Virtual IP (10.0.20.222) on pfSense and configured Outbound NAT to masquerade Mac Mini traffic.

### Step 1: Create Virtual IP on pfSense

**Navigate**: Firewall → Virtual IPs

```
Type: IP Alias
Interface: LAN (10.0.20.x interface)
Address: 10.0.20.222/32
Description: "VIP for Mac Mini NAT"
```

**What This Does:**
Makes pfSense respond to traffic destined for 10.0.20.222 on the internal network.

### Step 2: Configure Outbound NAT

**Navigate**: Firewall → NAT → Outbound

```
Mode: Hybrid Outbound NAT (or Manual)
Interface: LAN (where traffic exits to Lab network)
Address Family: IPv4
Protocol: Any
Source: Network → <HOME_IP>/32 (Mac IP)
Destination: Network → 10.0.20.0/24 (Lab subnet)
Translation Address: 10.0.20.222 (VIP)
Description: "Masquerade Mac as 10.0.20.222"
```

### Traffic Flow

```
Mac Mini (<HOME_IP>)
  ↓
Home Router
  ↓
pfSense WAN (NAT translation applied)
  ↓
pfSense LAN (source rewritten to 10.0.20.222)
  ↓
Vault VM (sees connection from 10.0.20.222 → ✅ Allowed by firewall)
```

### Verification

**On Vault VM:**
```bash
netstat -tn | grep 222
```

**Expected Output:**
```
tcp  0  0  10.0.20.191:8200  10.0.20.222:62861  ESTABLISHED
tcp  0  0  10.0.20.191:8200  10.0.20.222:5150   ESTABLISHED
```

### Benefits

- ✅ Mac Mini can access Vault without weakening firewall rules
- ✅ Vault OS firewall remains restrictive (10.0.20.0/24 only)
- ✅ Easy maintenance from pfSense (no need to modify each VM's firewall)
- ✅ Clean separation: pfSense handles network translation, VMs handle application security

**Related Configuration:**
- Vault firewall rules: `03-AUTOMATION/ansible-playbooks/vault/02-vault_fw_check.yml`
- pfSense internet restriction: `03-AUTOMATION/ansible-playbooks/vault/09-internet-restriction.txt`

---

## Future: Hybrid Cloud Integration

### AWS Site-to-Site VPN

**Architecture:**
```
pfSense ↔ AWS VPC (VPN Tunnel)
  │
  ├─ home.lab queries → Forward to IPA (10.0.20.184)
  ├─ aws.home.lab queries → Forward to AWS Route53
  └─ Public queries → Forward to 8.8.8.8
```

**DNS Configuration with VPN:**

**Domain Overrides:**
```
Domain: home.lab
IP: 10.0.20.184 (IPA Server)

Domain: aws.home.lab
IP: 10.0.100.2 (AWS Route53 Resolver)
```

**Benefits:**
- Unified DNS view (on-prem + cloud)
- Secure connectivity to AWS resources
- Hybrid application deployment
- Cloud bursting capability

### VPN Tunnel Configuration (Planned)

**pfSense Side:**
```
Type: IPsec Site-to-Site
Local Network: 10.0.20.0/24
Remote Network: 10.0.100.0/16 (AWS VPC)
Remote Gateway: AWS VPN Gateway Public IP
Pre-shared Key: (generated)
```

**AWS Side:**
```
Create Virtual Private Gateway
Attach to VPC (10.0.100.0/16)
Create Customer Gateway (pfSense WAN IP)
Create Site-to-Site VPN Connection
```

---

## Troubleshooting

### Issue: Internal VMs Cannot Reach Internet

**Symptom**: VMs on 10.0.20.x cannot ping 8.8.8.8

**Diagnosis:**
```bash
# On affected VM
ping 8.8.8.8  # Fails
ping 10.0.20.170  # Works (can reach pfSense)

# On pfSense
ping 8.8.8.8  # Should work
```

**Cause**: NAT not configured or outbound rule missing

**Solution:**
1. Verify NAT: Firewall → NAT → Outbound
2. Ensure rule exists for 10.0.20.0/24 → Any
3. Verify pfSense WAN interface has internet

### Issue: Cannot Access pfSense Web UI

**Symptom**: Cannot connect to pfSense HTTPS interface

**Solution by Source:**

**From Mac PC (192.x.x.##):**
- Access via WAN: `https://192.x.x.##`
- Should work (firewall rule allows)

**From Windows Host (192.x.x.##):**
- Access via LAN: `https://10.0.20.170`
- WAN access blocked by firewall

**From Internal VM (10.0.20.x):**
- Access via LAN: `https://10.0.20.170`

### Issue: DNS Resolution Slow

**Symptom**: DNS queries take 5-10 seconds

**Cause**: pfSense forwarding to IPA, IPA slow or unreachable

**Diagnosis:**
```bash
# On pfSense
nslookup ansible.home.lab 10.0.20.184  # Direct IPA query
# If slow: IPA issue
# If fast: pfSense forwarding issue
```

**Solution:**
1. Check IPA server health
2. Verify domain override configured correctly
3. Test direct DNS queries to IPA from pfSense

---

## Related Documentation

- [Network Overview](01-Network-Overview.md)
- [WAN Network](02-WAN-Network.md)
- [Internal Network](03-Internal-Network.md)
- [Network Security](07-Network-Security-and-Troubleshooting.md)
- [Platform Layer - Identity Management](../../02-Platform-Layer/)
