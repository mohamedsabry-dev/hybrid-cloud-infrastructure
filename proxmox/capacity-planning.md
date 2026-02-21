# Resource Planning Documentation

## Environment Context

- **Type:** Home Lab - Development & Learning
- **Usage:** Few hours per day, shut down when not in use
- **Focus:** Terraform, Ansible, Python development
- **Workload:** Light (not heavy K8s production loads)
- **Power:** Energy-conscious, limited home space

---

## Hardware Summary

| Server | CPU | RAM | Local Storage | Notes |
|--------|-----|-----|---------------|-------|
| Dev Server | Ryzen 7 7730U (8c/16t) | 24GB | 500GB NVMe | 16 vCPUs |
| Prod Server | Ryzen 7 7435HS (8c/16t) | 64GB | 500GB NVMe | 16 vCPUs |
| NAS | ASUSTOR FLASHSTOR 6 FS6706T | - | 2x2TB RAID1 | 1.8TB usable |

---

## Development Environment (24GB RAM, 500GB NVMe)

| Resource | Type | OS Disk | Data Disk | RAM | vCPU | Purpose |
|----------|------|---------|-----------|-----|------|---------|
| FreeIPA | VM | 25GB | 30GB | 1.5GB | 1 | Identity mgmt |
| K8s Master 1 | VM | 25GB | - | 2GB | 2 | Control plane |
| K8s Master 2 | VM | 25GB | - | 2GB | 2 | Control plane |
| K8s Master 3 | VM | 25GB | - | 2GB | 2 | Control plane |
| K8s Worker 1 | VM | 25GB | 50GB | 2.25GB | 2 | Workloads |
| K8s Worker 2 | VM | 25GB | 50GB | 2.25GB | 2 | Workloads |
| K8s Worker 3 | VM | 25GB | 50GB | 2.25GB | 2 | Workloads |
| Vault 1 | VM | 25GB | 20GB | 1GB | 1 | Secrets mgmt |
| Vault 2 | VM | 25GB | 20GB | 1GB | 1 | Secrets mgmt |
| Vault 3 | VM | 25GB | 20GB | 1GB | 1 | Secrets mgmt |
| NGINX | LXC | 15GB | - | 0.5GB | 1 | Reverse proxy |
| Ansible | LXC | 15GB | - | 0.75GB | 1 | Automation |
| GH Runner | LXC | 15GB | 20GB | 1GB | 2 | GitHub Actions |
| Prometheus | LXC | 15GB | 30GB | 0.5GB | 1 | Metrics |
| Grafana | LXC | 15GB | 10GB | 0.5GB | 1 | Dashboards |
| Loki | LXC | 15GB | 50GB | 0.5GB | 1 | Log aggregation |
| NGINX Ingress | POD | - | - | 0.25GB | 0.5 | K8s Ingress |
| Flux CD | POD | - | - | 0.5GB | 0.5 | GitOps CD |
| Helm | POD | - | - | 0.5GB | 0.5 | Package mgmt |
| **TOTALS** | | **340GB** | **330GB** | **20.5GB** | **22** | |

*Note: POD RAM runs inside K8s workers (already allocated above)*

**Summary:**
- Local NVMe: ~340GB OS + 10GB ISOs = ~350GB used, ~150GB free (snapshots)
- NAS (dev-storage): ~330GB data disks
- RAM: 20.5GB VMs/LXCs + 2GB Proxmox = ~22.5GB, ~1.5GB buffer

---

## Production Environment (64GB RAM, 500GB NVMe)

| Resource | Type | OS Disk | Data Disk | RAM | vCPU | Purpose |
|----------|------|---------|-----------|-----|------|---------|
| FreeIPA | VM | 25GB | 40GB | 3GB | 2 | Identity mgmt |
| K8s Master 1 | VM | 25GB | - | 4GB | 2 | Control plane |
| K8s Master 2 | VM | 25GB | - | 4GB | 2 | Control plane |
| K8s Master 3 | VM | 25GB | - | 4GB | 2 | Control plane |
| K8s Worker 1 | VM | 25GB | 100GB | 8GB | 2 | Workloads |
| K8s Worker 2 | VM | 25GB | 100GB | 8GB | 2 | Workloads |
| K8s Worker 3 | VM | 25GB | 100GB | 8GB | 2 | Workloads |
| Vault 1 | VM | 25GB | 25GB | 2GB | 1 | Secrets mgmt |
| Vault 2 | VM | 25GB | 25GB | 2GB | 1 | Secrets mgmt |
| Vault 3 | VM | 25GB | 25GB | 2GB | 1 | Secrets mgmt |
| NGINX | LXC | 15GB | - | 1GB | 2 | Reverse proxy |
| Ansible | LXC | 15GB | - | 1GB | 1 | Automation |
| GH Runner | LXC | 15GB | 30GB | 2GB | 2 | GitHub Actions |
| Prometheus | LXC | 15GB | 50GB | 1GB | 1 | Metrics |
| Grafana | LXC | 15GB | 15GB | 1GB | 1 | Dashboards |
| Loki | LXC | 15GB | 70GB | 1GB | 1 | Log aggregation |
| NGINX Ingress | POD | - | - | 0.5GB | 1 | K8s Ingress |
| Flux CD | POD | - | - | 1GB | 1 | GitOps CD |
| Helm | POD | - | - | 0.5GB | 0.5 | Package mgmt |
| **TOTALS** | | **340GB** | **580GB** | **52GB** | **25** | |

*Note: POD RAM runs inside K8s workers (already allocated above)*

**Summary:**
- Local NVMe: ~340GB OS + 10GB ISOs = ~350GB used, ~150GB free (snapshots)
- NAS (prod-storage): ~580GB data disks
- RAM: 52GB VMs/LXCs + 4GB Proxmox = ~56GB, ~8GB buffer

---

## NAS Storage Allocation (1.8TB Total)

**NAS:** ASUSTOR FLASHSTOR 6 FS6706T (2x2TB RAID1 = 1.8TB usable)

The NAS provides centralized storage for all resources:
- ISO images and container templates (shared)
- VM/LXC data disks (per environment)
- Proxmox Backup Server backups (shared)

| Share | Environment | Size | Content |
|-------|-------------|------|---------|
| shared-iso | Both | 50GB | ISO images, templates |
| dev-storage | Dev only | 360GB | Dev data disks |
| prod-storage | Prod only | 600GB | Prod data disks |
| PBS backups | Both | 650GB | Proxmox Backup Server |
| **TOTAL** | | **1660GB** | ~140GB buffer on 1.8TB |

---

## Proxmox NFS Storage Mounts

Each Proxmox server mounts 2 NFS shares from NAS:
- `nas-iso` - Shared ISO/template storage (both servers access same share)
- `nas-{env}-data` - Environment-specific data disks (isolated per environment)

### DEV Server (10.0.5.110)

*Datacenter > Storage > Add > NFS*

| Storage ID | NFS Server | Export | Content Types |
|------------|------------|--------|---------------|
| nas-iso | 10.0.40.120 | /volume1/shared-iso | ISO image, Container template |
| nas-dev-data | 10.0.40.120 | /volume1/dev-storage | Disk image, Container, Backup |

### PROD Server (10.0.5.100)

*Datacenter > Storage > Add > NFS*

| Storage ID | NFS Server | Export | Content Types |
|------------|------------|--------|---------------|
| nas-iso | 10.0.40.120 | /volume1/shared-iso | ISO image, Container template |
| nas-prod-data | 10.0.40.120 | /volume1/prod-storage | Disk image, Container, Backup |

### Storage Usage

- **OS disks** - Local NVMe (fast boot/performance)
- **Data disks** - NAS NFS share (persistent, shared across VMs)
- **ISOs** - NAS shared-iso (uploaded once, used by both servers)
- **Backups** - NAS PBS share (centralized backup location)

---

## ISO Images Required

| Image | Size | Purpose |
|-------|------|---------|
| proxmox-ve_9.1-1.iso | ~1.2GB | Proxmox VE hypervisor |
| proxmox-backup-server_4.1-1.iso | ~0.9GB | Proxmox Backup Server |
| Rocky-10.1-x86_64-minimal.iso | ~1.5GB | Rocky Linux for VMs |
| rockylinux-10-default_20251001_amd64.tar.xz | ~150MB | Rocky Linux LXC template |

---

## Backup Strategy

| Storage Type | Content | Backup Target |
|--------------|---------|---------------|
| Local NVMe | OS disks only | PBS on NAS (daily snapshots) |
| NAS Data | Persistent data | NAS-level snapshots + RAID 1 |
| NAS PBS | VM/LXC backups | RAID 1 redundancy |

---

## Notes

- Data disks stored on NAS, accessed via NFS mount
- OS disks stored on local NVMe for performance
- vCPU overcommit acceptable for home lab workloads
- Thin provisioning used - disk sizes are max limits
