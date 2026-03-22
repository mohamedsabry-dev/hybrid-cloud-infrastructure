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
| FreeIPA | VM | 25GB | 25GB | 2GB | 2 | Identity mgmt |
| K8s Master 1 | VM | 25GB | - | 2GB | 2 | Control plane |
| K8s Master 2 | VM | 25GB | - | 2GB | 2 | Control plane |
| K8s Master 3 | VM | 25GB | - | 2GB | 2 | Control plane |
| K8s Worker 1 | VM | 25GB | 80GB | 2.75GB | 2 | Prom + Grafana |
| K8s Worker 2 | VM | 25GB | 80GB | 2.75GB | 2 | NGINX Ingress + Loki |
| K8s Worker 3 | VM | 25GB | 80GB | 2.75GB | 2 | Helm + FluxCD |
| Vault 1 | LXC | 10GB | 5GB | 0.75GB | 1 | Secrets mgmt |
| Vault 2 | LXC | 10GB | 5GB | 0.75GB | 1 | Secrets mgmt |
| Vault 3 | LXC | 10GB | 5GB | 0.75GB | 1 | Secrets mgmt |
| NGINX | LXC | 10GB | 5GB | 0.5GB | 1 | Reverse proxy |
| Ansible | LXC | 10GB | 5GB | 0.5GB | 1 | Automation |
| GH Runner | LXC | 15GB | 5GB | 0.5GB | 1 | GitHub Actions |

### Pod Distribution

| Pod | Worker | RAM | Purpose |
|-----|--------|-----|---------|
| Prometheus | Worker 1 | 0.5GB | Metrics |
| Grafana | Worker 1 | 0.5GB | Dashboards |
| NGINX Ingress | Worker 2 | 0.25GB | K8s Ingress |
| Loki | Worker 2 | 0.5GB | Log aggregation |
| Helm | Worker 3 | 0.5GB | Package mgmt |
| FluxCD | Worker 3 | 0.5GB | GitOps CD |

### Summary

| | Value |
|---|-------|
| OS Disk (local-lvm) | 240GB |
| Data Disk (NAS) | 295GB |
| RAM allocated | 20GB |
| Proxmox host | 2GB |
| Total RAM used | ~22GB |
| Buffer | ~2GB |
| vCPU | 20 |

---

## Production Environment (64GB RAM)

| Resource | Type | OS Disk | Data Disk | RAM | vCPU | Purpose |
|----------|------|---------|-----------|-----|------|---------|
| FreeIPA | VM | 25GB | 25GB | 3GB | 2 | Identity mgmt |
| K8s Master 1 | VM | 25GB | - | 4GB | 2 | Control plane |
| K8s Master 2 | VM | 25GB | - | 4GB | 2 | Control plane |
| K8s Master 3 | VM | 25GB | - | 4GB | 2 | Control plane |
| K8s Worker 1 | VM | 25GB | 80GB | 8GB | 4 | Prom + Grafana |
| K8s Worker 2 | VM | 25GB | 80GB | 8GB | 4 | NGINX Ingress + Loki |
| K8s Worker 3 | VM | 25GB | 80GB | 8GB | 4 | Helm + FluxCD |
| Vault 1 | LXC | 10GB | 5GB | 0.75GB | 1 | Secrets mgmt |
| Vault 2 | LXC | 10GB | 5GB | 0.75GB | 1 | Secrets mgmt |
| Vault 3 | LXC | 10GB | 5GB | 0.75GB | 1 | Secrets mgmt |
| NGINX | LXC | 10GB | 5GB | 0.5GB | 1 | Reverse proxy |
| Ansible | LXC | 10GB | 5GB | 0.5GB | 1 | Automation |
| GH Runner | LXC | 15GB | 5GB | 0.5GB | 1 | GitHub Actions |

### Pod Distribution

| Pod | Worker | RAM | vCPU | Purpose |
|-----|--------|-----|------|---------|
| Prometheus | Worker 1 | 1.5GB | 1 | Metrics |
| Grafana | Worker 1 | 1GB | 0.5 | Dashboards |
| NGINX Ingress | Worker 2 | 0.5GB | 1 | K8s Ingress |
| Loki | Worker 2 | 1.5GB | 1 | Log aggregation |
| Helm | Worker 3 | 1GB | 0.5 | Package mgmt |
| FluxCD | Worker 3 | 1GB | 0.5 | GitOps CD |

### Summary

| | Dev (24GB) | Prod (64GB) |
|---|------------|-------------|
| OS Disk (local-lvm) | 240GB | 240GB |
| Data Disk (NAS) | 295GB | 295GB |
| RAM allocated | 20GB | 42.75GB |
| Proxmox host | 2GB | 4GB |
| Total used | ~22GB | ~47GB |
| Buffer | ~2GB | ~17GB |
| vCPU | 20 | 26 |

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
| dev-storage | Dev only | 300GB | Dev data disks |
| prod-storage | Prod only | 300GB | Prod data disks |
| PBS backups | Both | 650GB | Proxmox Backup Server |
| **TOTAL** | | **1300GB** | ~500GB buffer on 1.8TB |

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
