# Hybrid Cloud Infrastructure

A home-lab hybrid cloud setup connecting on-premises Proxmox servers to AWS, managed with Terraform, Ansible, and Kubernetes.

---

## Architecture Overview

```
On-Premises (Proxmox)              AWS
┌──────────────────────┐           ┌──────────────────────┐
│  PROD Server         │           │  Prod VPC            │
│  Ryzen 7 7435HS      │◄─────────►│  172.17.0.0/16       │
│  64GB RAM            │ WireGuard │                      │
├──────────────────────┤   VPN     ├──────────────────────┤
│  DEV Server          │           │  Dev VPC             │
│  Ryzen 7 7730U       │◄─────────►│  172.16.0.0/16       │
│  24GB RAM            │           │                      │
└──────────────────────┘           └──────────────────────┘
         │
   NAS (TrueNAS)
   1.8TB RAID1
```

---

## Repository Structure

| Directory | Purpose |
|-----------|---------|
| [terraform/](terraform/) | Infrastructure as Code for Proxmox VMs/LXCs and AWS resources |
| [ansible/](ansible/) | Configuration management playbooks |
| [kubernetes/](kubernetes/) | Kubernetes manifests and examples |
| [proxmox/](proxmox/) | Proxmox host bootstrap, golden templates, DR guides |
| [network/](network/) | Network device configs (router, switch, AP, VPN) |
| [aws/](aws/) | AWS-specific documentation |
| [github/](github/) | GitHub Actions workflows |
| [workstation/](workstation/) | Local workstation setup |
| [troubleshooting/](troubleshooting/) | Troubleshooting logs and guides |
| [archive/](archive/) | Archived PoC configurations |

---

## Environments

| Environment | Proxmox Host | Management IP | AWS VPC |
|-------------|-------------|---------------|---------|
| Production | pve-prod.lab.local | 10.0.5.100 | 172.17.0.0/16 |
| Development | pve-dev.lab.local | 10.0.5.110 | 172.16.0.0/16 |

---

## Key Components

| Component | Technology | Purpose |
|-----------|------------|---------|
| Hypervisor | Proxmox VE | VM/LXC hosting |
| IaC | Terraform | Provision VMs, LXCs, and AWS resources |
| Config Mgmt | Ansible | OS configuration and app deployment |
| Container Orch | Kubernetes (k3s) | Application orchestration |
| Secrets | HashiCorp Vault | Secrets management (3-node HA) |
| Identity | FreeIPA | DNS and identity management |
| Monitoring | Prometheus + Grafana | Metrics and dashboards |
| Logging | Loki | Log aggregation |
| GitOps | FluxCD | Continuous delivery |
| Ingress | NGINX | Kubernetes ingress controller |
| Reverse Proxy | NGINX LXC | External reverse proxy |
| VPN | WireGuard | On-prem to AWS connectivity |
| Storage | TrueNAS (NAS) | Centralized NFS storage (1.8TB RAID1) |
| Backups | Proxmox Backup Server | VM/LXC backup and restore |

---

## Quick Start

### Deploy Infrastructure (Terraform)

```bash
cd terraform/dev/proxmox/vms
terraform init
terraform plan
terraform apply
```

### Configure Hosts (Ansible)

```bash
cd ansible/dev
ansible-playbook playbooks/common/site.yml
```

### Bootstrap New Proxmox Host

```bash
./proxmox/bootstrap_proxmox/bootstrap.sh dev   # or prod
./proxmox/bootstrap_proxmox/network-setup.sh dev
```

---

## Resource Summary

See [capacity-planning.md](capacity-planning.md) for full hardware and resource allocation details.

| Environment | RAM | vCPU | Storage (local) | Storage (NAS) |
|-------------|-----|------|-----------------|---------------|
| Dev | 24GB | 16 | 500GB NVMe | 300GB |
| Prod | 64GB | 16 | 500GB NVMe | 300GB |

---

## Network

See [network/README.md](network/README.md) for full network documentation, VLAN assignments, and device configs.

**Domain:** `lab.local`

**VPN Tunnels (WireGuard):**
- Dev: `172.16.200.1` (ER605) ↔ `172.16.200.2` (AWS)
- Prod: `172.17.200.1` (ER605) ↔ `172.17.200.2` (AWS)
