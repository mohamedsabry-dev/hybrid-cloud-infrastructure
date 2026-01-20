# Overall Architecture Design

## Overview

This hybrid cloud infrastructure spans AWS cloud services and on-premises VMware infrastructure, connected via site-to-site VPN.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              HYBRID CLOUD INFRASTRUCTURE                         │
├─────────────────────────────────────┬───────────────────────────────────────────┤
│         ON-PREMISES (VMware)        │              AWS CLOUD                     │
│                                     │                                            │
│  ┌───────────────────────────────┐  │  ┌──────────────────────────────────────┐ │
│  │     ESXi Host (Master)        │  │  │              AWS VPC                  │ │
│  │  ┌─────────┐  ┌─────────┐    │  │  │  ┌──────────┐  ┌──────────────────┐  │ │
│  │  │ ESXi    │  │ ESXi    │    │  │  │  │   EKS    │  │    EC2 (VPN)     │  │ │
│  │  │ (Prod)  │  │ (DR)    │    │  │  │  │ Workers  │  │   OpenVPN        │  │ │
│  │  └─────────┘  └─────────┘    │  │  │  └──────────┘  └──────────────────┘  │ │
│  │       ┌─────────┐            │  │  │                                       │ │
│  │       │ vCenter │            │  │  │  ┌──────────┐  ┌──────────────────┐  │ │
│  │       └─────────┘            │  │  │  │    S3    │  │    DynamoDB      │  │ │
│  └───────────────────────────────┘  │  │  │ (State)  │  │    (Lock)        │  │ │
│                                     │  │  └──────────┘  └──────────────────┘  │ │
│  ┌───────────────────────────────┐  │  └──────────────────────────────────────┘ │
│  │      Core Services VMs        │  │                                            │
│  │  ┌─────────┐  ┌─────────┐    │  │                                            │
│  │  │ FreeIPA │  │  Vault  │    │  │                                            │
│  │  │ (DNS/   │  │ (HA     │    │  │                                            │
│  │  │  Auth)  │  │ Cluster)│    │  │                                            │
│  │  └─────────┘  └─────────┘    │  │                                            │
│  │  ┌─────────┐  ┌─────────┐    │  │                                            │
│  │  │ Jenkins │  │ TrueNAS │    │  │                                            │
│  │  │         │  │ (NFS/   │    │  │                                            │
│  │  │         │  │  iSCSI) │    │  │                                            │
│  │  └─────────┘  └─────────┘    │  │                                            │
│  └───────────────────────────────┘  │                                            │
│                                     │                                            │
│  ┌───────────────────────────────┐  │                                            │
│  │      Kubernetes Cluster       │  │                                            │
│  │  ┌─────────┐  ┌─────────┐    │  │                                            │
│  │  │ Control │  │ Workers │    │  │                                            │
│  │  │  Plane  │  │  (3+)   │    │  │                                            │
│  │  └─────────┘  └─────────┘    │  │                                            │
│  └───────────────────────────────┘  │                                            │
│                                     │                                            │
│  ┌───────────────────────────────┐  │                                            │
│  │         Monitoring            │  │                                            │
│  │  ┌─────────┐  ┌─────────┐    │  │                                            │
│  │  │Promethus│  │ Grafana │    │  │                                            │
│  │  └─────────┘  └─────────┘    │  │                                            │
│  └───────────────────────────────┘  │                                            │
│                                     │                                            │
│          ┌─────────┐               │                                            │
│          │ pfSense │◄──────────────VPN──────────────────────────────────────────┤
│          │ (FW/VPN)│               │                                            │
│          └─────────┘               │                                            │
│                                     │                                            │
└─────────────────────────────────────┴───────────────────────────────────────────┘
```

## Component Overview

| Component | Location | Purpose |
|-----------|----------|---------|
| ESXi Hosts | On-prem | VM hosting (Prod/DR) |
| vCenter | On-prem | VMware management |
| FreeIPA | On-prem | Identity/DNS/Kerberos |
| Vault | On-prem | Secrets management |
| Jenkins | On-prem | CI/CD automation |
| TrueNAS | On-prem | Network storage |
| K8s Cluster | On-prem | Container orchestration |
| Prometheus/Grafana | On-prem | Monitoring |
| pfSense | On-prem | Firewall/VPN gateway |
| EKS Workers | AWS | Public K8s workers |
| S3/DynamoDB | AWS | Terraform state |
| EC2 VPN | AWS | VPN endpoint |

## Network Design

- On-prem network: 10.x.x.x/16
- AWS VPC: 172.x.x.x/16
- VPN: Site-to-site between pfSense and AWS

## Related Documents

- [Network Topology](network-topology.md)
- [Phase Implementations](../phase-implementations/)
