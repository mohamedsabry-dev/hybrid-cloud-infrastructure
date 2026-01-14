# Network Overview

> **Three-tier network design strategy and topology**

---

## Overview

The DC-K8s environment uses a three-network architecture that separates external access, internal VM communication, and vMotion traffic. This design provides security isolation, supports nested virtualization, and enables future hybrid cloud integration.

---

## Network Summary

| Network | Subnet | Purpose | Gateway |
|---------|--------|---------|---------|
| **WAN/External** | 192.x.x.x/24 | Internet access, home network bridge | 192.x.x.1 (Home Router) |
| **Internal/LAN** | 10.0.20.x/24 | VM management & production traffic | 10.0.20.170 (pfSense) |
| **vMotion** | 10.0.30.x/24 | ESXi live migration traffic | None (isolated) |

---

## Network Topology

### High-Level View

```
Internet
  │
Home Router (192.x.x.1)
  │
  ├─ Mac PC: 192.x.x.##
  ├─ Windows Host: 192.x.x.##
  └─ WAN Network (192.x.x.x/24 - VMnet0 Bridge)
      │
      ├─ pfSense WAN: 192.x.x.##
      └─ ESXi Master vmk0: 192.x.x.##
           │
           ├─ pfSense LAN: 10.0.20.170 (Gateway for Internal)
           │
           └─ Internal Network (10.0.20.x/24 - VMnet2 Host-Only)
               ├─ Infrastructure VMs
               ├─ Production VMs
               └─ Management Interfaces
```

### Detailed Topology

```
┌──────────────────────────────────────────────────────┐
│          WAN Network (192.x.x.x/24)                  │
│                  VMnet0 (Bridge)                     │
├──────────────────────────────────────────────────────┤
│  pfSense WAN: 192.x.x.##                            │
│  ESXi Master vmk0: 192.x.x.##                       │
└──────────────────────────────────────────────────────┘
                      │
                      │ NAT Gateway
                      ↓
┌──────────────────────────────────────────────────────┐
│       Internal Network (10.0.20.x/24)                │
│             VMnet2 (Host-Only)                       │
│         Gateway: pfSense LAN (10.0.20.170)           │
├──────────────────────────────────────────────────────┤
│  Infrastructure Layer (ESXi Master)                  │
│    ├─ pfSense LAN: 10.0.20.170                      │
│    ├─ vCenter: 10.0.20.89                           │
│    ├─ NAS VM: 10.0.20.90 (bonded NICs)              │
│    ├─ IPA: 10.0.20.184 (DNS/Auth)                   │
│    ├─ Veeam: 10.0.20.195                            │
│    ├─ ESXi Master vmk1: 10.0.20.100                 │
│    ├─ ESXi Production: 10.0.20.101                  │
│    └─ ESXi DR: 10.0.20.102                          │
│                                                      │
│  Production VMs (ESXi Nested Production)             │
│    ├─ Ansible: 10.0.20.185                          │
│    ├─ Grafana: 10.0.20.186                          │
│    ├─ K8s-Master: 10.0.20.181                       │
│    ├─ K8s-Worker-1: 10.0.20.182                     │
│    ├─ K8s-Worker-2: 10.0.20.183                     │
│    ├─ K8s-Worker-3: 10.0.20.187                     │
│    ├─ Vault-1: 10.0.20.191                          │
│    ├─ Vault-2: 10.0.20.192                          │
│    ├─ Vault-3: 10.0.20.193                          │
│    └─ Jenkins: 10.0.20.196                          │
└──────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────┐
│       vMotion Network (10.0.30.x/24)                 │
│             VMnet3 (Host-Only)                       │
│              No Gateway (Isolated)                   │
├──────────────────────────────────────────────────────┤
│  ESXi Master vmk2: 10.0.30.100                      │
│  ESXi Production vmk: 10.0.30.101                   │
│  ESXi DR vmk: 10.0.30.102                           │
└──────────────────────────────────────────────────────┘
```

---

## Key Design Principles

### Security Through Segmentation
- **WAN isolation**: External network separate from internal
- **vMotion isolation**: Management/production traffic separate from migration
- **Gateway control**: All internet access through pfSense NAT

### Support for Nested Virtualization
- **Promiscuous mode**: Required on ESXi Master for nested VMs
- **Forged transmits**: Allows nested ESXi to forward traffic
- **MAC changes**: Supports vMotion and failover

### High Availability
- **NAS network bonding**: Active-Backup for zero downtime
- **DNS redundancy**: IPA primary, pfSense backup
- **Infrastructure DNS**: IPA placed in infrastructure layer for stable DNS service

### Future-Ready Architecture
- **VPN endpoint ready**: pfSense supports site-to-site VPN
- **Cloud integration**: DNS forwarding to AWS Route53 planned
- **Scalability**: Room for additional VLANs and networks

---

## IP Allocation Summary

### Infrastructure VMs (ESXi Master)

| IP Address | Hostname | FQDN | Status |
|------------|----------|------|--------|
| 10.0.20.89 | vcenter | vcenter.home.lab | Active |
| 10.0.20.90 | nas | nas.home.lab | Active |
| 10.0.20.100 | esxi-master | esxi-master.home.lab | Active |
| 10.0.20.101 | esxi-prod | esxi-prod-01.home.lab | Active |
| 10.0.20.102 | esxi-dr | esxi-dr-01.home.lab | Powered Off |
| 10.0.20.170 | pfsense | N/A | Active |
| 10.0.20.184 | ipa | ipa.home.lab | Active |
| 10.0.20.195 | veeam | N/A | Active |
| 10.0.20.222 | - | N/A | Active (Virtual IP) |

### Production VMs (ESXi Nested)

| IP Address | Hostname | FQDN | Status |
|------------|----------|------|--------|
| 10.0.20.181 | k8s-master | k8s-master.home.lab | Active |
| 10.0.20.182 | k8s-worker1 | k8s-worker1.home.lab | Active |
| 10.0.20.183 | k8s-worker2 | k8s-worker2.home.lab | Active |
| 10.0.20.185 | ansible | ansible.home.lab | Active |
| 10.0.20.186 | monitor | monitor.home.lab | Active |
| 10.0.20.187 | k8s-worker3 | k8s-worker3.home.lab | Active |
| 10.0.20.191 | vault-01 | vault-01.home.lab | Active |
| 10.0.20.192 | vault-02 | vault-02.home.lab | Active |
| 10.0.20.193 | vault-03 | vault-03.home.lab | Active |
| 10.0.20.196 | jenkins-master | jenkins-master.home.lab | Active |

### vMotion Network

| IP Address | Hostname | FQDN | VMkernel | Status |
|------------|----------|------|----------|--------|
| 10.0.30.100 | esxi-master | esxi-master.home.lab | vmk2 | Active |
| 10.0.30.101 | esxi-prod | esxi-prod.home.lab | vmk1 | Active |
| 10.0.30.102 | esxi-dr | esxi-dr.home.lab | vmk1 | Powered Off |

---

## Related Documentation

- [WAN Network](02-WAN-Network.md)
- [Internal Network](03-Internal-Network.md)
- [vMotion Network](04-vMotion-Network.md)
- [pfSense Configuration](05-pfSense-Configuration.md)
