# Network Architecture

> **Archived PoC v1 material** — retired infrastructure, not the current project.
> See [`../../README.md`](../../README.md) for the retirement story and the current
> network stack (MikroTik + FS308GP + physical cabling). The three-tier design
> described below is the **PoC v1 network layout**, based on pfSense + VMware
> virtual networking, which has been fully replaced.

---

> **Three-tier network design with security segmentation and nested virtualization support** *(PoC v1 era)*

---

## Overview

The DC-K8s environment uses a three-network architecture that separates external access, internal VM communication, and vMotion traffic. This design provides security isolation, supports nested virtualization, and enables future hybrid cloud integration.

---

## Documents in This Section

### [01-Network-Overview.md](01-Network-Overview.md)
Network strategy, topology, and design summary
- Three-tier network design (WAN, Internal, vMotion)
- Network topology diagrams
- IP allocation summary

### [02-WAN-Network.md](02-WAN-Network.md)
External/WAN network configuration
- Bridge to home router
- ESXi Master vSwitch0 configuration
- Security settings

### [03-Internal-Network.md](03-Internal-Network.md)
Internal/LAN network configuration
- VM communication and management traffic
- IP address allocation
- Nested virtualization settings

### [04-vMotion-Network.md](04-vMotion-Network.md)
Dedicated vMotion network configuration
- vMotion isolation strategy
- VMkernel adapter configuration
- Performance benefits

### [05-pfSense-Configuration.md](05-pfSense-Configuration.md)
pfSense gateway and firewall configuration
- NAT gateway setup
- Firewall rules
- DNS resolver configuration
- Mac Mini NAT/VIP setup

### [06-NAS-Network-Bonding.md](06-NAS-Network-Bonding.md)
NAS VM network bonding for high availability
- Active-Backup bonding mode
- miimon parameter explanation
- Failover testing results

### [07-Network-Security-and-Troubleshooting.md](07-Network-Security-and-Troubleshooting.md)
Security best practices and common issues
- Network segmentation
- Promiscuous mode requirements
- Common network troubleshooting

---

## Quick Reference

### Network Summary

| Network | Subnet | Purpose | Gateway |
|---------|--------|---------|---------|
| **WAN/External** | 192.x.x.x/24 | Internet access, home network bridge | 192.x.x.1 (Home Router) |
| **Internal/LAN** | 10.0.20.x/24 | VM management & production traffic | 10.0.20.170 (pfSense) |
| **vMotion** | 10.0.30.x/24 | ESXi live migration traffic | None (isolated) |

### Key Design Principles

✅ **Network segmentation** for security and performance isolation
✅ **Dedicated vMotion network** prevents I/O contention
✅ **NAS network bonding** for high availability
✅ **DNS redundancy** (IPA primary, pfSense backup)
✅ **Nested virtualization support** with promiscuous mode
✅ **Future hybrid cloud ready** (VPN, AWS integration)

---

## Related Documentation

- [Storage Architecture](../storage/)
- [Compute Resources](../compute/)
- [Troubleshooting Cases](../../troubleshooting/network/)
- [Documentation Overview](../README.md)
