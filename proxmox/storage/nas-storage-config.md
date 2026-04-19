# NAS Storage Configuration

**Device:** ASUSTOR FLASHSTOR 6 FS6706T
**Capacity:** 1.8TB usable (EXT4)
**Management:** https://10.0.5.120:8001

---

## Network Interfaces

| Port | IP | Gateway | Speed | Purpose |
|------|-----|---------|-------|---------|
| LAN 2 | 10.0.5.120 | 10.0.5.1 | 100Mb | Management (VLAN 5) |
| LAN 1 | 10.0.40.120 | None | 1000Mb | Storage (VLAN 40) |

**Connection Paths:**
- LAN 2 → AC750 AP → MikroTik Port 7 → VLAN 5 (untagged)
- LAN 1 → FS308GP Port 6 → VLAN 40 (tagged, L2 isolated, no router hop)

The router was previously a TP-Link ER605 (mgmt path went via ER605 Port 3). See [`../../network/DESIGN.md`](../../network/DESIGN.md) for the ER605 → MikroTik migration story.

---

## VLAN 40 - Storage Network

Isolated L2 network on the FS308GP managed switch (no router routing; Proxmox hosts, NAS, and k8s workers talk to each other directly over L2).

| Device | IP | Role |
|--------|-----|------|
| NAS | 10.0.40.120 | NFS Server |
| Prod Proxmox host | 10.0.40.100 | NFS Client (stor0 interface) |
| Prod K8s Worker 1 | 10.0.40.101 | NFS Client — CSI-NFS for k8s PVs (second NIC) |
| Prod K8s Worker 2 | 10.0.40.102 | NFS Client — CSI-NFS for k8s PVs (second NIC) |
| Prod K8s Worker 3 | 10.0.40.103 | NFS Client — CSI-NFS for k8s PVs (second NIC) |
| Dev Proxmox host | 10.0.40.110 | NFS Client (stor0 interface) |
| Dev K8s Worker 1 | 10.0.40.201 | NFS Client — CSI-NFS for k8s PVs (second NIC) |
| Dev K8s Worker 2 | 10.0.40.202 | NFS Client — CSI-NFS for k8s PVs (second NIC) |
| Dev K8s Worker 3 | 10.0.40.203 | NFS Client — CSI-NFS for k8s PVs (second NIC) |

K8s worker VMs each have a second NIC on VLAN 40 — added after initial setup when CSI-NFS was introduced so pods on workers could mount NFS PVs directly without proxying through the Proxmox host. See [`../../network/ip-planning.txt`](../../network/ip-planning.txt) for the full VLAN 40 address plan.

---

## NAS Firewall (ADM Defender)

**LAN 2 (Management):**
- Allow 192.168.0.223
- Allow 10.0.5.223
- Deny All

**LAN 1 (Storage):**
- Allow 10.0.40.100 (Prod Proxmox host)
- Allow 10.0.40.101-.103 (Prod K8s workers, CSI-NFS)
- Allow 10.0.40.110 (Dev Proxmox host)
- Allow 10.0.40.201-.203 (Dev K8s workers, CSI-NFS)
- Deny All

*Result: Only Mac Mini manages the NAS over the mgmt plane. On the storage plane, only the two Proxmox hosts + the six k8s workers can reach the NFS service.*

---

## NFS Shares

| Share | NFS Path | Access | Content |
|-------|----------|--------|---------|
| shared-iso | /volume1/shared-iso | 10.0.40.100 + 10.0.40.110 (RW) | ISOs, CT templates (shared between hosts) |
| prod-storage | /volume1/prod-storage | 10.0.40.100 only (RW) | Prod VM/LXC images, rootdir, non-k8s backups |
| dev-storage | /volume1/dev-storage | 10.0.40.110 only (RW) | Dev VM/LXC images, rootdir, non-k8s backups |
| k8s-prod | /volume1/k8s-prod | 10.0.40.101-103 (RW) | Prod k8s CSI-NFS PersistentVolumes (pod data) |
| k8s-dev | /volume1/k8s-dev | 10.0.40.201-203 (RW) | Dev k8s CSI-NFS PersistentVolumes (pod data) |
| Backups | /volume1/Backups | 10.0.40.100 + 10.0.40.110 (RW) | vzdump backups from both Proxmox hosts |

**NFS Settings:** root Mapping = root (0), Async = Yes

Note: `k8s-dev` and `k8s-prod` are exposed directly to the worker VMs (via their VLAN 40 second NIC), not through the Proxmox hosts. This means pod PVs get straight L2 access to NAS storage without the Proxmox hypervisor in the critical path — important for CSI-NFS performance and for avoiding the hypervisor becoming a bottleneck under pod-mount load.

---

## SMB Share - Configuration Backups

Dedicated share for Proxmox environment configuration backups (not VM/LXC data).

| Setting | Value |
|---------|-------|
| Name | Backups |
| Description | ENV Backup Files |
| Volume | Volume 1 (EXT4) |
| Network Recycle Bin | Yes |
| Admin Only Access | Yes |
| Anonymous Access | Deny |
| Permission Mode | Traditional |

**Purpose:** Store Proxmox config backups from both environments. Accessible via SMB from management network only.

**Access:** `smb://10.0.5.120/Backups` (admin credentials required)

---

## Proxmox Storage Config

**Managed via Terraform:** `terraform/dev/proxmox/storage/nas/` and `terraform/prod/proxmox/storage/nas/`

**DEV Server:**

| Storage ID | NFS Export | Content | Retention |
|------------|------------|---------|-----------|
| nas-iso | /volume1/shared-iso | iso, vztmpl | - |
| nas-dev-data | /volume1/dev-storage | images, rootdir, backup | keep_last=5 |
| nas-backups | /volume1/Backups | backup, rootdir | keep_last=5 |

**PROD Server:**

| Storage ID | NFS Export | Content | Retention |
|------------|------------|---------|-----------|
| nas-iso | /volume1/shared-iso | iso, vztmpl | - |
| nas-prod-data | /volume1/prod-storage | images, rootdir, backup | keep_last=5 |
| nas-backups | /volume1/Backups | backup, rootdir | keep_last=5 |

**Verify:** `showmount -e 10.0.40.120`

> Note: Upload ISOs to `shared-iso/template/iso/` (not root)

---

## Capacity Allocation

| Share | Size | Content |
|-------|------|---------|
| shared-iso | ~50GB | ISOs, container templates |
| prod-storage | ~500GB | PROD VM images, container rootfs |
| dev-storage | ~300GB | DEV VM images, container rootfs |
| k8s-prod | (carved from Volume 1) | Prod k8s CSI-NFS PVs (pod-managed quotas) |
| k8s-dev | (carved from Volume 1) | Dev k8s CSI-NFS PVs (pod-managed quotas) |
| Backups | ~200GB | vzdump backups (both envs) |
| Reserved | remaining | Future expansion |
