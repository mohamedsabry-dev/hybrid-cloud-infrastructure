# Proxmox Bootstrap Scripts

Initial setup scripts for Proxmox VE servers. Run once after a fresh Proxmox
installation on each host.

> **Design notes & reasoning** — for how these scripts grew from a manual-first run,
> why `bootstrap.sh` and `network-setup.sh` are split (SSH-disconnect risk),
> why Terraform gets its own long-lived Proxmox token, and what the scripts
> deliberately do NOT do, see [`DESIGN.md`](DESIGN.md).
>
> **Run commands + prerequisites** — see [`bootstrap-operation-guide.txt`](bootstrap-operation-guide.txt).

## Files in this folder

| File | Description |
|------|-------------|
| `bootstrap.sh` | Core system setup (repos, users, NTP) |
| `network-setup.sh` | Network configuration (WiFi, VLANs, bridges) |
| `mail-config.sh` | Email notifications via Gmail SMTP |
| `vmbr1-vlan40-setup.txt` | Reference: VLAN 40 storage bridge setup |
| `bootstrap-operation-guide.txt` | Run order + per-script description + prerequisites |
| `mail-config-guide.txt` | Full Gmail SMTP relay manual setup (App Password, postfix config) |

## Environment Differences

| Setting | Dev | Prod |
|---------|-----|------|
| Admin user | `admin_dev` | `admin_prod` |
| Terraform user | `tf_dev` | `tf_prod` |
| WiFi interface | `wlp1s0` | `wlp4s0` |
| Management IP | `10.0.5.110` | `10.0.5.100` |
| Storage IP | `10.0.40.110` | `10.0.40.100` |
| Service VLANs | `60-65` | `50-55` |
| Hostname | `pve-dev` | `pve-prod` |

## Related

- [`DESIGN.md`](DESIGN.md) — iteration history, split reasoning, Terraform token rationale
- [`bootstrap-operation-guide.txt`](bootstrap-operation-guide.txt) — run order + commands
- [`mail-config-guide.txt`](mail-config-guide.txt) — Gmail SMTP relay setup
- [`../README.md`](../README.md) — proxmox parent scope
