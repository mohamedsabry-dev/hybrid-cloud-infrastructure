# Internal/LAN Network

> **Primary VM communication and management network**

---

## Purpose

- Primary VM communication network
- Management traffic
- Production workload traffic
- NFS storage traffic

---

## Network Configuration

**Subnet**: 10.0.20.x/24
**Gateway**: 10.0.20.170 (pfSense LAN interface)
**DNS Primary**: 10.0.20.184 (IPA Server)
**DNS Secondary**: 10.0.20.170 (pfSense)
**VMware Type**: VMnet2 (Host-Only network)

---

## ESXi Master - vSwitch_Internal

### vSwitch Configuration

**Uplinks**: 1 physical vNIC from VMnet2

**Security Policies (CRITICAL):**
- **Promiscuous Mode: ON** ⚠️ (Required for nested virtualization)
- **Forged Transmits: ON** ⚠️ (Required for nested ESXi)
- **MAC Changes: ON** ⚠️ (Required for vMotion)

### Why Promiscuous Mode is Required

Nested ESXi hosts need to receive traffic for nested VMs with different MAC addresses. Without promiscuous mode, nested VMs would be completely isolated.

**How It Works:**
1. Nested VM sends packet with MAC `AA:BB:CC:DD:EE:FF`
2. Nested ESXi forwards packet via its vNIC (MAC `11:22:33:44:55:66`)
3. ESXi Master vSwitch_Internal sees packet with nested VM MAC
4. **With Promiscuous Mode**: Forwards packet to correct destination
5. **Without Promiscuous Mode**: Drops packet (unknown MAC)

**Reference**: See troubleshooting case [04-Network-Promiscuous-Mode-Nested-Virtualization.md](../../../05-TROUBLESHOOTING/cases/network/04-Network-Promiscuous-Mode-Nested-Virtualization.md)

### Portgroups

#### 1. VM Internal Network
- All infrastructure VMs
- All production VMs
- Nested ESXi hosts

#### 2. Management Network Internal
- **Interface**: ESXi Master vmk1: 10.0.20.100
- **Purpose**: Primary management interface

---

## ESXi Production Server (Nested) - vSwitch_Internal

### vSwitch Configuration

**Uplinks**: 1 virtual vNIC from ESXi Master

**Security Policies:**
- **Promiscuous Mode: OFF** (not needed inside nested ESXi)
- **Forged Transmits: OFF**
- **MAC Changes: OFF**

**Why Different from ESXi Master?**
- Nested ESXi VMs behave like normal VMs
- No additional nesting inside Production ESXi
- Standard security policies sufficient

### Portgroups

#### 1. VM Internal Network
- All production VMs (IPA, K8s, Vault, etc.)

#### 2. Management Network
- **Interface**: ESXi Production vmk: 10.0.20.101

---

## ESXi DR Server (Nested) - vSwitch_Internal

**Status**: Cold Standby (Powered OFF)

**Configuration**: Mirrors Production ESXi
- Management: 10.0.20.102
- Activated only during DR scenarios

---

## IP Address Allocation

### Infrastructure VMs (ESXi Master)

| IP Address | Hostname | FQDN | Type | Status | Notes |
|------------|----------|------|------|--------|-------|
| 10.0.20.89 | vcenter | vcenter.home.lab | Management | Active | vCenter Server (LAN interface) |
| 10.0.20.90 | nas | nas.home.lab | Infrastructure | Active | NAS VM - Bond0 (2 vNICs: ens33 + ens35) |
| 10.0.20.100 | esxi-master | esxi-master.home.lab | ESXi Host | Active | ESXi Master vmk1 (Management) |
| 10.0.20.101 | esxi-prod | esxi-prod-01.home.lab | ESXi Host | Active | ESXi Production (Nested) |
| 10.0.20.102 | esxi-dr | esxi-dr-01.home.lab | ESXi Host | Powered Off | ESXi DR (Cold Standby) |
| 10.0.20.170 | pfsense | N/A | Gateway | Active | pfSense LAN Interface (Gateway) |
| 10.0.20.195 | veeam | N/A | Infrastructure | Active | Veeam Backup Server |
| 10.0.20.222 | - | N/A | Virtual IP | Active | pfSense VIP - Outbound NAT for Mac Mini |

### Production VMs (ESXi Nested Production)

| IP Address | Hostname | FQDN | Type | Status | Notes |
|------------|----------|------|------|--------|-------|
| 10.0.20.181 | k8s-master | k8s-master.home.lab | Production | Active | Kubernetes Master |
| 10.0.20.182 | k8s-worker1 | k8s-worker1.home.lab | Production | Active | Kubernetes Worker 1 |
| 10.0.20.183 | k8s-worker2 | k8s-worker2.home.lab | Production | Active | Kubernetes Worker 2 |
| 10.0.20.184 | ipa | ipa.home.lab | Production | Active | FreeIPA Server (DNS, LDAP, Kerberos) |
| 10.0.20.185 | ansible | ansible.home.lab | Production | Active | Ansible Controller |
| 10.0.20.186 | monitor | monitor.home.lab | Production | Active | Grafana Monitoring |
| 10.0.20.187 | k8s-worker3 | k8s-worker3.home.lab | Production | Active | Kubernetes Worker 3 |
| 10.0.20.191 | vault-01 | vault-01.home.lab | Production | Active | Vault Node 1 |
| 10.0.20.192 | vault-02 | vault-02.home.lab | Production | Active | Vault Node 2 |
| 10.0.20.193 | vault-03 | vault-03.home.lab | Production | Active | Vault Node 3 |
| 10.0.20.196 | jenkins-master | jenkins-master.home.lab | Production | Active | Jenkins Master |

---

## DNS Configuration

### Primary DNS: IPA Server (10.0.20.184)

**Purpose**: Authoritative DNS for home.lab domain

**Responsibilities:**
- A/PTR records for all VMs
- SRV records for services (LDAP, Kerberos)
- DNSSEC signing (optional)

### Secondary DNS: pfSense (10.0.20.170)

**Purpose**: Backup DNS resolver

**Responsibilities:**
- Forward internal queries to IPA
- Resolve external queries directly
- Provide DNS when IPA is unavailable

**Configuration**: See [pfSense Configuration](05-pfSense-Configuration.md)

---

## Network Traffic Types

### Management Traffic
- vCenter to ESXi hosts
- ESXi to ESXi (cluster operations)
- SSH/Web UI access
- Veeam to VMs (backup)

### Production Traffic
- VM to VM communication
- K8s pod networking
- Application traffic
- NFS storage traffic

### Why Not Separate Management and Production?

**Current Design: Single Internal Network**
- ✅ Simpler configuration
- ✅ Fewer VMware networks to manage
- ✅ Adequate for home lab scale

**Future Consideration: Separate Networks**
- Dedicated management VLAN (10.0.10.x/24)
- Dedicated production VLAN (10.0.20.x/24)
- Better security isolation
- Easier traffic shaping

---

## Nested Virtualization Requirements

### Security Policy Summary

| vSwitch | Promiscuous | Forged Transmits | MAC Changes |
|---------|-------------|------------------|-------------|
| ESXi Master (vSwitch_Internal) | **ON** ⚠️ | **ON** ⚠️ | **ON** ⚠️ |
| ESXi Nested (Production/DR) | OFF | OFF | OFF |

**Why these settings:**
- **Master needs to forward traffic** for nested VMs with different MACs
- **Nested ESXi doesn't nest again**, standard settings suffice

---

## Troubleshooting

### Issue: Nested VMs Have No Network Connectivity

**Symptom**: Nested ESXi VMs completely isolated, cannot ping gateway

**Cause**: Promiscuous mode, forged transmits, or MAC changes disabled on ESXi Master

**Solution**: Enable all three security policies on vSwitch_Internal

**Verification:**
```bash
# SSH to ESXi Master
vim-cmd hostsvc/net/query_networkhint --pnic-names=vmnic1

# Verify promiscuous mode is ON
```

### Issue: Reverse Path Forwarding Errors

**Symptom**: Ping shows 3 duplicate responses per request

**Cause**: Promiscuous mode with Active/Standby uplink redundancy creates loop

**Solution**: Enable RPF check on ESXi Master
```bash
esxcli system settings advanced set -o /Net/ReversePathFwdCheckPromisc -i 1
```

**Reference**: [05-Network-Duplicate-Packets-Loop-RPF.md](../../../05-TROUBLESHOOTING/cases/network/05-Network-Duplicate-Packets-Loop-RPF.md)

---

## Related Documentation

- [Network Overview](01-Network-Overview.md)
- [WAN Network](02-WAN-Network.md)
- [vMotion Network](04-vMotion-Network.md)
- [Network Security](07-Network-Security-and-Troubleshooting.md)
