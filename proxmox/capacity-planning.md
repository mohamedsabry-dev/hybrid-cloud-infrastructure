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

Development Environment (24GB RAM, 500GB NVMe)
ResourceTypeOS DiskData DiskRAMvCPUPurposeFreeIPAVM25GB30GB2GB1Identity mgmtK8s Master 1VM25GB-2GB2Control planeK8s Master 2VM25GB-2GB2Control planeK8s Master 3VM25GB-2GB2Control planeK8s Worker 1VM25GB80GB2.75GB2Prom + GrafanaK8s Worker 2VM25GB80GB2.75GB2NGINX Ingress + LokiK8s Worker 3VM25GB80GB2.75GB2Helm + FluxCDVault 1LXC15GB20GB0.75GB1Secrets mgmtVault 2LXC15GB20GB0.75GB1Secrets mgmtVault 3LXC15GB20GB0.75GB1Secrets mgmtNGINXLXC15GB-0.5GB1Reverse proxyAnsibleLXC15GB-0.75GB1AutomationGH RunnerLXC15GB20GB0.75GB2GitHub Actions

Pod Distribution:
PodWorkerRAMPurposePrometheusWorker 10.5GBMetricsGrafanaWorker 10.5GBDashboardsNGINX IngressWorker 20.25GBK8s IngressLokiWorker 20.5GBLog aggregationHelmWorker 30.5GBPackage mgmtFluxCDWorker 30.5GBGitOps CD

Summary:
BeforeAfterOS Disk295GB265GBData Disk340GB340GBRAM (VMs/LXCs)20.5GB19GBProxmox host2GB2GBTotal RAM used~22.5GB~21GBBuffer~1.5GB~3GBvCPU1919

---

Production Environment (64GB RAM)
ResourceTypeOS DiskData DiskRAMvCPUPurposeFreeIPAVM25GB30GB4GB2Identity mgmtK8s Master 1VM25GB-4GB2Control planeK8s Master 2VM25GB-4GB2Control planeK8s Master 3VM25GB-4GB2Control planeK8s Worker 1VM25GB150GB8GB4Prom + GrafanaK8s Worker 2VM25GB150GB8GB4NGINX Ingress + LokiK8s Worker 3VM25GB150GB8GB4Helm + FluxCDVault 1LXC15GB30GB2GB2Secrets mgmtVault 2LXC15GB30GB2GB2Secrets mgmtVault 3LXC15GB30GB2GB2Secrets mgmtNGINXLXC15GB-1GB2Reverse proxyAnsibleLXC15GB-1.5GB2AutomationGH RunnerLXC15GB30GB1.5GB4GitHub Actions

Pod Distribution:
PodWorkerRAMvCPUPurposePrometheusWorker 11.5GB1MetricsGrafanaWorker 11GB0.5DashboardsNGINX IngressWorker 20.5GB1K8s IngressLokiWorker 21.5GB1Log aggregationHelmWorker 31GB0.5Package mgmtFluxCDWorker 31GB0.5GitOps CD

Summary:
Dev (24GB)Prod (64GB)OS Disk265GB265GBData Disk340GB570GBRAM allocated19GB49GBProxmox host2GB4GBTotal used~21GB~53GBBuffer~3GB~11GBvCPU1935
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
