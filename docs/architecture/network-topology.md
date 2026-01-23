# Network Topology

## Overview

Network design for the hybrid cloud infrastructure connecting on-premises and AWS environments.

## Network Segments

### On-Premises

| Network | CIDR | Purpose |
|---------|------|---------|
| Management | 10.0.1.0/24 | ESXi, vCenter, infrastructure |
| Production | 10.0.10.0/24 | Production workloads |
| DR | 10.0.20.0/24 | Disaster recovery |
| Storage | 10.0.30.0/24 | NFS/iSCSI traffic |
| Kubernetes | 10.0.100.0/24 | K8s nodes |

### AWS VPC

| Subnet | CIDR | Purpose |
|--------|------|---------|
| Public | 172.16.1.0/24 | VPN, NAT Gateway |
| Private | 172.16.10.0/24 | EKS workers |
| Data | 172.16.20.0/24 | RDS, ElastiCache |

## VPN Configuration

```
On-Premises (pfSense)          AWS (VPN Gateway)
    10.0.0.0/16     ◄─────────►    172.16.0.0/16
         │                              │
    IPSec Tunnel (AES-256)             │
         │                              │
    Phase 1: IKEv2                     │
    Phase 2: ESP                       │
```

## DNS Resolution

- Internal: FreeIPA (*.internal.local)
- External: Route53 (*.example.com)
- Split-horizon DNS for hybrid access

## Firewall Rules (pfSense)

| Source | Destination | Port | Action |
|--------|-------------|------|--------|
| LAN | Any | Any | Allow |
| VPN | Management | 22,443 | Allow |
| VPN | K8s API | 6443 | Allow |
| Any | pfSense | 500,4500 | Allow (IPSec) |

## Related

- [Overall Design](overall-design.md)
- [pfSense Configuration](../../pfsense/docs/)
