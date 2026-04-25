# Storage

NAS-backed shared storage for the Proxmox fleet and the Kubernetes CSI-NFS layer. One physical NAS (ASUSTOR FLASHSTOR 6 FS6706T) on the isolated VLAN 40 L2 network, serving NFS shares to the two Proxmox hosts and to the six k8s worker VMs (three per env).

> **Design notes & reasoning** — for why OS disks stay on local Proxmox storage (not on the NAS), why k8s workers get a dedicated VLAN 40 second NIC instead of proxying through the hypervisor, and the IP-range convention that makes dev/prod collision on VLAN 40 impossible, see [`DESIGN.md`](DESIGN.md).

## Files

| File | Contents |
|------|----------|
| [`nas-storage-config.md`](nas-storage-config.md) | Concrete NAS config — interfaces, firewall, NFS shares, Proxmox storage IDs, capacity allocation |
| [`DESIGN.md`](DESIGN.md) | Why the storage is split the way it is (local OS disks + NAS for data/PVs/backups), why each k8s worker has its own VLAN 40 NIC |

## Quick reference

- **Device:** ASUSTOR FS6706T, 1.8 TB EXT4, management at `https://10.0.5.120:8001`
- **Storage VLAN:** 40 (10.0.40.0/24) — L2-isolated on FS308GP switch
- **NFS shares:** `shared-iso`, `prod-storage`, `dev-storage`, `k8s-prod`, `k8s-dev`, `Backups`
- **Access pattern:** Proxmox hosts mount `{env}-storage` + `shared-iso` + `Backups`; k8s workers mount `k8s-{env}` directly on their VLAN 40 second NIC for CSI-NFS
- **Managed via Terraform:** [`../../terraform/*/proxmox/storage/nas/`](../../terraform/)
