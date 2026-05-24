# Proxmox Infrastructure

On-prem hypervisor layer — two physical Proxmox hosts (dev + prod), a dedicated NAS, and a physical router. Hosts are configured via [`bootstrap_proxmox/`](bootstrap_proxmox/) scripts and manual commands. VMs/LXCs on top are provisioned by [`../terraform/*/proxmox/`](../terraform/).

> **Design notes & reasoning** — for the iteration history behind this layout (why two physical hosts instead of one nested setup, why hardware NAS over TrueNAS VM, how the bootstrap scripts were built), see [`DESIGN.md`](DESIGN.md).
>
> **Capacity planning** — resource allocation (CPU / RAM / disk) across the VMs and LXCs that run on these hosts is in [`capacity-planning.md`](capacity-planning.md).

---

## Server details

| Environment | Hostname | Management IP | Storage IP | API URL |
|-------------|----------|---------------|------------|---------|
| PROD | pve-prod.lab.local | 10.0.5.100 | 10.0.40.100 | https://pve-prod.lab.local:8006 |
| DEV  | pve-dev.lab.local  | 10.0.5.110 | 10.0.40.110 | https://pve-dev.lab.local:8006  |

Each host runs Proxmox VE 9.x with three physically separate traffic planes:

- **Management** — built-in WiFi, joining `unified_mgmt` SSID (AC750 AP), VLAN 5
- **Service VLAN trunk** (`svc0`) — USB-Ethernet adapter, VLANs 50-55 (prod) / 60-65 (dev)
- **Storage VLAN 40** (`stor0`) — separate USB-Ethernet adapter, L2-isolated to the NAS

## Folder structure

| Folder | Purpose |
|--------|---------|
| [`bootstrap_proxmox/`](bootstrap_proxmox/) | Initial Proxmox host setup — `bootstrap.sh`, `network-setup.sh`, mail config |
| [`golden_templates/`](golden_templates/) | VM / LXC golden image preparation scripts |
| [`backup/`](backup/) | Proxmox config + workload backup scripts and configuration |
| [`disaster_recovery/`](disaster_recovery/) | Host-layer DR — power + thermal monitors, hardware replacement runbook, full-host recovery. Not chaos tests (those live in [`../disaster-recovery/`](../disaster-recovery/)) |
| [`storage/`](storage/) | NAS storage configuration |

## Quick start

```bash
# 1. Bootstrap host (repos, users, NTP, chrony, subscription-nag removal)
./bootstrap_proxmox/bootstrap.sh dev   # or prod

# 2. Network (WiFi mgmt + vmbr0 service trunk + vmbr1.40 storage)
./bootstrap_proxmox/network-setup.sh dev   # or prod
reboot

# 3. Optional: email notifications via Gmail SMTP
./bootstrap_proxmox/mail-config.sh
```

After bootstrap, create golden templates (VM and LXC) via `golden_templates/`, then Terraform takes over from [`../terraform/*/proxmox/`](../terraform/).

## Related

- [`DESIGN.md`](DESIGN.md) — the story behind this layer (iteration history, decision trail, bootstrap-script origin)
- [`capacity-planning.md`](capacity-planning.md) — resource allocation for VMs/LXCs running on these hosts
- [`../terraform/*/proxmox/`](../terraform/) — Terraform resources provisioned on these hosts
- [`../ansible/`](../ansible/) — configuration applied after provisioning
- [`../network/README.md`](../network/README.md) — physical network these hosts connect into
