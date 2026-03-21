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
- LAN 2 → AC750 AP → ER605 Port 3 → VLAN 5 (untagged)
- LAN 1 → FS308GP Port 6 → VLAN 40 (tagged, L2 isolated, no gateway)

---

## VLAN 40 - Storage Network

Isolated L2 network on FS308GP managed switch (no ER605 routing)

| Device | IP | Role |
|--------|-----|------|
| NAS | 10.0.40.120 | NFS Server |
| Prod Proxmox | 10.0.40.100 | NFS Client (stor0 interface) |
| Dev Proxmox | 10.0.40.110 | NFS Client (stor0 interface) |

---

## NAS Firewall (ADM Defender)

**LAN 2 (Management):**
- Allow 192.168.0.223
- Allow 10.0.5.223
- Deny All

**LAN 1 (Storage):**
- Allow 10.0.40.100 (Prod)
- Allow 10.0.40.110 (Dev)
- Deny All

*Result: Only Mac Mini manages NAS. Proxmox servers access storage only.*

---

## NFS Shares

| Share | NFS Path | Access |
|-------|----------|--------|
| shared-iso | /volume1/shared-iso | 10.0.40.100 + 10.0.40.110 (RW) |
| prod-storage | /volume1/prod-storage | 10.0.40.100 only (RW) |
| dev-storage | /volume1/dev-storage | 10.0.40.110 only (RW) |

**NFS Settings:** root Mapping = root (0), Async = Yes

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

**DEV Server** (Datacenter → Storage → Add → NFS):
- `nas-iso` : 10.0.40.120:/volume1/shared-iso (ISO, CT template)
- `nas-dev-data` : 10.0.40.120:/volume1/dev-storage (Disk, CT, Backup)

**PROD Server:**
- `nas-iso` : 10.0.40.120:/volume1/shared-iso (ISO, CT template)
- `nas-prod-data` : 10.0.40.120:/volume1/prod-storage (Disk, CT, Backup)

**Verify:** `showmount -e 10.0.40.120`

> Note: Upload ISOs to `shared-iso/template/iso/` (not root)

---

## Capacity Allocation

| Share | Size | Content |
|-------|------|---------|
| shared-iso | ~50GB | ISOs, container templates |
| prod-storage | ~600GB | PROD VMs, backups |
| dev-storage | ~400GB | DEV VMs, backups |
| Reserved | ~750GB | Future expansion |
