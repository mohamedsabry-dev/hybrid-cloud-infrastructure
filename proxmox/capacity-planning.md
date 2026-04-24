⚠️  LEGACY PLAN
This was the initial resource allocation baseline. Actual deployment adapted as needed.
For the dev server: masters adjusted to 2.5GB RAM, Vault nodes to 0.5GB, workers to 3.25GB.
And it keep changing based on needs:
latest 25 April >> k8s masters and workers on dev all 2.75GB // k8s master on prod 5GB , worker 7 GB 

================================================================================
RESOURCE PLANNING
================================================================================

ENVIRONMENT OVERVIEW
--------------------
                Dev Server              Prod Server         NAS
CPU             Ryzen 7 7730U (8c/16t)  Ryzen 7 7435HS      —
RAM             24GB                    64GB                —
Local Storage   500GB NVMe              500GB NVMe          2x2TB RAID1 (~1.8TB usable)
Usage           Light / learning        Primary workloads   Shared storage


================================================================================
DEV SERVER ALLOCATION (24GB RAM)
================================================================================

Resource          Type  OS Disk     Data Disk   RAM      vCPU
--------------    ----  --------    ---------   ------   ----
FreeIPA           VM    25GB        25GB        2GB      2
K8s Master x3     VM    25GB each   —           2GB ea   2 ea
K8s Worker x3     VM    25GB each   80GB each   2.75GB ea  2 ea
Vault x3          LXC   10GB each   5GB each    0.75GB ea  1 ea
NGINX             LXC   10GB        5GB         0.5GB    1
Ansible           LXC   10GB        5GB         0.5GB    1
GH Runner         LXC   15GB        5GB         0.5GB    1

Totals: ~22GB RAM used · 2GB buffer · 20 vCPU
        240GB OS (NVMe) · 295GB data (NAS)


================================================================================
PROD SERVER ALLOCATION (64GB RAM)
================================================================================

Resource          Type  OS Disk     Data Disk   RAM      vCPU
--------------    ----  --------    ---------   ------   ----
FreeIPA           VM    25GB        25GB        3GB      2
K8s Master x3     VM    25GB each   —           4GB ea   2 ea
K8s Worker x3     VM    25GB each   80GB each   8GB ea   4 ea
Vault x3          LXC   10GB each   5GB each    0.75GB ea  1 ea
NGINX             LXC   10GB        5GB         0.5GB    1
Ansible           LXC   10GB        5GB         0.5GB    1
GH Runner         LXC   15GB        5GB         0.5GB    1

Totals: ~47GB RAM used · 17GB buffer · 26 vCPU
        240GB OS (NVMe) · 295GB data (NAS)


================================================================================
NAS STORAGE ALLOCATION (1.8TB Total)
================================================================================

Share           Environment   Size    Content
-----------     -----------   ----    -------
shared-iso      Both          50GB    ISO images, templates
dev-storage     Dev only      300GB   Dev data disks
prod-storage    Prod only     300GB   Prod data disks
PBS backups     Both          650GB   Proxmox Backup Server
                              ------
TOTAL                         1300GB  (~500GB buffer)


================================================================================
NFS MOUNTS
================================================================================

DEV Server (10.0.5.110)
  nas-iso       → 10.0.40.120:/volume1/shared-iso    (ISO image, Container template)
  nas-dev-data  → 10.0.40.120:/volume1/dev-storage   (Disk image, Container, Backup)

PROD Server (10.0.5.100)
  nas-iso       → 10.0.40.120:/volume1/shared-iso    (ISO image, Container template)
  nas-prod-data → 10.0.40.120:/volume1/prod-storage  (Disk image, Container, Backup)


================================================================================
STORAGE LAYOUT
================================================================================

OS disks   → Local NVMe (fast boot/performance)
Data disks → NAS NFS share (persistent, shared across VMs)
ISOs       → NAS shared-iso (uploaded once, used by both servers)
Backups    → NAS PBS share (centralized backup)


================================================================================
ISO IMAGES
================================================================================

proxmox-ve_9.1-1.iso                        ~1.2GB   Proxmox VE
Rocky-10.1-x86_64-minimal.iso               ~1.5GB   Rocky Linux VMs
rockylinux-10-default_20251001_amd64.tar.xz ~150MB   Rocky Linux LXC template


================================================================================
BACKUP STRATEGY
================================================================================

NAS Data               → NAS-level snapshots + RAID 1
NAS PBS                → RAID 1 redundancy


================================================================================
NOTES
================================================================================

- vCPU overcommit acceptable for home lab workloads
- Thin provisioning used — disk sizes are max limits
- Pod placement managed dynamically by Kubernetes scheduler