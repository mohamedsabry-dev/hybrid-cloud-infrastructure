# Proxmox Virtual Machines — DEV

Terraform modules that provision the VM side of the Proxmox fleet:
golden-image source VM, FreeIPA VM, K8s masters, K8s workers.

For the clone-then-template design and rationale, see [`DESIGN.md`](DESIGN.md).
For the setup + refresh commands, see [`golden-image-operation-guide.txt`](golden-image-operation-guide.txt).

---

## Modules

| Module | Description | Tags |
|--------|-------------|------|
| `golden-image` | Rocky Linux 10.1 source VM (OS installed from ISO) | `vm, golden, template, dev` |
| `freeipa` | FreeIPA identity + DNS server | `vm, freeipa, identity, dev` |
| `k8s_masters` | Kubernetes control plane (3 nodes) | `vm, k8s-master, kubernetes, dev` |
| `k8s_workers` | Kubernetes workers (3 nodes, with second NIC on VLAN 40 for CSI-NFS) | `vm, k8s-worker, kubernetes, dev` |

Template flow: `golden-image` → cloned manually to VMID 9001 (not Terraform-managed)
→ `freeipa` / `k8s_masters` / `k8s_workers` clone from 9001.

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
