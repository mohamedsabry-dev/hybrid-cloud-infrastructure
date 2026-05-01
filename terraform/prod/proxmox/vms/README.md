# Proxmox Virtual Machines — PROD

Terraform modules that provision the VM side of the Proxmox fleet:
golden-image source VM, FreeIPA VM, K8s masters, K8s workers.

For the clone-then-template design and rationale, see [`DESIGN.md`](DESIGN.md).
For the setup + refresh commands, see [`golden-image-operation-guide.txt`](golden-image-operation-guide.txt).

---

## Modules

| Module | Description | Tags |
|--------|-------------|------|
| `golden-image` | Rocky Linux 10.1 source VM (OS installed from ISO) | `vm, golden, template, prod` |
| `freeipa` | FreeIPA identity + DNS server | `vm, freeipa, identity, prod` |
| `k8s_masters` | Kubernetes control plane (3 nodes) | `vm, k8s-master, kubernetes, prod` |
| `k8s_workers` | Kubernetes workers (3 nodes, with second NIC on VLAN 40 for CSI-NFS) | `vm, k8s-worker, kubernetes, prod` |
| `testing` | 2 throwaway VMs for DR break/fix testing (VLAN 55, not in boot order) | `vm, test, linux, prod` |

Template flow: `golden-image` → cloned manually to VMID 9001 (not Terraform-managed)
→ `freeipa` / `k8s_masters` / `k8s_workers` / `testing` clone from 9001.

### Testing VMs — why they exist

Two disposable VMs (test1, test2) for running risky Linux operations — filesystem corruption, kernel-level recovery, boot failure DR scenarios — without touching any production workload. Placed on VLAN 55 (the external-facing VLAN, same as Nginx) rather than internal-sensitive VLANs. Ansible SSH key injected so I can jump to them from VPN without extra setup, which matters for operating from outside the home network. Second NIC on VLAN 40 (storage) attached just in case I need NFS access later.

Both VMs are `started = false` and `on_boot = false` — excluded from the Proxmox boot order entirely. They only come up when I manually start them for a test session.

## Tags convention

Every VM is tagged `[type, service, category, environment]`:

- `type` — resource type, always `vm`
- `service` — service name (`freeipa`, `k8s-master`, `k8s-worker`, `golden`)
- `category` — functional category (`identity`, `kubernetes`, `template`)
- `environment` — `dev` or `prod`

## Module outputs

| Module | Outputs |
|--------|---------|
| `golden-image` | `vm_id`, `name`, `node`, `status`, `setup_instructions`, `clone_command` |
| `freeipa` | `vm_id`, `name`, `ip` |
| `k8s_masters` | per-master `vm_id`, `name`, `ip` |
| `k8s_workers` | per-worker `vm_id`, `name`, `ip` |
| `testing` | per-vm `vm_id`, `name`, `ip`, `storage_ip` |

## Environment differences (dev vs prod)

Only `variables.tf` differs:

| Variable | Dev | Prod |
|----------|-----|------|
| `tags[3]` | `dev` | `prod` |
| `node_name` | `pve-dev` | `pve-prod` |
| `proxmox_api_url` | `https://pve-dev.lab.local:8006` | `https://pve-prod.lab.local:8006` |
| IP ranges | `10.0.6x.x` | `10.0.5x.x` |
| `disks.data_disk.datastore_id` | `nas-dev-data` | `nas-prod-data` |
| Resource sizing | Lower (2GB RAM, 2 cores typical) | Higher (4–8GB RAM, 4 cores) |

## Related

- [`DESIGN.md`](DESIGN.md) — clone-then-template rationale, hardcoded-values policy, `ignore_changes = [clone]` reasoning
- [`golden-image-operation-guide.txt`](golden-image-operation-guide.txt) — commands (setup, deploy, refresh)
- [`../lxc/`](../lxc/) — LXC containers (different template pattern)
- [`../../../../troubleshooting/terraform/`](../../../../troubleshooting/terraform/) — TS cases (Proxmox clone disks, VM disk tracking, etc.)
